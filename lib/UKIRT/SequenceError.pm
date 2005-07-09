package UKIRT::SequenceError;

=head1 NAME

UKIRT::SequenceError - Exceptions associated with a UKIRT::Sequence

=head1 SYNOPSIS

  use UKIRT::SequenceError;
  use UKIRT::SequenceError qw/ :try /;

  throw UKIRT::SequenceError::MissingTarget("No target");


=head1 DESCRIPTION

Base class for C<UKIRT::Sequence> exceptions. Inherits from the
L<Error|Error> class. See C<Error> for more information.

=head1 PROCEDURAL INTERFACE

C<SCUBA::ODFError> exports subroutines to perform exception
handling. These will be exported if the C<:try> tag is used in the
C<use> line.


=cut

use Error;
use warnings;
use strict;

use vars qw/ $VERSION /;

'$Revision$ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

# Class hierarchy
use base qw/ Error::Simple /;

=head1 EXCEPTIONS

The following exceptions are available:

=over 4

=item B<UKIRT::SequenceError::BadArgs>

Bad arguments have been supplied to a method.

=cut

package UKIRT::SequenceError::BadArgs;
use base qw/ UKIRT::SequenceError /;

=item B<UKIRT::SequenceError::FileError>

Error occurred when opening a file.

=cut

package UKIRT::SequenceError::FileError;
use base qw/ UKIRT::SequenceError /;

=item B<UKIRT::SequenceError::MissingTarget>

An attempt has been made to verify the state of the sequence
but the sequence is missing target information.

=cut

package UKIRT::SequenceError::MissingTarget;
use base qw/ UKIRT::SequenceError /;

=item B<UKIRT::SequenceError::UnrecognizedConfig>

The supplied config could not be understood by the constructor.

=cut

package UKIRT::SequenceError::UnrecognizedConfig;
use base qw/ UKIRT::SequenceError /;

=back

=head1 SEE ALSO

L<Error>, L<OMP::Error>, L<SCUBA::ODFError>.

=head1 AUTHORS

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>

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
