#! /usr/bin/env perl
use Test2::V0;
use Math::3Space 'space', 'vec3';

sub vec_check {
	my ($x, $y, $z)= @_;
	return object { call sub { [shift->xyz] }, [ float($x), float($y), float($z) ]; }
}

my $sp1= space->rotate_z(.125);
my $sp2= $sp1->space->rotate_z(.125);
my $sp3= $sp2->space->rotate_z(.125);
my $sp4= $sp3->space->rotate_z(.125);

# Space 4 should be a complete .5 rotation, with X and Y axes pointing opposite direction.
my $v= vec3(1,0,0);
$_->unproject_inplace($v) for $sp4, $sp3, $sp2, $sp1;
is( $v, vec_check(-1,0,0), 'unproject each makes .5 rotation' );

# Now reparent space 4 back out to global
$sp4->reparent(undef);
is( $sp4->parent_count, 0, 'sp4 has no parents' );
# Now unprojecting from sp4 alone should make a .5 rotation.
is( $sp4->unproject(vec3(1,0,0)), vec_check(-1,0,0), 'unproject sp4 makes .5 rotation' );
is( $sp4->project(vec3(1,0,0)), vec_check(-1,0,0), 'project sp4 also makes .5 rotation' );

# put it back
$sp4->reparent($sp3);
is( $sp4->parent_count, 3, 'sp4 back to 3 parents' );

# Create a new branch of the tree
my $sp2a= $sp1->space->rotate_z(-.125);
my $sp3a= $sp2a->space->rotate_z(-.125);
my $sp4a= $sp3a->space->rotate_z(-.125);

# Now, to project a point from sp4 to sp4a travels through six 1/8 rotations = 3/4
$v= vec3(5,5,5);
$_->unproject_inplace($v) for $sp4, $sp3, $sp2;
$_->project_inplace($v) for $sp2a, $sp3a, $sp4a;
is( $v, vec_check(5,-5,5), 'cross-project sp4 to sp4a makes .75 rotation' );

# Should get the same result by reparenting sp4a into sp4 and projecting
my $sp4b= $sp4a->clone->reparent($sp4);
is( $sp4b->parent_count, 4, 'sp4b parents = 4' );
is( $sp4b->project(vec3(5,5,5)), vec_check(5,-5,5), 'project sp4 => sp4b' );

# detect cycles
my @spaces= ($sp1);
push @spaces, $spaces[-1]->space for 1..100;
is( $spaces[-1]->parent_count, 100, 'tree is 100 deep' );
is( $spaces[$_]->parent_count, $_, "parent count of $_" )
	for 62..66; # cross threshold where it starts checking for cycles

is( eval { $spaces[-5]->reparent($spaces[-1]) }, undef, "can't reparent" );
like( $@, qr/cycle/i, 'error about cycles' );

is( eval { $spaces[0]->reparent($spaces[-5]) }, undef, "can't reparent" );
like( $@, qr/cycle/i, 'error about cycles' );

is( eval { $spaces[11]->reparent($spaces[0]) }, $spaces[11], "reparent 11 under 0" );
is( $spaces[11]->parent_count, 1, 'space 11 has one parent now' );
is( $spaces[-1]->parent_count, 90, 'space 100 has 90 parents now' );

done_testing;
