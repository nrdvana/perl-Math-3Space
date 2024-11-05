use Test2::V0;
BEGIN {eval {require PDL;1} or skip_all("No PDL")}
use Math::3Space::PDL 'space', 'vec3';

sub vec_check {
	my ($x, $y, $z)= @_;
	return object { call sub { [shift->xyz] }, [ float($x), float($y), float($z) ]; }
}

subtest translate => sub {
	my $s1= space();
	$s1->xv([2,0,0]); # just so move_rel is different from move
	is( $s1->tr( 3,3,3), object { call origin => vec_check(3,3,3); }, 'translate(3,3,3)' );
	is( $s1->tr(-1,0,1), object { call origin => vec_check(2,3,4); }, 'translate(-1,0,1)' );
	
	$s1= space();
	$s1->xv([2,0,0]);
	is( $s1->travel([1,1,1]), object { call origin => vec_check(2,1,1); }, 'travel(1,1,1)' );
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
	# Basic quarter rotations around each axis
	# quarter rotation around X axis should leave y axis pointing at z
	is( space->rot_x(.25), object {
		call is_normal => T;
		call xv => vec_check(1,0,0);
		call yv => vec_check(0,0,1);
		call zv => vec_check(0,-1,0);
	}, 'rotate around parent X axis' );
	# quarter rotation around Y axis should move z to point at x
	is( space->rot_y(.25), object {
		call is_normal => T;
		call xv => vec_check(0,0,-1);
		call yv => vec_check(0,1,0);
		call zv => vec_check(1,0,0);
	}, 'rotate around parent Y axis' );
	# quarter rotation around Z axis should leave XV pointing at Y and YV pointing at -X
	is( space->rot_z(.25), object {
		call is_normal => T;
		call xv => vec_check(0,1,0);
		call yv => vec_check(-1,0,0);
		call zv => vec_check(0,0,1);
	}, 'rotate around parent Z axis' );
	is( space->rot_x(.1)->rot_y(.4), object {
		call is_normal => T;
		call xv => vec_check(-0.80901699,0,-0.58778525);
		call yv => vec_check(0.34549150,0.80901699,-0.47552825);
		call zv => vec_check(0.47552825,-0.58778525,-0.65450849);
	}, 'two non-right-angle rotations' );
	
	# Rotations of non-unit-length axis vectors:
	# Ensure that magnitude is preserved and that they remain orthogonal.
	my $s1= space->scale(2,3,4)->rot_x(.1)->rot_y(.4)->rot_z(.8);
	is( $s1, object {
		call is_normal => F;
		call xv => object {
		  call sub { shift->magnitude->sclr } => float(2);
		  call sub { shift->dot($s1->yv)->sclr } => float(0);
                };
		call yv => object {
		  call sub { shift->magnitude->sclr } => float(3);
		  call sub { shift->dot($s1->zv)->sclr } => float(0);
                };
		call zv => object {
		  call sub { shift->magnitude->sclr } => float(4);
		  call sub { shift->dot($s1->xv)->sclr } => float(0);
                };
	}, 'rotate_x/y/z on scaled axes' );
	
	# Starting from the Identity, the self-relative rotations will have the same effect as the
	# rotations around parent axes.
	# quarter rotation around X axis should leave y axis pointing at z
	is( space->rot_xv(.25), object {
		call is_normal => T;
		call xv => vec_check(1,0,0);
		call yv => vec_check(0,0,1);
		call zv => vec_check(0,-1,0);
	}, 'rotate around own X axis, optimized' );
	# quarter rotation around Y axis should move z to point at x
	is( space->rot_yv(.25), object {
		call is_normal => T;
		call xv => vec_check(0,0,-1);
		call yv => vec_check(0,1,0);
		call zv => vec_check(1,0,0);
	}, 'rotate around own Y axis, optimized' );
	# quarter rotation around Z axis should leave XV pointing at Y and YV pointing at -X
	is( space->rot_zv(.25), object {
		call is_normal => T;
		call xv => vec_check(0,1,0);
		call yv => vec_check(-1,0,0);
		call zv => vec_check(0,0,1);
	}, 'rotate around own Z axis, optimized' );
	# Now test the non-optimized code path when the axes are not normal eigenvectors.
	is( space->scale(5)->rot_xv(.25), object {
		call is_normal => F;
		call xv => vec_check(5,0,0);
		call yv => vec_check(0,0,5);
		call zv => vec_check(0,-5,0);
	}, 'rotate around own X axis' );
	# quarter rotation around Y axis should move z to point at x
	is( space->scale(5)->rot_yv(.25), object {
		call is_normal => F;
		call xv => vec_check(0,0,-5);
		call yv => vec_check(0,5,0);
		call zv => vec_check(5,0,0);
	}, 'rotate around own Y axis' );
	# quarter rotation around Z axis should leave XV pointing at Y and YV pointing at -X
	is( space->scale(5)->rot_zv(.25), object {
		call is_normal => F;
		call xv => vec_check(0,5,0);
		call yv => vec_check(-5,0,0);
		call zv => vec_check(0,0,5);
	}, 'rotate around own Z axis' );
	
	# Un-optimized rotations around an arbitrary axis
	# 1/3 rotation around 1,1,1 should swap axes with each other.
	is( space->rotate(1/3, [1,1,1]), object {
		call is_normal => T;
		call origin => vec_check(0,0,0);
		call xv => vec_check(0,1,0);
		call yv => vec_check(0,0,1);
		call zv => vec_check(1,0,0);
	}, 'rotate around (1,1,1)' );
};

subtest rotate_subspace => sub {
  my $sp1= space->rot_z(.125);
  my $sp2= $sp1->space->rot_z(.125);
  my $sp3= $sp2->space->rot_z(.125);
  my $sp4= $sp3->space->rot_z(.125);
  is( $sp4, object {
    call is_normal => T;
    call origin => vec_check(0,0,0);
    call xv => vec_check(0.70710678,0.70710678,0);
    call yv => vec_check(-0.70710678,0.70710678,0);
    call zv => vec_check(0,0,1);
  }, 'rotate 4 times, each subspaced' );
};

done_testing;
