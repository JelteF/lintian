# symlinks -- lintian check script -*- perl -*-
#
# Copyright (C) 2011 Niels Thykier
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, you can find it on the World Wide
# Web at http://www.gnu.org/copyleft/gpl.html, or write to the Free
# Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston,
# MA 02110-1301, USA.

package Lintian::symlinks;
use strict;
use warnings;
use autodie;

use File::Basename qw(dirname);
use Lintian::Tags qw(tag);

sub run {

my ($pkg, undef, $info, $proc, $group) = @_;

my $ginfo = $group->info;
my @brokenlinks;
my @dindexes;

foreach my $file ($info->sorted_index) {
    if ($file->is_symlink){
        my $target = $file->link//''; # the link target
        my $path; # the target (from the pkg root)
        # Should not happen (too often) - but just in case
        next unless $target;
        $path = $file->link_normalized;
        if (not defined $path) {
            # Unresolvable link
            tag 'package-contains-unsafe-symlink', $file;
            next;
        }
        # Links to the package root is always going to exist (although
        # self-recursive and possibly not very useful)
        next if $path eq '';

        # Skip usr/share/doc/<pkg> - we got a separate check for
        # that.
        next if $file eq "usr/share/doc/$pkg";


        # Check if the destination is in the package itself
        next if $info->index ($path) || $info->index ("$path/");

        $target =~ s,^/++,,o; # strip leading slashes (for reporting)

        # Ignore links pointing to common things that may exist
        # even if they are not shipped by any binary from this
        # source package.
        next if $path =~ m@man/man\d/undocumented@o or
            $path =~ m@^etc/alternatives/@o or
            $path =~ m@^usr/share/javascript/(?:[^/]++/)++[^/]+\.js$@o or
            $path =~ m@^usr/share/fonts/[^/]++/.++$@o or # link to font dir or a font file
            $path =~ m@^usr/share/java/[^/]+\.jar$@o or
            $path eq 'lib/init/upstart-job';

        # Skip langpack links (used in Ubuntu) - after we check that
        # it appears to be consistent.
        if ($path =~ m,/([^/]+)-langpack/,o) {
            my $pre = $1;
            my $t = $path;
            $t =~ s,/\Q$pre\E-langpack/,/help/,;
            next if $t eq $file;
        }

        # Possibly broken symlink
        push @brokenlinks, [$file, $path, $target] unless $info->index ($path);
    }

}

return unless @brokenlinks;

# Check our dependencies:
foreach my $depproc (@{ $ginfo->direct_dependencies ($proc)}) {
    push @dindexes, $depproc->info;
}

BLINK:
foreach my $blink (@brokenlinks){
    my ($file, $path, $target) = @$blink;
    foreach my $dinfo (@dindexes){
        # Is it in our dependency?
        next BLINK if $dinfo->index ($path) || $dinfo->index ("$path/");
    }
    # nope - not found in any of our direct dependencies.
    if ($target =~ m/\*/) {
        # If it contains a "*" it probably a bad ln -s target/*.so link
        # expansion.
        tag 'package-contains-broken-symlink-wildcard', $file, $target
    } else {
        tag 'package-contains-broken-symlink', $file, $target
    }
}

return;
}

1;

# Local Variables:
# indent-tabs-mode: nil
# cperl-indent-level: 4
# End:
# vim: syntax=perl sw=4 sts=4 sr et
