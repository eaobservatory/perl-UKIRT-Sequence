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
exec and multiple instrument configs and TCS XML).

=cut

use 5.006;
use strict;
use warnings;
use Carp;

our $VERSION = '0.02';

use Time::HiRes qw/ gettimeofday /;

use Astro::Coords;
use Astro::WaveBand;
use JAC::OCS::Config;
use File::Spec;
use UKIRT::Sequence::Config;

# Overloading
#use overload '""' => "_stringify";

use vars qw/ $DEBUG /;
$DEBUG = 0;

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
		   ExecModified => 0,
		   OCS_CONFIG => undef,
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

=item B<modified>

True if the exec has been modified since it was read. This can be used to decide
whether the file needs to be written out or whether the original version can be
used instead.

  $seq->modified( 1 );

=cut

sub modified {
  my $self = shift;
  if (@_) {
    my $val = shift;
    $self->{ExecModified} = ( $val ? 1 : 0 );
  }
  return $self->{ExecModified};
}

=item B<configs>

The instrument configurations used by the exec. Returned as a
hash where the keys correspond to the config name and
the values correspond to a C<UKIRT::Sequence::Config> object.

  %configs = $seq->configs();

Returns the named config as a C<UKIRT::Sequence::Config> object if a
single argument is given:

  $config = $seq->configs( $config_name );

Configs can be stored (overwriting if necessary) by specifying 
config names and corresponding objects:

  $seq->configs( $config1 => $cfg1, $config2 => $cfg2 );

=cut

sub configs {
  my $self = shift;
  if (@_) {
    if (scalar(@_) == 1) {
      # We have a request for a config
      my $config = shift;
      if (exists $self->{Configs}->{$config}) {
	return $self->{Configs}->{$config};
      } else {
	return;
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

=item B<coordinates>

A C<JAC::OCS::Config> object representing the coordinates of this
observation. See the C<getCoords> method for details on how to request
tagged coordinates directly.

  $ocs = $seq->coordinates();

=cut

sub coordinates {
  my $self = shift;
  if ( @_ ) {
    my $arg = shift;
    if ( UNIVERSAL::isa( $arg, "JAC::OCS::Config")) {
      $self->{OCS_CONFIG} = $arg;
    } else {
       croak "Argument to coordinates() must be an JAC::OCS::Config object.";
    }
  }
  return $self->{OCS_CONFIG};
}

=item B<old_coords>

The exec uses an old style coordinate specification.

=cut

sub old_coords {
  my $self = shift;
  if ( @_ ) {
    $self->{OLD_COORDS} = shift;
  }
  return $self->{OLD_COORDS};
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

The config file can be in three locations. If the full path is specified
to the config file, it is assumed that the file must be in that directory.
If no path is specified (just the filename) the method will look in
the same directory as the exec was located (this is what the observing
tool does when it exports a sequence) or in the sibling C<configs>
directory (this is what the translator does at the telescope).
The exec directory is obtained from the C<inputfile> method.

=cut

sub readconfig {
  my $self = shift;
  my $file = shift;

  # Config file is either in
  #  - the same directory as the exec
  #  - in the ../config directory relative to the location of the exec
  #  - in the directory specified as part of the full file name
  #    supplied to this method.

  # list of directories to try
  my @files;

  # First prepend the inputdir as the first search location
  # it will not be changed if it has a full directory path
  push(@files, $self->_prepend_dir( $file ));

  # If we have only been given a filename without path we need to try
  # different ideas (since the exec may not be giving us all the info we
  # need
  if ($files[0] ne $file) {
    # If the file did not include a directory, also try for a lower case
    # version of the file name. This is important for CGS4 which uses
    # lower case filenames
    push(@files, $self->_prepend_dir( lc($file) ));

    # and also look for the ../configs directory [in both standard case
    # and lower case variant]
    push(@files, $self->_prepend_dir( $file,
				     File::Spec->catdir( File::Spec->updir,
							 "configs")));

    push(@files, $self->_prepend_dir( lc($file),
				     File::Spec->catdir( File::Spec->updir,
							 "configs")));
  }

  # CGS4 configs have .aim suffix whereas other UKIRT sequences
  # have a .conf suffix. We therefore have to try both combinations
  # plus the variation where the file is fully specified.
  # Assume that the @files array includes both normal and lower case
  # variants since CGS4 must be lower case
  # Use -e rather than open() to test existence since it is not likely
  # that we will encounter a race condition
  # All three suffices
  my $found;
  PATHS: for my $path (@files) {
    for my $suffix ('','.conf','.aim') {
      print "CHECKING $path$suffix\n" if $DEBUG;
      if (-e $path.$suffix) {
	$found = $path . $suffix;
	last PATHS;
      }
    }
  }

  croak "Unable to locate config file with root name $file"
    unless defined $found;

  my $cfg = new UKIRT::Sequence::Config( File => $found);
  return $cfg;
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
  my $ocs;
  my %tags;

  # Remove any leftover newlines
  chomp(@$lines);

  # go through the exec
  # We populate target information now but defer instrument discovery
  for my $line (@$lines) {
    # We do need to read config files
    if ($line =~ /^loadConfig\s+(.*)/) {
      my $c = $self->readconfig( $1 );
      $configs{$1} = $c;
      push(@confs, $1);
    } elsif ( $line =~ /^telConfig/) {
      $ocs = $self->readtcsxml( $line );
      $self->old_coords( 0 );
    } elsif ( $line =~ /^SET_(\w+)/) {
      # Possibly a target specification
      my $b = $self->_parse_oldtcs( $line );
      $tags{$b->tag} = $b if defined $b;
    }
  }

  # did we get some old coordinates?
  if ( keys %tags  && !defined $ocs) {
    $self->old_coords( 1 );
    my $tcs = new JAC::OCS::Config::TCS;
    $tcs->telescope( "UKIRT" );
    $tcs->tags( %tags );
    $ocs = new JAC::OCS::Config;
    $ocs->tcs( $tcs );
  }

  # Store it
  $self->exec( $lines );
  $self->configs( %configs );
  $self->config_names( @confs );
  $self->coordinates( $ocs ) if defined $ocs;
  return;
}

=item B<readtcsxml>

Given a telConfig line, read the XML file and return it as a
C<JAC::OCS::Config> object.

  $ocs = $seq->readtcsxml( $line );

=cut

sub readtcsxml {
  my $self = shift;
  my $line = shift;
  return unless $line =~ /telConfig/;

  my @content = split /\s+/, $line;
  my $file = $content[1];

  # File will either be in the same directory as exec or in
  # ../configs directory
  my $xmlfile = $self->_prepend_dir( $file );

  # Hmm. If it does not exist, AND no path was supplied
  # with the filename, try looking in ../configs directory
  if (!-e $xmlfile && $xmlfile ne $file) {
    $xmlfile = $self->_prepend_dir( $file,
				    File::Spec->catdir( File::Spec->updir,
							"configs")
				  );
  }

  croak "Unable to locate TCS XML config file $file\n"
    unless -e $xmlfile;

  my $ocs = new JAC::OCS::Config( File => $xmlfile,
				  telescope => 'UKIRT',
				  validation => 0,
				);
  return $ocs;
}

=item B<_parse_oldtcs>

Parse the old-style coordinate specification. Returns a
C<JAC::OCS::Config::TCS::BASE> object, or an empty list if the line is
not parseable (possibly because not all SET_ lines refer to
coordinates.

 $base = $seq->_parse_oldtcs( $line );

=cut

sub _parse_oldtcs {
  my $self = shift;
  my $line = shift;

  return unless $line =~ /^SET_(\w+)/;

  # Work out the tag name
  my $tag = $1;
  $tag = "BASE" if $tag eq 'TARGET';

  # now parse the line
  my @content = split /\s+/, $line;
  return unless @content == 7;

  my $target = new Astro::Coords(
				 name => $content[1],
				 type => $content[2],
				 ra => $content[3],
				 dec => $content[4],
				 units => 's',
				);

  my $base = new JAC::OCS::Config::TCS::BASE;
  $base->tag( $tag );
  $base->coords( $target );

  return $base;
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

Set to "UNKNOWN" if an instrument can not be determined from the
exec or config.

B<Note:> the instrument name is returned in upper case.

=cut

sub getInstrument {
  my $self = shift;

  # Get the exec
  my @exec = $self->exec;

  # First scan through the exec looking for a set_instr line
  my $inst;
  for my $line (@exec) {
    if ($line =~ /^[-]?set_inst\s+(.*)/i) {
      $inst = $1;
      last;
    }
  }

  # If that did not work try looking in the config
  if (!defined $inst) {
    my @values = grep { defined $_ } $self->getConfigItem( "instrument" );
    $inst = $values[0];
  }


  # Finally, get the instrument from the filename
  if (!defined $inst) {
    my $file = $self->inputfile;
    # split into two parts
    ($inst, my $rest) = split(/_/,$file,2);
  }

  $inst = "UNKNOWN" if !defined $inst;

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

=item B<getMSBTID>

Retrieve the MSB transaction ID associated with this exec. Returns C<undef> if
one can not be found.

  $msbid = $seq->getMSBTID;

=cut

sub getMSBTID {
  my $self = shift;
  return $self->getHeaderItem( 'MSBTID' );
}

=item B<getMSBTitle>

Get the MSB title.  Returns C<undef> if not found.

  my $title = $seq->getMSBTitle();

=cut

sub getMSBTitle {
  my $self = shift;
  return $self->getHeaderItem('MSBTITLE');
}

=item B<getShiftType>

Get the shift type.

=cut

sub getShiftType {
  my $self = shift;
  return $self->getHeaderItem('OPER_SFT');
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

=item B<getCameraMode>

Retrieve operating mode of camera. Can be 'imaging', 'spectroscopy'
or 'ifu'. Consecutive duplicates are ignored but order is retained.

 @modes = $seq->getCameraMode.

In scalar context, the waveband objects are stringified and joined with a 
"/" delimiter.

=cut

sub getCameraMode {
  my $self = shift;

  # need to know the instrument
  my $inst = $self->getInstrument;

  my @cam;
  if ($inst eq 'UFTI' || $inst eq 'WFCAM') {
    push(@cam,'imaging');
  } elsif ($inst eq 'CGS4') {
    push(@cam,'spectroscopy');
  } elsif ($inst eq 'MICHELLE' || $inst eq 'UIST') {
    @cam = $self->_remove_dups( $self->getConfigItem('camera'));
  } else {
    croak "Unrecognized instrument: $inst\n";
  }
  return (wantarray ? @cam : join("/",@cam));
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
  if ($inst eq 'UFTI' || $inst eq 'WFCAM') {
    $key = 'filter';
    $type = 'Filter';
  } elsif ($inst eq 'UIST' || $inst eq 'MICHELLE') {
    # depends on camera mode
    my @cam = $self->getCameraMode;
    my $c = $cam[0];
    croak "Unable to determine camera mode for UIST"
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
  my @uniq = $self->_remove_dups( @vals );

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
      push(@values, _unquote_header($1));
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

  my @v = map { $configs{$_}->getItem($key) } $self->config_names;
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

  my $ocs = $self->coordinates;
  return unless defined $ocs;
  my $tcs = $ocs->tcs;

  return $tcs->getCoords( $tag );
}

=item B<summary>

Return a one-line summary of the Sequence.

  $summary = $seq->summary;

Current format:

  Instrument TargetName Filters Camera/Disperser

=cut

sub summary {
  my $self = shift;

  # Guide information
  my $gname = $self->getGuideName;
  my $guide = (defined $gname ? "[Guide=$gname]" : "[No Guide]");

  my $inst = $self->getInstrument;
  my $mode = '';
  if ($inst eq 'CGS4') {
    # For CGS4 we need the grating
    $mode = join("/",$self->_remove_dups( $self->getConfigItem( 'grating' )));
  } elsif ($inst eq 'UFTI' || $inst eq 'WFCAM') {
    $mode = 'imaging';
  } elsif ($inst eq 'UIST' || $inst eq 'MICHELLE') {
    my @cam = $self->getCameraMode;
    if ($cam[0] eq 'imaging') {
      $mode = 'imaging';
    } else {
      $mode = join("/",$self->_remove_dups($self->getConfigItem('disperser')));
    }
  }


  # For UFTI we should say simply 'imaging'
  # For UIST we should say 'imaging' or

  # Get the content
  my $s = sprintf("%-10s %-15s %-12s %-15s", 
		  $self->getInstrument,
		  substr($self->getTargetName,0,15),
		  scalar($self->getWaveBand),
		  substr($mode,0,15)
		 );
  return $s;
}

=back

=head2 Content modification

=over 4

=item B<setHeaderItem>

Modifies the sequence to include either a new setHeader directive
or change the all occurences of that header if it pre-exists.

  $seq->setHeaderItem( $header, $value );

The header will be inserted after the first setHeader directive
if the header does not exist.

The optional third argument controls where in the header it goes.
It is only accessed for a new header, not when modifying an existing header.

  $seq->setHeaderItem( $header, $value, qr/MSBID/ );

The header will be inserted after the first line in the exec that matches
the supplied regular expression.

If nowhere can be found to place the setHeader command it is inserted at the front.

=cut

sub setHeaderItem {
  my $self = shift;
  my $header = uc(shift);
  my $newval = shift;
  my $posn = shift;

  # Get the exec contents
  my @exec = $self->exec;

  # Quote the new value in preparation for inserting it.
  $newval = _quote_header($newval);

  # form a regex that will allow us to know that we are changing
  # an existing header
  my $existing = qr/^([-]?setHeader\s+$header)\s+/;

  # We now need to look for the header
  my $replaced;
  for my $line (@exec) {
    if ($line =~ $existing) {
      $line = $1 . " $newval";
      $replaced = 1;
    }
  }

  # if we did not find a header to replace we have to insert one
  if (!$replaced) {

    # Default position will be after first setHeader or startGroup
    if (!defined $posn) {
      $posn = qr/(setHeader|startGroup)/;
    } elsif (not ref $posn) {
      $posn = qr/$posn/;
    } elsif (ref($posn) eq 'Regexp') {
      # this is okay. carry on.
    } else {
      croak "3rd Argument to setHeaderItem must be Regexp object or string";
    }

    # find the location to splice
    # default if we find no match will be to insert it in the first line ($index+1)
    my $index = -1;
    for my $i (0..$#exec) {
      if ($exec[$i] =~ $posn) {
	$index = $i;
	last;
      }
    }

    # put this new line one after the location we found
    splice(@exec, $index+1, 0, "setHeader $header $newval");

  }

  # update the object
  $self->exec( \@exec );
  $self->modified( 1 );
  return;
}

=item B<setMSBTID>

Set the MSB transaction ID.

 $seq->setMSBTID( $tid );

=cut

sub setMSBTID {
  my $self = shift;
  my $tid = shift;
  croak "MSB transaction ID is not defined"
    unless defined $tid;
  $self->setHeaderItem( "MSBTID", $tid, qr/MSBID/);
}

=item B<setShiftType>

Set the shift type.

=cut

sub setShiftType {
  my $self = shift;
  my $type = shift;
  croak "Shift type is not defined"
    unless defined $type;
  $self->setHeaderItem('OPER_SFT', $type);
}

=back

=head2 Queue compatibility methods

The queue requires some standard methods to simplify operation.

=over 4

=item B<msbtid>

Return or set the MSB transaction ID.

  $seq->msbtid( $tid );
  $tid = $seq->msbtid;

Wrapper around the getMSBTID

=cut

sub msbtid {
  my $self = shift;
  if (@_) {
    $self->setMSBTID( @_ );
  }
  return $self->getMSBTID;
}

=item B<shift_type>

Return or set the shift type.

  $seq->shift_type('NIGHT');

=cut

sub shift_type {
  my $self = shift;
  if (@_) {
    $self->setShiftType(@_);
  }
  return $self->getShiftType();
}

=back

=head2 Output Methods

=over 4

=item B<writeseq>

Writes the sequence/exec to the specified output directory and returns the
name of the sequence/exec that was created.

 $file = $seq->writeseq( $outputdir );

Configs are not updated and will be referenced as they were originally named.

=cut

sub writeseq {
  my $self = shift;
  my $dir = shift;
  # In the future this may change to match JAC::OCS::Config
  # but for now the queue just requires a simple interface
  croak "Must supply an output directory name"
    unless defined $dir;

  # The filename is mandated to be made of the instrument name
  # and a timestamp
  my $inst = $self->getInstrument;

  # If the instrument is Michelle, the filename needs to start "Michelle"
  # rather than the upper case version returned by getInstrument.
  $inst = 'Michelle' if $inst eq 'MICHELLE';

  my ($sec, $mic_sec) = gettimeofday();
  my @ut = gmtime( $sec );

  my $fn_start = sprintf("%s_%04d%02d%02d_%02d%02d%02d",
		$inst, ($ut[5]+1900), ($ut[4]+1), $ut[3],
		$ut[2], $ut[1], $ut[0]);

  # The filenames become too long if milliseconds are included and the
  # instrument is Michelle.  Therefore only include milliseconds for
  # other instruments.
  $fn_start .= sprintf('%03d', int($mic_sec / 1000))
    unless $inst eq 'Michelle';

  my $fullname = _make_unique_filename($dir, $fn_start, '.exec');

  open (my $fh, "> $fullname") or
    croak "Unable to open output file $fullname: $!";

  my @exec = $self->exec;
  print $fh join("\n",@exec)."\n";
  close ($fh) or croak "Error closing exec file $fullname: $!";

  return $fullname;
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

An optional second argument can be supplied. This argument will
be a directory name supplied as a relative path that should be
appended to the global C<inputdir>

=cut

sub _prepend_dir {
  my $self = shift;
  my $file = shift;
  my $newpath = shift;

  my ($vol, $dir, $base) = File::Spec->splitpath( $file );

  # no directory, add one
  if (!$dir && $base eq $file) {
    # Get the input directory and prepend it
    my $indir = $self->inputdir;

    # Append the optional path adjustment
    if (defined $newpath) {
      $indir = File::Spec->catdir(File::Spec->splitdir($indir),
				  File::Spec->splitdir($newpath));
    }

    $file = File::Spec->catfile( $indir, $file);
  }

  return $file;
}

=item B<_remove_dups>

Remove consecutive entries that are duplicates but not
entries that change and then revert.

  @uniq = $self->_remove_dups( @entries );

For example,  A-A-B-C-C would become A-B-C.

Undefined entries are removed.

=cut

sub _remove_dups {
  my $self = shift;
  my @vals = @_;

  my $current = '';
  my @uniq;
  for my $w (@vals) {
    next unless defined $w;
    next if $current eq $w;
    push(@uniq, $w);
    $current = $w;
  }

  return @uniq;
}

=item B<_make_unique_filename($dir, $start, $end)>

Look for a 3-digit integer to add to a filename between the C<start>
and C<$end> parts such that it is unique in directory C<$dir>.

Returns the full pathname for the new file (the file is not created
by this subroutine).

=cut

sub _make_unique_filename {
  my ($dir, $start, $end) = @_;

  for (my $i = 0; $i < 1000; $i ++) {
    my $fullname = File::Spec->catdir($dir,
        sprintf('%s%03d%s', $start, $i, $end));

    return $fullname unless -e $fullname;
  }

  die 'Could not find unique filename "' . $start . 'NNN' . $end . '"';
}

=item B<_quote_header($value)>

Add quoting to a FITS header string.

=cut

sub _quote_header {
  my $value = shift;

  # It is unclear how to escape double quotes.  For now,
  # remove them.
  $value =~ s/"/?/g;

  # Apply quotes if needed.
  if ($value =~ / /) {
    $value = '"' . $value . '"';
  }

  return $value;
}

=item B<_unquote_header($value)>

Removing quoting from a FITS header string.

=cut

sub _unquote_header {
  my $value = shift;

  # If we have leading and trailing double quotes, remove them.
  if ($value =~ /^"(.*)"\s*$/) {
    $value = $1;

    # It is unclear whether there can be escaped double quotes
    # within the string.  For now, do nothing.
  }

  return $value;
}

=back

=end __PRIVATE__METHODS__

=head1 BUGS

Only headers can be modified by this class. Configs can not be changed.

=head1 SEE ALSO

C<SCUBA::ODF> for reading and writing groups of SCUBA ODFs.
C<JAC::OCS::Config> for reading and writing JCMT config files.

=head1 AUTHOR

Tim Jenness E<lt>t.jenness@jach.hawaii.eduE<gt>.

Copyright (C) 2007 Science and Technology Facilities Council.
Copyright (C) 2003-2005 Particle Physics and Astronomy Research Council.
All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful,but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place,Suite 330, Boston, MA  02111-1307, USA

=cut

1;
