package UKIRT::Sequence::Config::AIM;

=head1 NAME

UKIRT::Sequence::Config::AIM - AIM specific config file parsing

=head1 SYNOPSIS

 use UKIRT::Sequence::Config::AIM;

 $cfg = new AIM::Sequence::Config::AIM;
 $cfg->getItem( "filter" );

=head1 DESCRIPTION

=cut

use 5.006;
use strict;
use Carp;
use warnings;

use base qw/ UKIRT::Sequence::Config /;
use vars qw/ $VERSION /;

$VERSION = sprintf("%d", q$Revision$ =~ /(\d+)/);

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new object. Takes a file name or an array of lines from a config file.

  $cfg = new UKIRT::Sequence::Config::AIM( Lines => \@lines );
  $cfg = new UKIRT::Sequence::Config::AIM( File => $file );

See C<UKIRT::Sequence::Config> for a generic interface to this class.

=back

=begin __PRIVATE_METHODS__

=head1 PRIVATE METHODS

=over 4

=item B<_parse_config_line>

Given a line, splits it into keyword and value.

  ($key, $value) = $cfg->_parse_config_line( $line );

Returns an empty list if no keyword is present.

=cut

sub _parse_config_line {
  my $self = shift;
  my $line = shift;

  return() if $line =~ /:/;

  # remove leading and trailing space
  $line =~ s/^\s+//;
  $line =~ s/\s+$//;

  return () unless length($line);

  # split into two chunks (keys will include spaces)
  my ($value, $key) = split /\s+/,$line, 2;
  return ($value, $key);
}

=back


=end __PRIVATE_METHODS__

=head1 SEE ALSO

L<UKIRT::Sequence>, L<UKIRT::Sequence::Config::ORAC>.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>.

Copyright (C) 2003-2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

1;
