package UKIRT::Sequence;

=head1 NAME

UKIRT::Sequence - Parse and manipulate a UKIRT sequence

=head1 SYNOPSIS

  use UKIRT::Sequence;

  my $seq = new UKIRT::Sequence;
  $seq->readseq( $file );
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
use TOML::TCS;
use File::Spec;

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
		   ConfigNames => [],
		   InputDir => File::Spec->curdir,
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
is known). Directory path is not included (see C<inputdir> method).

Automatically populated when an exec is read. If called with a
file that includes a directory path, the directory is stripped and
stored in the C<inputdir> attribute. Directory path is not modified
if none is supplied.

=cut

sub inputfile {
  my $self = shift;
  if (@_) {
    my $path = shift;
    my ($vol,$dir, $file) = File::Spec->splitpath($path);
    croak "Volume is defined [$vol] but this module does not know what to do with it!"
      if $vol;
    $self->{InputFile} = $file;

    # Do nothing if no directory specified (will refer to cwd) by default
    $self->inputdir( $dir ) if $dir;
  }
  return $self->{InputFile};
}

=item B<inputdir>

The name of the directory containing the exec (and, by inference)
the associated config files.

Automatically populated when a file is stored in C<inputfile>
attribute (by stripping the path). Defaults to current directory.

=cut

sub inputdir {
  my $self = shift;
  if (@_) {
    $self->{InputDir} = shift;
  }
  return $self->{InputDir};
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

=item B<config_names>

Order of the configs in the exec. Returns keys suitable for use
with the hash returned by the C<configs> method.

  @names = $seq->config_names();

=cut

sub config_names {
  my $self = shift;
  if (@_) {
    croak "Can not modify order after object is created"
      if @{$self->{ConfigNames}};
    @{$self->{ConfigNames}} = @_;
  }
  return @{$self->{ConfigNames}};
}

=back

=head2 Load methods

=over 4

=item B<readseq>

Read a sequence into the object given a file name pointing to the
exec.

  $seq->readseq( $exec );

Assumes that either the full path is specified in the file name
or the file is available in the current directory or that the
C<inputdir> has been configured prior to calling this method.

=cut

sub readseq {
  my $self = shift;

  my $exec = shift;

  # if we store this in the inputfile() method then the input directory
  # will be set correctly.
  $self->inputfile( $exec );

  # Now get path to exec
  my $path = File::Spec->catfile( $self->inputdir, $self->inputfile);
  print "Path is $path\n";

  open my $fh, "< $path" or croak "Unable to read sequence $path: $!";
  my @lines = <$fh>;
  close($fh) or croak "Error closing sequence $exec: $!";

  # Now pass this to the line parser
  $self->_parse_lines( \@lines );

  return;
}

=item B<readconfig>

Given a config name, read it in and convert it to a hash.

  %config = $seq->readconfig( $configfile );

The config file can be called without a suffix; with .conf or
.aim added automatically. Additionally, if the file can not be
found, a check is made for a lower case version of the file (with
all suffix combinations). An exception is thrown if no file can be
found.

Note that this routine does not attempt to determine the suffix
and case-sensitvity from the instrument name since it is possible
that the config is being read without knowing the instrument.

The assumption is that, if no path is specfied for the config file,
that the config files are in the same directory as the exec. The
directory is obtained via the C<inputfile> method (and automatically
set when the exec is read).

=cut

sub readconfig {
  my $self = shift;
  my $file = shift;

  # need to find out whether the file includes a directory
  $file = $self->_prepend_dir( $file );

  # CGS4 configs have .aim suffix whereas other UKIRT sequences
  # have a .conf suffix. We therefore have to try both combinations
  # plus the variation where the file is fully specified.
  # Since CGS4 uses lower case for its .aim files (since they must
  # be visible on a vax) we also try doing a lc() as last resort.
  # Use -e rather than open() to test existence since it is not likely
  # that we will encounter a race condition
  # All three suffices
  my $found;
  for my $suffix ('','.conf','.aim') {
    my $f = $file . $suffix;

    if (-e $f) {
      $found = $f;
      last;
    }
    # lower case
    if (-e lc($f)) {
      $found = lc($f);
      last;
    }
  }

  croak "Unable to locate config file with root name $file"
    unless defined $found;

  open my $fh, "< $found" or croak "Error reading config $found: $!";
  my @lines = <$fh>;
  close($fh) or croak "Error closing config $file: $!";

  # We need to be able to extract information from both a ORAC .conf
  # file and an AIM .aim file (e.g. for CGS4) Note that the AIM format
  # can not be written out since the object representation of using a
  # hash is not sufficient (and if we want to write we should be using
  # a UKIRT::Sequence::Config::AIM and UKIRT::Sequence::Config::ORAC
  # subclasses)
  my %conf;
  if ($found =~ /\.conf$/) {
    for my $line (@lines) {
      # split into 2 parts / dropping the =
      chomp $line;
      my ($key, undef, $value) = split /\s+/,$line, 3;

      $conf{$key} = $value;
    }
  } elsif ($found =~ /\.aim$/) {
    # simple parser
    for my $line (@lines) {
      # skip anything that has a colon in it
      next if $line =~ /:/;
      # remove leading and trailing space
      $line =~ s/^\s+//;
      $line =~ s/\s+$//;
      next unless length($line);
      # split into two chunks (keys will include spaces)
      my ($value, $key) = split /\s+/,$line, 2;
      $conf{$key} = $value;
    }
  } else {
    croak "Unrecognized file suffix. Neither .aim nor .conf in '$found'";
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
  # both by name and by position in the file
  my %configs;
  my @confs;

  # Remove any leftover newlines
  chomp(@$lines);

  # go through the exec
  # Do we populate target and instrument information now?
  for my $line (@$lines) {
    # We do need to read config files
    if ($line =~ /^loadConfig\s+(.*)/) {
      my %c = $self->readconfig( $1 );
      $configs{$1} = \%c;
      push(@confs, $1);
    }
  }

  # Store it
  $self->exec( $lines );
  $self->configs( %configs );
  $self->config_names( @confs );
  return;
}

=back

=head2 Content extraction

=over 4

=item B<getTarget>

Go through the exec and retrieve the target information for the base position.
Returned as an C<Astro::Coords> object.

  $c = $seq->getTarget();

Returns C<undef> if no target can be found.

=cut

sub getTarget {
  my $self = shift;
  return $self->getCoords( 'BASE' );
}

=item B<setTarget>

Store new target information.

=cut

sub setTarget {
  croak "setTarget not yet implemented.";
}

=item B<clearTarget>

Clear target information associated with this sequence.

=cut

sub clearTarget {
  croak "clearTarget not yet implemented.";
}

=item B<fixup>

Fix up any just-in-time sections of the sequence.
Currently is a no-op provided for compatibility with the queue
system.

=cut

sub fixup {
  return;
}

=item B<verify>

Verify that the sequence is observable.

Currently is a no-op provided for compatibility with the queue
system.

=cut

sub verify {
  return;
}

=item B<getGuide>

Go through the exec and retrieve the guide star information.
Returned as an C<Astro::Coords> object.

  $c = $seq->getGuide();

Returns C<undef> if no guide star can be found.

=cut

sub getGuide {
  my $self = shift;
  return $self->getCoords( 'GUIDE' );
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

Returns "NONE" if no target is specified.

=cut

sub getTargetName {
  my $self = shift;
  my $c = $self->getTarget;
  return ( defined $c ? $c->name : "NONE");
}

=item B<getGuideName>

Return the name of the guide star.

  $target = $seq->getGuideName;

Returns C<undef> if no guide star is specified.

=cut

sub getGuideName {
  my $self = shift;
  my $c = $self->getGuide;
  return (defined $c ? $c->name : undef);
}

=item B<getWaveBand>

Return a list of C<Astro::WaveBand> objects associated with the sequence.
Consecutive duplicates are ignored, but order is retained.

 @wb = $seq->getWaveband;

In scalar context, the waveband objects are stringified and joined with a 
"/" delimiter.

=cut

sub getWaveBand {
  my $self = shift;

  # For UFTI we need a filter
  my $inst = $self->getInstrument;

  # If we can change camera mode via the config then we clearly
  # need to put this if statement inside a loop and not use the
  # getConfigItem method to obtain the values.

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
    $key = 'wavelength';
  } else {
    croak "Unknown instrument '$inst'";
  }

  # Now read the config
  my @vals = $self->getConfigItem( $key );

  # Remove consecutive entries that are duplicates but not
  # entries that change and then revert
  my $current = '';
  my @uniq;
  for my $w (@vals) {
    next unless defined $w;
    next if $current eq $w;
    push(@uniq, $w);
    $current = $w;
  }

  # Now create the objects
  my @wb = map { new Astro::WaveBand( Instrument => $inst,
				      $type => $_
				    ) } @uniq;

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

The order of the entries in the array will match the order of the configs
in the exec

  @values = $seq->getConfigItem( $key );

=cut

sub getConfigItem {
  my $self = shift;
  my $key = shift;
  my %configs = $self->configs;

  my @v = map { $configs{$_}->{$key} } $self->config_names;
  return @v;
}

=item B<getCoords>

Retrieve the coordinate associated with the specified tag
name (BASE, GUIDE or SKY).

Assumes that the tag is specified in the TCS XML or, if a C<telConfig>
instruction is not present, looks for a line of the form C<SET_$TAG>
(although BASE maps to SET_TARGET not SET_BASE).

  $coords = $seq->getCoords( 'SKY' );
  $coords = $seq->getCoords( 'BASE' );
  $coords = $seq->getCoords( 'GUIDE' );

The C<getTarget> and C<getGuide> methods are simple wrappers about this
routine.

=cut

sub getCoords {
  my $self = shift;
  my $tag = shift;
  $tag = uc($tag);

  # retrieve the exec
  my @exec = $self->exec;

  # Probably should cache this somewhere since it is not going to change
  my $target;

  # Go through the exec looking for a telConfig
  # This should generate a hit for all modern sequences
  my $foundConfig;
  for my $line (@exec) {
    if ($line =~ /telConfig/) {
      $foundConfig = 1;
      my @content = split /\s+/, $line;
      my $file = $content[1];

      $file = $self->_prepend_dir( $file );

      my $tcs = new TOML::TCS( File => $file );

      # Get the target information associated with this tag
      $target = $tcs->getCoords( $tag );

      # Abort from the search
      last;
    }
  }

  # If we did not find a tcsConfig, assume old format
  if (!$foundConfig) {
    # Name of the line in the exec is SET_TARGET for tag=BASE
    my $execline = ( $tag eq 'BASE' ? 'SET_TARGET' : 'SET_$tag' );
    for my $line (@exec) {
      if ($line =~ /^$execline/) {
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
  }

  return $target;
}

=item B<summary>

Return a one-line summary of the Sequence.

  $summary = $seq->summary;

Current format:

  TargetName Filters

=cut

sub summary {
  my $self = shift;

  # Guide information
  my $gname = $self->getGuideName;
  my $guide = (defined $gname ? "[Guide=$gname]" : "[No Guide]");

  # Get the content
  my $s = sprintf("%-12s %-12s %s %-12s", 
		  $self->getInstrument,
		  $self->getTargetName,
		  $guide,
		  scalar($self->getWaveBand));
  return $s;
}

=back

=begin __PRIVATE__METHODS__

=head2 Private Methods

=over 4

=item B<_prepend_dir>

If the supplied string does not include a directory specification,
prepend the directory stored in C<inputdir>. If it does contain a
directory, simply return it.

 $file = $seq->_prepend_dir( $file );

=cut

sub _prepend_dir {
  my $self = shift;
  my $file = shift;

  my ($vol, $dir, $base) = File::Spec->splitpath( $file );

  # no directory, add one
  if (!$dir && $base eq $file) {
    # Get the input directory and prepend it
    my $indir = $self->inputdir;
    $file = File::Spec->catfile( $indir, $file);
  }

  return $file;
}

=end __PRIVATE__METHODS__

=head1 BUGS

Note that this class can not write/edit execs/configs. This is partly
because oof a lack of time and because of the realisation that CGS4
aim files would require a non-standard implementation.

=head1 SEE ALSO

C<SCUBA::ODF> for reading and writing groups of SCUBA ODFs.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>.

Copyright (C) 2003-2004 Particle Physics and Astronomy Research Council.
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
