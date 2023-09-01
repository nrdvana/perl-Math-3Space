#! /usr/bin/env perl
use Test2::V0;
use Math::3Space 'space', 'vec3';

sub vec_check {
	my ($x, $y, $z)= @_;
	return object { call sub { [shift->xyz] }, [ float($x), float($y), float($z) ]; }
}

subtest move => sub {
	my $s1= space();
	$s1->xv([2,0,0]); # just so move_rel is different from move
	is( $s1->move( 3,3,3), object { call origin => vec_check(3,3,3); }, 'move(3,3,3)' );
	is( $s1->move(-1,0,1), object { call origin => vec_check(2,3,4); }, 'move(-1,0,1)' );
};

subtest move_rel => sub {
	my $s1= space();
	$s1->xv([2,0,0]);
	is( $s1->move_rel([1,1,1]), object { call origin => vec_check(2,1,1); }, 'move_rel(1,1,1)' );
};

subtest scale => sub {
	my $s1= space();
	is( $s1->scale(5), object {
		call xv => vec_check(5,0,0);
		call yv => vec_check(0,5,0);
		call zv => vec_check(0,0,5);
		call origin => vec_check(0,0,0);
	}, 'scale(5)' );
};

subtest rotate => sub {
	my $s1= space();
	# quarter rotation around Z axis should leave XV pointing at Y and YV pointing at -X
	is( $s1->rotate_z(.25), object {
		call xv => vec_check(0,1,0);
		call yv => vec_check(-1,0,0);
		call zv => vec_check(0,0,1);
	}, 'rotate around parent Z axis' );
	# 1/3 rotation around 1,1,1 should swap axes with eachother.
	$s1= space();
	is( $s1->rotate(1/3, [1,1,1]), object {
		call origin => vec_check(0,0,0);
		call xv => vec_check(0,1,0);
		call yv => vec_check(0,0,1);
		call zv => vec_check(1,0,0);
	}, 'rotate around (1,1,1)' );
};

done_testing;
