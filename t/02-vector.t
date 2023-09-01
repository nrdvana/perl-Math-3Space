#! /usr/bin/env perl
use Test2::V0;
use Math::3Space::Vector;

*vec3= *Math::3Space::Vector::vec3;

sub vec_check {
	my ($x, $y, $z)= @_;
	return object { call sub { [shift->xyz] }, [ float($x), float($y), float($z) ]; }
}

is( vec3(1,2,3),                       vec_check(1,2,3), 'basic ctor' );
is( vec3(vec3(4,3,2)),                 vec_check(4,3,2), 'clone ctor' );

is( vec3(5,5,5)->x(1)->y(4),           vec_check(1,4,5), 'x y z accessors' );
is( [ vec3(5,5,5)->xyz ],              [5, 5, 5],        'read xyz accessor' );

is( vec3(5,5,5)->set(1,2,3),           vec_check(1,2,3), 'set($x,$y,$z)' );
is( vec3(1,0,0)->add(0,1,1),           vec_check(1,1,1), 'add(x,y,z)' );
is( vec3(1,0,0)->add(1,1),             vec_check(2,1,0), 'add(x,y)' );
is( vec3(1,0,0)->add([1,1,1]),         vec_check(2,1,1), 'add([x,y,z])' );
is( vec3(1,0,0)->add(vec3(-1,-1,2)),   vec_check(0,-1,2),'add(vec)' );
is( vec3(1,0,0)->sub(-1,0,-5),         vec_check(2,0,5), 'sub(x,y,z)' );
is( vec3(1,1,1)->scale(2),             vec_check(2,2,2), 'scale(uniform)' );
is( vec3(1,1,1)->scale(2,2),           vec_check(2,2,1), 'scale(x,y)' );
is( vec3(1,1,1)->scale(2,2,2),         vec_check(2,2,2), 'scale(x,y,z)' );
is( vec3(1,1,1)->scale(vec3(0,0,0)),   vec_check(0,0,0), 'scale(vec)' );

is( vec3(5,0,0)->magnitude,            float(5),         'magnitude' );
is( vec3(5,0,0)->magnitude(2),         vec_check(2,0,0), 'set magnitude' );

is( vec3(1,0,0)->dot(0,1,0),           float(0),         'dot orthagonal' );
is( vec3(1,1,1)->dot(1,1,1),           float(1),         'dot colinear' );
is( vec3(1,1,0)->dot(-1,-1,0),         float(-1),        'dot opposite' );

is( vec3(1,0,0)->cross([ 0,1,0 ]),        vec_check(0,0,1),  'X->cross(Y) = Z' );
is( vec3(0,0,0)->cross([0,1,0], [0,0,1]), vec_check(1,0,0),  'Self= X cross Y' );

done_testing;
