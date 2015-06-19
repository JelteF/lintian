#!/usr/bin/perl

# Copyright © 2014 Jakub Wilk <jwilk@jwilk.net>

# This program is free software.  It is distributed under the terms of
# the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, you can find it on the World Wide
# Web at <https://www.gnu.org/copyleft/gpl.html>, or write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.

use strict;
use warnings;
use autodie;

use Getopt::Long();

use Lintian::Check qw(check_spelling check_spelling_picky);
use Lintian::Data;
use Lintian::Profile;
use Lintian::Util qw(slurp_entire_file);

our $VERSION = '0.0';

sub show_version {
    print "spellintian $VERSION\n";
    exit 0;
}

sub show_help {
    print <<'EOF' ;
Usage: spellintian [--picky] [FILE...]
EOF
    exit 0;
}

sub spellcheck {
    my ($path, $picky, $text) = @_;
    my $prefix = $path ? "$path: " : q{};
    my $spelling_error_handler = sub {
        my ($mistake, $correction) = @_;
        print "$prefix$mistake -> $correction\n";
    };
    check_spelling($text, $spelling_error_handler);
    if ($picky) {
        check_spelling_picky($text, $spelling_error_handler);
    }
    return;
}

sub main {
    my $profile = Lintian::Profile->new;
    Lintian::Data->set_vendor($profile);

    my $picky = 0;
    {
        local $SIG{__WARN__} = sub {
            my ($message) = @_;
            $message =~ s/\A([[:upper:]])/lc($1)/e;
            $message =~ s/\n+\z//;
            print {*STDERR} "spellintian: $message\n";
            exit(1);
        };
        Getopt::Long::Configure('gnu_getopt');
        Getopt::Long::GetOptions(
            'picky'   => \$picky,
            'h|help'  => \&show_help,
            'version' => \&show_version,
        ) or exit(1);
    }

    if (not @ARGV) {
        my $text = slurp_entire_file(*STDIN);
        spellcheck(undef, $picky, $text);
    } else {
        for my $path (@ARGV) {
            my $text;
            die("$path is a directory\n") if not -f $path;
            $text = slurp_entire_file($path);
            spellcheck($path, $picky, $text);
        }
    }
    return;
}

END {
    close(STDOUT);
    close(STDERR);
}

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
