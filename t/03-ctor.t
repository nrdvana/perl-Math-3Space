#! /usr/bin/env perl
use Test2::V0;
use Math::3Space 'space';

sub is_vec {
	my ($x, $y, $z)= @_;
	return object { call sub { [shift->xyz] }, [ $x, $y, $z ]; }
}

is( Math::3Space::space(), object {
	call xv     => object { call sub { [shift->xyz] } => [ 1, 0, 0 ]; };
	call yv     => object { call sub { [shift->xyz] } => [ 0, 1, 0 ]; };
	call zv     => object { call sub { [shift->xyz] } => [ 0, 0, 1 ]; };
	call origin => object { call sub { [shift->xyz] } => [ 0, 0, 0 ]; };
	call parent => undef;
}, 'global ctor' );

is( my $s1= space(), object {
	call xv     => object { call sub { [shift->xyz] } => [ 1, 0, 0 ]; };
	call yv     => object { call sub { [shift->xyz] } => [ 0, 1, 0 ]; };
	call zv     => object { call sub { [shift->xyz] } => [ 0, 0, 1 ]; };
	call origin => object { call sub { [shift->xyz] } => [ 0, 0, 0 ]; };
	call parent => undef;
}, 'imported ctor' );

is( $s1->space, object {
	call xv     => object { call sub { [shift->xyz] } => [ 1, 0, 0 ]; };
	call yv     => object { call sub { [shift->xyz] } => [ 0, 1, 0 ]; };
	call zv     => object { call sub { [shift->xyz] } => [ 0, 0, 1 ]; };
	call origin => object { call sub { [shift->xyz] } => [ 0, 0, 0 ]; };
	call parent => $s1;
}, 'derived space' );	

# Test accessors
for my $name (qw( origin xv yv zv )) {
	my $m= $s1->can($name);
	is( $s1->$m(1,2,3)->$m,   is_vec(1,2,3), "write $name (,,)" );
	my $vec= $s1->$m;
	is( $s1->$m([2,3,4])->$m, is_vec(2,3,4), "write $name [,,]" );
	is( $s1->$m( $vec )->$m,  is_vec(1,2,3), "write $name vec()" );
}

done_testing;
