#!perl

use Test::More tests => 2;

require_ok( 'UKIRT::Sequence' );

chdir "execs";
my $exec = "UFTI_20031103_111731.exec";
my $seq = new UKIRT::Sequence( File => $exec );

isa_ok( $seq, "UKIRT::Sequence");

use Data::Dumper;
print Dumper($seq);

print Dumper($seq->getTarget);
print "Instrument: ".$seq->getInstrument."\n";
print "Filters: ". $seq->getWaveBand ."\n";
print "RMTAGENT : " . join("-",$seq->getHeaderItem("RMTAGENT")) ."\n";

print Dumper( $seq->getWaveBand);
