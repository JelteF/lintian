# source-copyright-file -- lintian check script -*- perl -*-

# Copyright (C) 2011 Jakub Wilk
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

package Lintian::source_copyright;

use strict;
use warnings;
use autodie;

use List::MoreUtils qw(any);
use Text::Levenshtein qw(distance);

use Lintian::Relation::Version qw(versions_compare);
use Lintian::Tags qw(tag);
use Lintian::Util qw(parse_dpkg_control slurp_entire_file);

my $dep5_last_normative_change = '0+svn~166';
my $dep5_last_overhaul = '0+svn~148';
my %dep5_renamed_fields = (
    'format-specification' => 'format',
    'maintainer' => 'upstream-contact',
    'upstream-maintainer' => 'upstream-contact',
    'contact' => 'upstream-contact',
    'name' => 'upstream-name',
);

sub run {

my (undef, undef, $info) = @_;

my $copyright_filename = $info->debfiles('copyright');

if (-l $copyright_filename) {
    tag 'debian-copyright-is-symlink';
    return;
}

if (not -f $copyright_filename) {
    my @pkgs = $info->binaries;
    tag 'no-debian-copyright';
    $copyright_filename = undef;
    if (scalar @pkgs == 1) {
        # If debian/copyright doesn't exist, and the only a single binary
        # package is built, there's a good chance that the copyright file is
        # available as debian/<pkgname>.copyright.
        $copyright_filename = $info->debfiles ($pkgs[0] . '.copyright');
        if (not -f $copyright_filename or -l $copyright_filename) {
            $copyright_filename = undef;
        }
    }
}

return unless defined $copyright_filename;

my $contents = slurp_entire_file ($copyright_filename);
study $contents;

my @dep5;
my @lines;

if ($contents =~ m{
    (^ | \n)
    (?i: format(:|[-\s]spec) )
    (?: . | \n\s+ )*
    (?: /dep[5s]?\b | \bDEP-?5\b | [Mm]achine-readable\s(?:license|copyright) | /copyright-format/ | CopyrightFormat | VERSIONED_FORMAT_URL )
}x)
{
    # Before trying to parse the copyright as Debian control file, try to
    # determine the format URI.
    my $first_para = $contents;
    $first_para =~ s,^#.*,,mg;
    $first_para =~ s,[ \t]+$,,mg;
    $first_para =~ s,^\n+,,g;
    $first_para =~ s,\n\n.*,\n,s; #;; hi emacs
    $first_para =~ s,\n?[ \t]+, ,g;
    $first_para =~ m,^Format(?:-Specification)?:\s*(.*),mi;
    my $uri = $1;
    $uri =~ s/^([^#\s]+)#/$1/ if defined $uri; # strip fragment identifier
    if (defined $uri) {
        my $original_uri = $uri;
        my $version;
        if ($uri =~ m,\b(?:rev=REVISION|VERSIONED_FORMAT_URL)\b,) {
            tag 'boilerplate-copyright-format-uri', $uri;
        }
        elsif ($uri =~ s,http://wiki\.debian\.org/Proposals/CopyrightFormat\b,,) {
            $version = '0~wiki';
            $uri =~ m,^\?action=recall&rev=(\d+)$, and $version = "$version~$1";
        }
        elsif ($uri =~ m,^http://dep\.debian\.net/deps/dep5/?$,) {
            $version = '0+svn';
        }
        elsif ($uri =~ s,^http://svn\.debian\.org/wsvn/dep/web/deps/dep5\.mdwn\b,,) {
            $version = '0+svn';
            $uri =~ m,^\?(?:\S+[&;])?rev=(\d+)(?:[&;]\S+)?$, and $version = "$version~$1";
        }
        elsif ($uri =~ s,^http://(?:svn|anonscm)\.debian\.org/viewvc/dep/web/deps/dep5\.mdwn\b,,) {
            $version = '0+svn';
            $uri =~ m,^\?(?:\S+[&;])?(?:pathrev|revision|rev)=(\d+)(?:[&;]\S+)?$, and $version = "$version~$1";
        }
        elsif ($uri =~ m,^http://www\.debian\.org/doc/(?:packaging-manuals/)?copyright-format/(\d+\.\d+)/?$,) {
            $version = $1;
        }
        else {
            tag 'unknown-copyright-format-uri', $original_uri;
        }
        if (defined $version) {
            if ($version =~ m,wiki,) {
                    tag 'wiki-copyright-format-uri', $original_uri;
            }
            elsif ($version =~ m,svn$,) {
                tag 'unversioned-copyright-format-uri', $original_uri;
            }
            elsif (versions_compare $version, '<<', $dep5_last_normative_change) {
                tag 'out-of-date-copyright-format-uri', $original_uri;
            }
            if (versions_compare $version, '>=', $dep5_last_overhaul) {
                # We are reasonably certain that we're dealing with an up-to-date
                # DEP-5 format. Let's try to do more strict checks.
                eval {
                    open(my $fd, '<', \$contents);
                    @dep5 = parse_dpkg_control ($fd, 0, \@lines);
                    close($fd);
                };
                if ($@) {
                    chomp $@;
                    $@ =~ s/^syntax error at //;
                    tag 'syntax-error-in-dep5-copyright', $@;
                }
            }
        }
    }
    else {
        tag 'unknown-copyright-format-uri';
    }
}

if (@dep5) {
    my $first_para = shift @dep5;
    my %standalone_licenses;
    my %required_standalone_licenses;
    for my $field (keys %{$first_para}) {
        my $renamed_to = $dep5_renamed_fields{$field};
        if (defined $renamed_to) {
            tag 'obsolete-field-in-dep5-copyright', $field, $renamed_to, "(paragraph at line $lines[0])";
        }
    }
    if (not defined $first_para->{'format'} and not defined $first_para->{'format-specification'}) {
        tag 'missing-field-in-dep5-copyright', 'format', "(paragraph at line $lines[0])";
    }
    for my $license (split_licenses($first_para->{'license'})) {
        $required_standalone_licenses{$license} = 1;
    }
    my $commas_in_files = 0;
    my $i = 0;
    for my $para (@dep5) {
        $i++;
        my $license = get_field ($para, 'license', $lines[$i]);
        my $files = get_field ($para, 'files', $lines[$i]);
        my $copyright = get_field ($para, 'copyright', $lines[$i]);

        if (not defined $files and defined $license and defined $copyright) {
            tag 'ambiguous-paragraph-in-dep5-copyright', "paragraph at line $lines[$i]";
            # If it is the first paragraph, it might be an instance of
            # the (no-longer) optional "first Files-field".
            $files = '*' if $i == 1;
        }

        if (defined $license and not defined $files) {
            # Standalone license paragraph
            if (not $license =~ m/\n/) {
                tag 'missing-license-text-in-dep5-copyright', lc $license, "(paragraph at line $lines[$i])";
            }
            ($license, undef) = split /\n/, $license, 2;
            for (split_licenses($license)) {
                $standalone_licenses{$_} = $i;
            }
        }
        elsif (defined $files) {
            # Files paragraph
            $commas_in_files = $i if not $commas_in_files and $files =~ /,/;
            if (defined $license) {
                for (split_licenses($license)) {
                    $required_standalone_licenses{$_} = $i;
                }
            }
            else {
                tag 'missing-field-in-dep5-copyright', "license (paragraph at line $lines[$i])";
            }
            if (not defined $copyright) {
                tag 'missing-field-in-dep5-copyright', "copyright (paragraph at line $lines[$i])";
            }
        }
        else {
            tag 'unknown-paragraph-in-dep5-copyright', 'paragraph at line', $lines[$i];
        }
    }
    if ($commas_in_files) {
        tag 'comma-separated-files-in-dep5-copyright', 'paragraph at line', $lines[$commas_in_files]
            unless any {m/,/} $info->sorted_index;
    }
    while ((my $license, $i) = each %required_standalone_licenses) {
        if (not defined $standalone_licenses{$license}) {
            tag 'missing-license-paragraph-in-dep5-copyright', $license, "(paragraph at line $lines[$i])";
        }
    }
    while ((my $license, $i) = each %standalone_licenses) {
        if (not defined $required_standalone_licenses{$license}) {
            tag 'unused-license-paragraph-in-dep5-copyright', $license, "(paragraph at line $lines[$i])";
        }
    }
}

return;
}

sub split_licenses {
    my ($_) = @_;
    return () unless defined;
    return () if /\n/;
    s/[(),]//;
    return map { "\L$_" } (split /\s++(?:and|or)\s++/);
}

sub get_field {
    my ($para, $field, $line) = @_;
    return $para->{$field} if exists $para->{$field};
    # Fall back to a "likely misspelling" of the field.
    foreach my $f (sort keys %$para) {
        if (distance ($field, $f) < 3) {
            tag 'field-name-typo-in-dep5-copyright', $f, '->', $field, "(paragraph at line $line)";
            return $para->{$f};
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
