#! /usr/bin/env perl
use Test2::V0;
use Math::3Space 'space';

sub is_vec {
	my ($x, $y, $z)= @_;
	return object { call sub { [shift->xyz] }, [ $x, $y, $z ]; }
}

subtest move => sub {
	my $s1= space();
	$s1->xv([2,0,0]); # just so move_rel is different from move
	is( $s1->move( 3,3,3), object { call origin => is_vec(3,3,3); }, 'move(3,3,3)' );
	is( $s1->move(-1,0,1), object { call origin => is_vec(2,3,4); }, 'move(-1,0,1)' );
};

subtest move_rel => sub {
	my $s1= space();
	$s1->xv([2,0,0]);
	is( $s1->move_rel([1,1,1]), object { call origin => is_vec(2,1,1); }, 'move_rel(1,1,1)' );
};

subtest scale => sub {
	my $s1= space();
	is( $s1->scale(5), object {
		call xv => is_vec(5,0,0);
		call yv => is_vec(0,5,0);
		call zv => is_vec(0,0,5);
		call origin => is_vec(0,0,0);
	}, 'scale(5)' );
};

done_testing;
