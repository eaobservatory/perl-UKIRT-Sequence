use ExtUtils::MakeMaker;

WriteMakefile(
	      'NAME'      => 'UKIRT::Sequence',
	      'VERSION_FROM'   => 'Sequence.pm',
	      'dist'      => { COMPRESS => "gzip -9f"},
	      ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
	       (ABSTRACT_FROM => 'Sequence.pm',
		AUTHOR     => 'Tim Jenness <t.jenness@jach.hawaii.edu>') : ()),
	     );

