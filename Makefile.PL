use ExtUtils::MakeMaker;

WriteMakefile(
	      'NAME'      => 'UKIRT::Sequence',
	      'VERSION_FROM'   => 'Sequence.pm',
	      'dist'      => { COMPRESS => "gzip -9f"},
	      'PREREQ_PM' => {
			      'Astro::Coords' => 0.05,
			      'Astro::WaveBand' => 0,
		              'JAC::OCS::Config' => 0,
			     },
	      ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
	       (ABSTRACT_FROM => 'Sequence.pm',
		AUTHOR     => 'Tim Jenness <t.jenness@jach.hawaii.edu>') : ()),
	     );

