package UKIRT::Sequence;

=head1 NAME

UKIRT::Sequence - Parse and manipulate a UKIRT sequence

=head1 SYNOPSIS

  use UKIRT::Sequence;

  my $seq = new UKIRT::Sequence;
  $target = $seq->getTarget;
  $seq->setTarget( $coords );
  $text = $seq->summary();

=head1 DESCRIPTION

Parse and manipulate a UKIRT sequence (consisting of a single
exec and multiple instrument configs).

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = '0.01';

use Astro::Coords;
use Astro::WaveBand;

# Overloading
#use overload '""' => "_stringify";

use vars qw/ $DEBUG /;
$DEBUG = 1;

=head1 METHODS

=head2 Constructor

=over 4

=item B<new>

Create a new Sequence object. Can be constructed from a filename
pointing to an exec or the contents of an exec.

  $seq = new UKIRT::Sequence( );
  $seq = new UKIRT::Sequence( File => 'xx.exec');
  $seq = new UKIRT::Sequence( Lines => $exec );

How do we include config information?

=cut

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # Read the arguments
  my %args = @_;

  # Create the object
  my $seq = bless {
		   Exec => [],
		   Configs => {},
		   InputFile => undef,
		  }, $class;

  # Read the hash arguments
  if (exists $args{Lines} && defined $args{Lines}) {
    $seq->_parse_lines( $args{Lines} );
  } elsif (exists $args{File} && defined $args{File}) {
    $seq->readseq( $args{File});
  }

  return $seq;
}

=back

=head2 Accessor Methods

=over 4

=item B<inputfile>

The name of the exec used to populate this object (if the name
is known).

=cut

sub inputfile {
  my $self = shift;
  if (@_) {
    $self->{InputFile} = shift;
  }
  return $self->{InputFile};
}

=item B<exec>

The exec. Represented by a reference to an array of lines.

  $seq->exec( \@lines );
  @lines = $seq->exec;

=cut

sub exec {
  my $self = shift;
  if (@_) {
    @{ $self->{Exec} } = @{ shift(@_) };
  }
  return @{ $self->{Exec} };
}

=item B<configs>

The instrument configurations used by the exec. Returned as a
hash where the keys correspond to the config name and
the values correspond to a reference to a hash representing the
specific instrument config.

  %configs = $seq->configs();

Returns the named config as a hash if a single argument is given:

  %config = $seq->configs( $config_name );

Configs can be stored (overwriting if necessary) by specifying 
config names and references to hashes:

  $seq->configs( $config1 => { }, $config2 => { } );

=cut

sub configs {
  my $self = shift;
  if (@_) {
    if (scalar(@_) == 1) {
      # We have a request for a config
      my $config = shift;
      if (exists $self->{Configs}->{$config}) {
	return %{ $self->{Configs}->{$config}};
      } else {
	return ();
      }
    } else {
      my %newconf = @_;
      for my $conf (keys %newconf) {
	$self->{Configs}->{$conf} = $newconf{$conf};
      }
    }
  } else {
    # No arguments
    return %{ $self->{Configs} };
  }
}


=back

=head2 Load methods

=over 4

=item B<readseq>

Read a sequence into the object given a file name pointing to the
exec.

  $seq->readseq( $exec );

=cut

sub readseq {
  my $self = shift;

  my $exec = shift;

  open my $fh, "< $exec" or croak "Unable to read sequence $exec: $!";
  my @lines = <$fh>;
  close($fh) or croak "Error closing sequence $exec: $!";

  # Now pass this to the line parser
  $self->_parse_lines( \@lines );

  # Store the filename for reference
  $self->inputfile( $exec );

  return;
}

=item B<readconfig>

Given a config name, read it in and convert it to a hash.

  %config = $seq->readconfig( $configfile );

=cut

sub readconfig {
  my $self = shift;
  my $file = shift;

  $file .= ".conf" unless $file =~ /\.conf$/;

  open my $fh, "< $file" or croak "Error reading config $file: $!";
  my @lines = <$fh>;
  close($fh) or croak "Error closing config $file: $!";

  my %conf;
  for my $line (@lines) {
    # split into 2 parts / dropping the =
    chomp $line;
    my ($key, undef, $value) = split /\s+/,$line, 3;

    $conf{$key} = $value;
  }

  return %conf;
}

=item B<_parse_lines>

Internal method to parse the exec (represented as an array of lines)
and populate the object.

  $seq->_parse_lines( \@lines );

Currently configs are discovered by reading the exec, rather than being
provided through the arguments to this method. The routine must therefore
assume that the directory containing the configs is the current working
directory...

=cut

sub _parse_lines {
  my $self = shift;
  my $lines = shift;

  # somewhere to store the config information
  my %configs;

  # Remove any leftover newlines
  chomp(@$lines);

  # go through the exec
  # Do we populate target and instrument information now?
  for my $line (@$lines) {
    # We do need to read config files
    if ($line =~ /^loadConfig\s+(.*)/) {
      $configs{$1} = { $self->readconfig( $1 ) };
    }
  }

  # Store it
  $self->exec( $lines );
  $self->configs( %configs );
  return;
}

=back

=head2 Content extraction

=over 4

=item B<getTarget>

Go through the exec and retrieve the target information.
Returned as an C<Astro::Coords> object.

  $c = $seq->getTarget();

Returns C<undef> if no target can be found.

=cut

sub getTarget {
  my $self = shift;
  my @exec = $self->exec;

  my $target;
  for my $line (@exec) {
    if ($line =~ /^SET_TARGET/) {
      my @content = split /\s+/, $line;
      $target = new Astro::Coords(
				  name => $content[1],
				  type => $content[2],
				  ra => $content[3],
				  dec => $content[4],
				  units => 's',
				 );
      last;
    }
  }

  return $target;
}

=item B<getProjectid>

Go through the exec and retrieve the project ID.

  $c = $seq->getProjectid();

Returns C<undef> if no project can be found.

=cut

sub getProjectid {
  my $self = shift;
  return $self->getHeaderItem( "PROJECT" );
}

=item B<getInstrument>

Retrieve the name of the instrument taking part in this sequence.
(there can be only one instrument per sequence).

  $inst = $seq->getInstrument();

=cut

sub getInstrument {
  my $self = shift;

  # Get the exec
  my @exec = $self->exec;

  my $inst;
  for my $line (@exec) {
    if ($line =~ /^[-]?set_inst\s+(.*)/i) {
      $inst = $1;
      last;
    }
  }
  return uc($inst);

}

=item B<getMSBID>

Retrieve the MSB ID associated with this exec. Returns C<undef> if
one can not be found.

  $msbid = $seq->getMSBID;

=cut

sub getMSBID {
  my $self = shift;
  return $self->getHeaderItem( 'MSBID' );
}

=item B<getObsLabel>

Return the observation label (useful for suspending an MSB).

[Not Yet Implemented]

=cut

sub getObsLabel {
  croak "getObsLabel: not yet!";
}

=item B<getTargetName>

Return the target name.

  $target = $seq->getTargetName;

=cut

sub getTargetName {
  my $self = shift;
  my $c = $self->getTarget;
  if (defined $c) {
    return $c->name;
  } else {
    return undef;
  }
}

=item B<getWaveBand>

Return a list of C<Astro::WaveBand> objects associated with the sequence.
Duplicates are ignored.

 @wb = $seq->getWaveband;

In scalar context, the waveband objects are stringified and joined with a 
"/" delimiter.

=cut

sub getWaveBand {
  my $self = shift;

  # For UFTI we need a filter
  my $inst = $self->getInstrument;

  my ($key, $type);
  if ($inst eq 'UFTI') {
    $key = 'filter';
    $type = 'Filter';
  } elsif ($inst eq 'UIST') {
    # depends on camera mode
    my @cam = $self->getConfigItem('camera');
    my $c;
    for (@cam) {
      $c = $_;
      last if defined $c;
    }
    croak "Unable to determine camera mode for UIST"
      unless defined $c;
    if ($c eq 'spectroscopy') {
      $key = 'centralWavelength';
      $type = 'Wavelength';
    } else {
      $key = 'filter';
      $type = 'Filter';
    }

  } elsif ($inst eq 'MICHELLE') {
    # depends on camera mode
    # depends on camera mode
    my @cam = $self->getConfigItem('camera');
    my $c;
    for (@cam) {
      $c = $_;
      last if defined $c;
    }
    croak "Unable to determine camera mode for Michelle"
      unless defined $c;
    if ($c eq 'spectroscopy') {
      $key = 'centralWavelength';
      $type = 'Wavelength';
    } else {
      $key = 'filter';
      $type = 'Filter';
    }

  } elsif ($inst eq 'CGS4') {
    $type = 'Wavelength';
    $key = 'centralWavelength';
  } else {
    croak "Unknown instrument '$inst'";
  }

  # Now read the config
  my @vals = $self->getConfigItem( $key );

  # remove duplicates regardless of order
  my %dup = map { (defined $_ ? ($_, '') : () ) } @vals;

  # Now create the objects
  my @wb = map { new Astro::WaveBand( Instrument => $inst,
				      $type => $_
				    ) } keys %dup;

  return (wantarray ? @wb : join("/",@wb));
}

=item B<getHeaderItem>

Retrieve a named header item from the exec. These are items that
have the form

  setHeader ITEM value

Returns C<undef> if the header is not present.

  @values = $seq->getHeaderItem( "MSBID" );

There can be multiple values in a single sequence.
In scalar context, the last entry is returned.
The name is case-insensitive.

=cut

sub getHeaderItem {
  my $self = shift;
  my $item = shift;
  return undef unless defined $item;

  # Get the exec
  my @exec = $self->exec;

  my @values;
  for my $line (@exec) {
    if ($line =~ /^[-]?setHeader\s+$item\s+(.*)/i) {
      push(@values, $1);
    }
  }
  return (wantarray ?  @values : $values[-1]);
}

=item B<getConfigItem>

For a specified configuration option, return the corresponding value
from each config. There will be as many return elements as there are
configs, even if the key does not exist in the configuration.

The order of the entries in the array will match the sorted order
of the config names (which will usually match the order they
will be executed. This may be a bug [and they should be forced to
match the execution order].

  @values = $seq->getConfigItem( $key );

=cut

sub getConfigItem {
  my $self = shift;
  my $key = shift;
  my %configs = $self->configs;

  my @v = map { $configs{$_}->{$key} } sort keys %configs;
  return @v;
}

=item B<summary>

Return a one-line summary of the Sequence.

  $summary = $seq->summary;

=cut

sub summary {
  my $self = shift;

  # Get the content
  

}


=back


=head1 SEE ALSO

C<SCUBA::ODF> for reading and writing groups of SCUBA ODFs.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>.

Copyright (C) 2003 Particle Physics and Astronomy Research Council.
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
