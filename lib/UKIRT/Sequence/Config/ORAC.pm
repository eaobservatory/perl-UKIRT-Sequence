package UKIRT::Sequence::Config::ORAC;

=head1 NAME

UKIRT::Sequence::Config::ORAC - ORAC specific config file parsing

=head1 SYNOPSIS

 use UKIRT::Sequence::Config::ORAC;

 $cfg = new ORAC::Sequence::Config::ORAC;
 $cfg->getItem( "filter" );

=head1 DESCRIPTION

=cut

use 5.006;
use strict;
use Carp;
use warnings;

use base qw/ UKIRT::Sequence::Config /;
use vars qw/ $VERSION /;

$VERSION = 1.0;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new object. Takes a file name or an array of lines from a config file.

  $cfg = new UKIRT::Sequence::Config::ORAC( Lines => \@lines );
  $cfg = new UKIRT::Sequence::Config::ORAC( File => $file );

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
  # split into 3 since the "=" sign is in the middle surrounded
  # by spaces
  my ($key, undef, $value) = split /\s+/,$line, 3;
  return (defined $key ? ($key,$value) : () );
}

=back


=end __PRIVATE_METHODS__

=head1 SEE ALSO

L<UKIRT::Sequence>, L<UKIRT::Sequence::Config::AIM>.

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
