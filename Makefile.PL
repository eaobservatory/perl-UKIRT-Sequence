use strict;
use ExtUtils::MakeMaker;
use File::Spec;

my $verfile = File::Spec->catfile("lib","UKIRT","Sequence.pm");


WriteMakefile(
	      'NAME'      => 'UKIRT::Sequence',
	      'VERSION_FROM'   =>  $verfile,
	      'dist'      => { COMPRESS => "gzip -9f"},
	      'PREREQ_PM' => {
			      'Astro::Coords' => 0.05,
			      'Astro::WaveBand' => 0,
		              'JAC::OCS::Config' => 0,
			     },
	      ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
	       (ABSTRACT_FROM => $verfile,
		AUTHOR     => 'Tim Jenness <t.jenness@jach.hawaii.edu>') : ()),
	     );

