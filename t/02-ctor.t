#! /usr/bin/env perl
use Test2::V0;
use Math::3Space;

is( Math::3Space::space(), object {
	call xv     => object { call sub { [shift->xyz] } => [ 1, 0, 0 ]; };
	call yv     => object { call sub { [shift->xyz] } => [ 0, 1, 0 ]; };
	call zv     => object { call sub { [shift->xyz] } => [ 0, 0, 1 ]; };
	call origin => object { call sub { [shift->xyz] } => [ 0, 0, 0 ]; };
});

done_testing;
