#!perl

use Test::More tests => 9;

use_ok('UKIRT::Sequence');

my $seq = new UKIRT::Sequence(Lines => [
    'setHeader TEST1 FIRSTTEST',
    'setHeader TEST2 "SECOND TEST"',
]);

isa_ok($seq, 'UKIRT::Sequence');

is($seq->getHeaderItem('TEST1'), 'FIRSTTEST');
is($seq->getHeaderItem('TEST2'), 'SECOND TEST');

$seq->setHeaderItem('TEST2', 'SECOND TEST UPDATED');
$seq->setHeaderItem('TEST3', 'NEWTEST');
$seq->setHeaderItem('TEST4', 'ANOTHER "NEW" TEST');

is_deeply([$seq->exec()], [
    'setHeader TEST1 FIRSTTEST',
    'setHeader TEST4 "ANOTHER ?NEW? TEST"',
    'setHeader TEST3 NEWTEST',
    'setHeader TEST2 "SECOND TEST UPDATED"',
]);

is($seq->getHeaderItem('TEST1'), 'FIRSTTEST');
is($seq->getHeaderItem('TEST2'), 'SECOND TEST UPDATED');
is($seq->getHeaderItem('TEST3'), 'NEWTEST');
is($seq->getHeaderItem('TEST4'), 'ANOTHER ?NEW? TEST');
