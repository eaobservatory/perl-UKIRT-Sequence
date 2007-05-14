use strict;
use ExtUtils::MakeMaker;
use File::Spec;

my $verfile = File::Spec->catfile("lib","UKIRT","Sequence.pm");


WriteMakefile(
	      'NAME'      => 'UKIRT::Sequence',
	      'VERSION'   => '0.80',
	      'dist'      => { COMPRESS => "gzip -9f"},
	      'PREREQ_PM' => {
			      'Astro::Coords' => 0.05,
			      'Astro::WaveBand' => 0,
		              'JAC::OCS::Config' => 0,
			     },
	      ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
	       (ABSTRACT => 'UKIRT Sequence/Config parsing',
		AUTHOR     => 'Tim Jenness <t.jenness@jach.hawaii.edu>') : ()),
	     );

