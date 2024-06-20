#! /usr/bin/env perl
use Test2::V0;
use Math::3Space 'space', 'vec3';
BEGIN { eval {require PDL;1} or skip_all("No PDL") }
use PDL::Lite;

sub vec_check {
	my ($x, $y, $z)= @_;
	return object { call sub { [shift->xyz] }, [ float($x), float($y), float($z) ]; }
}
sub mat_check {
	return [ map float($_), @_ ];
}

subtest assign_from_pdl_vec => sub {
	my $s= space;
	$s->xv(pdl([1,0,1]));
	is( $s->xv, vec_check(1,0,1), 'assign xv from pdl' );
};


done_testing;
