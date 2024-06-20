#! /usr/bin/env perl
use Test2::V0;
use Math::3Space 'space', 'vec3';
BEGIN { eval {require PDL;1} or skip_all("No PDL") }
use PDL::Lite;
use Scalar::Util 'refaddr';

sub vec_check {
	my ($x, $y, $z)= @_;
	return object { call sub { [shift->xyz] }, [ float($x), float($y), float($z) ]; }
}
sub pdl_check {
	my (@list)= @_;
	return object { call sub { [shift->list] }, [ map float($_), @list ]; }
}
sub mat_check {
	return [ map float($_), @_ ];
}

subtest assign_from_pdl_vec => sub {
	my $s= space;
	$s->xv(pdl([1,0,1]));
	is( $s->xv, vec_check(1,0,1), 'assign xv from pdl' );
};

subtest project_pdl_vec => sub {
	my $s= space->translate(0,0,.5)->rot_z(.25);
	is( $s->project(pdl(1,0,0)),      pdl_check(0,-1,-.5), 'project' );
	is( $s->unproject(pdl(0,-1,-.5)), pdl_check(1,0,0),    'unproject' );
	is( $s->project_vector(pdl(1,0,0)),    pdl_check(0,-1,0), 'project_vector' );
	is( $s->unproject_vector(pdl(0,-1,0)), pdl_check(1,0,0),  'unproject_vector' );

	my $pdl= pdl(1,0,0);
	my $ret= $s->project_inplace($pdl);
	ok( refaddr($pdl) == refaddr($ret) );
	is( $pdl, pdl_check(0,-1,.5), 'project_inplace' );
	$ret= $s->unproject_inplace($pdl);
	is( $pdl, pdl_check(1,0,0), 'unproject_inplace' );
	$ret= $s->project_vector_inplace($pdl);
	is( $pdl, pdl_check(0,-1,0), 'project_vector_inplace' );
	$ret= $s->unproject_vector_inplace($pdl);
	is( $pdl, pdl_check(1,0,0), 'unproject_vector_inplace' );

	$pdl= pdl([1,0,0], [0,1,0], [0,0,1]);
	$ret= $s->project_inplace($pdl);
	is( $ret->slice(',0'), pdl_check(0,-1,0.5), 'project_inplace multi ,0' );
	is( $ret->slice(',1'), pdl_check(1,0,0.5),  'project_inplace multi ,1' );
	is( $ret->slice(',2'), pdl_check(0,0,1.5),  'project_inplace multi ,2' );
};

done_testing;
