#! /usr/bin/env perl
use Test2::V0;
use Math::3Space qw( vec3 space frustum_projection perspective_projection );

sub vec_check {
	my ($x, $y, $z)= @_;
	return object { call sub { [shift->xyz] }, [ float($x), float($y), float($z) ]; }
}

my $s= space;

# Tests created with
# perl -E 'use strict; use warnings;
#  use OpenGL::Sandbox qw/ -V1 make_context get_matrix glMatrixMode GL_PROJECTION glFrustum GL_PROJECTION_MATRIX /;
#  make_context; glMatrixMode(GL_PROJECTION); glFrustum(-1,1,-1,1,1,1000); say join ", ", get_matrix(GL_PROJECTION_MATRIX);'
# (and then truncating to 32-bit float precision because that's all OpenGL stores)

my $p= frustum_projection(-1,1,-1,1,1,1000);
is( [ $p->get_gl_matrix($s) ], [ map float($_, tolerance => 1e-6),
   # note - this is transposed because GL is column-major order,
   # but the goal is for the sequence of integers from get_gl_matrix
   # to match the sequence from glGetDouble, which this accurately tests.
   1, 0, 0, 0,
   0, 1, 0, 0,
   0, 0, -1.002002002, -1,
   0, 0, -2.002002002, 0
], 'simple 2x2x999 frustum' );

$p= perspective_projection(1/4, 1, 1, 1000);
is( [ $p->get_gl_matrix($s) ], [ map float($_, tolerance => 1e-6),
   1, 0, 0, 0,
   0, 1, 0, 0,
   0, 0, -1.002002002, -1,
   0, 0, -2.002002002, 0
], 'perspective 90deg 1:1 aspect 999 deep frustum' );

$p= perspective_projection(1/4, 4/3, .1, 1000);
is( [ $p->get_gl_matrix($s) ], [ map float($_, tolerance => 1e-6),
   0.74999999, 0, 0, 0,
   0, 1, 0, 0,
   0, 0, -1.00020002, -1,
   0, 0, -0.200020002, 0
], 'perspective 90deg 4:3 aspect 999.9 deep frustum' );

done_testing;
