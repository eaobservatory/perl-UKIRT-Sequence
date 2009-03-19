package UKIRT::Sequence::Config;

=head1 NAME

UKIRT::Sequence::Config -  Generic view of configuration information

=head1 SYNOPSIS



=head1 DESCRIPTION



=cut


use 5.006;
use strict;
use Carp;
use warnings;
use UKIRT::SequenceError qw/ :try /;

use UKIRT::Sequence::Config::ORAC;
use UKIRT::Sequence::Config::AIM;


use vars qw/ $VERSION /;

$VERSION = 1.0;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new object. Takes a filename.

  $cfg = new UKIRT::Sequence::Config( File => $file );

Will attempt to determine the correct class of configuration from
the file suffix. This is technically a factory constructor since you
will not receive an object blessed into this class.

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args = @_;

  # horrible hack because we have not done the subclassing
  # and factory constructor properly
  if ( $class eq __PACKAGE__ ) {
    # we are in the factory constructor

    throw UKIRT::SequenceError::BadArgs( "Must supply a filename to Config constructor" ) unless exists $args{File};

    if ( $args{File} =~ /\.conf$/i) {
      # ORAC Config
      return UKIRT::Sequence::Config::ORAC->new( File => $args{File} );
    } elsif ( $args{File} =~ /\.aim$/i) {
      # AIM config
      return UKIRT::Sequence::Config::AIM->new( File => $args{File} );
    } else {
      throw UKIRT::SequenceError::UnrecognizedConfig( "Unable to determine config type from suffix: '$args{File}'");
    }

  } else {
     # subclass constructor

    # create empty object
    my $cfg = bless {
		     LINES => [],
		     FILENAME => undef,
		     LUT => {},
		    }, $class;

    if ( exists $args{File} ) {
      $cfg->_parse_from_file( $args{File} );

    } elsif ( exists $args{Lines} ) {
      $cfg->_parse_lines( $args{Lines} );
    } else {
      throw UKIRT::SequenceError::BadArgs( "Must supply either ref to Lines array or a File name");
    }

    return $cfg;
  }

}

=back

=head2 Accessor Methods

=over 4

=item B<filename>

Name of the file used to create this object (if supplied).

  $f = $cfg->filename;
  $cfg->filename( $f );

=cut

sub filename {
  my $self = shift;
  if ( @_ ) {
    $self->{FILENAME} = shift;
  }
  return $self->{FILENAME};
}

=item B<contents>

The (unparsed) contents of the config. Represented by a reference to
an array of lines.

  $cfg->contents( \@lines );
  @lines = $cfg->contents;

=cut

sub contents {
  my $self = shift;
  if (@_) {
    @{ $self->{LINES} } = @{ shift(@_) };
  }
  return @{ $self->{LINES} };
}

=item B<items>

The extracted configuration information. Available as a hash indexed
by config item name.

 $cfg->items( \%items );
 %items = $cfg->items();

=cut

# Note that the set/getItem method access the hash ref directly.

sub items {
  my $self = shift;
  if ( @_ ) {
    %{ $self->{ITEMS} } = %{ shift(@_) };
  }
  return %{ $self->{ITEMS} };
}

=item B<getItem>

Retrieve the configuration value for the supplied option.

  $value = $cfg->getItem( "filter" );

=cut

sub getItem {
  my $self = shift;
  my $item = shift;
  if ( exists $self->{ITEMS}->{$item}) {
    return $self->{ITEMS}->{$item};
  }
  return undef;
}

=item B<setItem>

Set a configuration option by name.

 $cfg->setItem( $key, $value );

Also modifies the configuration item in the original contents.

=cut

sub setItem {
  my $self = shift;
  my $item = shift;
  my $value = shift;
  $self->{ITEMS}->{$item} = $value;

  # Now edit the line in the config itself
  $self->_modify_keyval_line( $item, $value );

}


=back

=begin __PRIVATE_METHODS__

=head1 PRIVATE METHODS

=over 4

=item B<_parse_from_file>

Parse the config, given the file name. Calls C<_parse_lines> method
to configure the object.

  $cfg->_parse_from_file( $file );

Expected to be called from a subclass.

=cut

sub _parse_from_file {
  my $self = shift;
  my $file = shift;

  # open the file
  open my $fh, "< $file"
    or throw UKIRT::SequenceError::FileError( "Unable to open file '$file'");
  my @lines = <$fh>;
  close($fh)
    or throw UKIRT::SequenceError::FileError("Error closing config $file: $!");

  # now call format specific parser
  $self->_parse_lines( \@lines );

  # Set the filename 
  $self->filename( $file );

}

=item B<_parse_lines>

Parse the array of lines and extract configuration information.

  $cfg->_parse_lines( \@lines );

The lines and config information are stored in the object.

=cut

sub _parse_lines {
  my $self = shift;
  my $lines = shift;

  my %conf;

  # parse
  for my $line (@$lines) {
    # split into 2 parts / dropping the =
    chomp $line;
    my ($key, $value) = $self->_parse_config_line( $line );
    next unless defined $key;

    $conf{$key} = $value;
  }

  # store the lookup table
  $self->items( \%conf );

  # store the original lines
  $self->contents( $lines );

}

=item B<_parse_config_line>

Low level line parser. Given each line in turn and returns a key 
and a value or an empty list.

  ($key, $value) = $cfg->_parse_config_line( $line );

=cut

sub _parse_lines_low_level {
  croak "Method _parse_lines must be sub-classed";
}

=item B<_modify_keyval_line>

Modify a keyword=value line in the original format.

  $cfg->_modify_keyval_line( $key , $value );

=cut

sub _modify_keval_line {
  croak "Method _modify_keyval_line must be sub-classed";
}

=back

=end __PRIVATE_METHODS__

=head1 SEE ALSO

L<UKIRT::Sequence>, L<UKIRT::Sequence::Config::AIM>,
L<UKIRT::Sequence::Config::ORAC>

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
