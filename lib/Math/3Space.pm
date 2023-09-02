package Math::3Space;

# VERSION
# ABSTRACT: 3D Coordinate Space math

use strict;
use warnings;
use Carp;

require XSLoader;
XSLoader::load('Math::3Space', $Math::3Space::VERSION);

=head1 SYNOPSIS

  use Math::3Space 'vec3', 'space';
  my $s1= space();
  my $s2= space($s1);
  my $s3= $s2->space->rotate_z(.25)->translate(2,2);
  
  # changes relative to parent space
  $s1->reset; # to identity
  $s1->translate(1,2,3);          # alias 'tr'
  $s1->rotate($angle, $vector);   # alias 'rot'
  $s1->orient($xv, $yv, $zv);
  
  # changes relative to itself
  $s1->scale($uniform_scale);
  $s1->scale($xs, $ys, $zs);
  $s1->set_scale(...);
  $s1->travel($x,$y,$z);          # alias 'go'
  $s1->rotate_xv($angle);
  $s1->rotate_yv($angle);
  $s1->rotate_zv($angle);
  
  # Transform coordinates between spaces
  $local_point= $s1->project($global_point);
  $global_point= $s1->unproject($local_point);
  $s1->project_inplace($point);
  $local_vector= $s1->project_vector($global_vector);
  $global_vector= $s1->unproject_vector($local_vector);
  
  # Create a custom space that condenses multiple space transformations
  $inner= space;
  $inner2= $inner->space;
  $inner3= $inner2->space;
  $combined= $inner3->clone->reparent($s1);
  # you can now directly project '$s1' points into '$combined'
  # and it is the same as a chain of unprojecting from $s1,
  # then projecting into $inner, $inner2, and $inner3,
  # but much faster.
  $combined->project_inplace($s1_pt);
  
  # Interoperate with OpenGL
  @float16= $s1->get_4x4_projection;
  @float16= $s1->get_4x4_unprojection;

=head1 DESCRIPTION

This module implements the sort of 3D coordinate space math that would typically be done using
4x4 matrices, but instead using a 3x4 matrix of 3 axis vectors (i.e. vectors that point along
the axes of the coordinate space) plus an origin point.  This results in significantly fewer
math operations needed to project points, and gives you a more useful mental model to work with,
like being able to see which direction the coordinate space is "facing", or which way is "up".

The coordinate spaces track their 'parent' coordinate space, so you can perform advanced
projections from a space inside a space out to a different space inside a space inside a space
without thinking about the details.

The coordiante spaces can be exported as 4x4 matrices for use with OpenGL or other common 3D
systems.

=cut

{ package Math::3Space::Exports;
	use Exporter::Extensible -exporter_setup => 1;
	*vec3= *Math::3Space::Vector::vec3;
	*space= *Math::3Space::space;
	export 'vec3', 'space';
}
sub import { shift; Math::3Space::Exports->import_into(scalar(caller), @_) }

sub parent { $_[0]{parent} }

require Math::3Space::Vector;
1;

__END__

=head1 CONSTRUCTOR

=head2 space

  $space= Math::3Space::space();
  $space= Math::3Space::space($parent);
  $space= $parent->space;

Construct a space (optionally within C<$parent>) initialized to an identity:

  origin => [0,0,0],
  xv     => [1,0,0],
  yv     => [0,1,0],
  zv     => [0,0,1],

=head2 new

  $space= Math::3Space->new(%attributes)

Initialize a space from raw attributes.

=head1 ATTRIBUTES

=head2 parent

Optional reference to parent coordinate space.  The origin and each of the axis vectors are
described in terms of the parent coordinate space.  A parent of C<undef> means the space is
described in terms of global absolute coordiantes.

=head2 parent_count

Number of parent coordinate spaces above this one, i.e. the "depth" of this node in the
hierarchy.

=head2 origin

The C<< [x,y,z] >> vector (point) of this space's origin in terms of the parent space.

=head2 xv

The C<< [x,y,z] >> vector of the X axis (often named "I" in math text)

=head2 yv

The C<< [x,y,z] >> vector of the Y axis (often named "J" in math text)

=head2 zv

The C<< [x,y,z] >> vector of the Z axis (often named "K" in math text)

=head2 is_normal

Returns true if all axis vectors are unit-length and orthagonal to eachother.

=head1 METHODS

=head2 clone

Return a new space with the same values, including same parent.

=head2 space

Return a new space describing an identity, with the current object as its parent.

=head2 reparent

Project this coordiante space into a different parent coordinate space.  After the projection,
this space still refers to the same global position and orientation as before, but it is just
described in terms of a different parent coordinate space.

For example, in a 3D game where a player is riding in a vehicle, the parent of the player's
3D space is the vehicle, and the parent space of the vehicle is the ground.
If the player jumps off the vehicle, you would call C<< $player->reparent($ground); >> to keep
the player at their current position, but begin describing them in terms of the ground.

A C<$parent> of C<undef> means "global coordinates".

=head2 project

  @local= $space->project( $vec1, $vec2, ... );
  @local= $space->project( [$x,$y,$z], [$x,$y,$z], ... );
  @parent= $space->unproject( $localpt, ... );
  $space->project_inplace( $pt1, $pt2, ... );
  $space->unproject_vector_inplace( $vec1, $vec2, ... );

Project one or more points into this coordinate space.  The points are assumed to be defined
in the parent 3Space (i.e. siblings to the origin of this 3Space)  This subtracts the origin
of this space from the point creating a vector, then projects the vector as per
L<project_vector>.  The returned list is the same length and format as the list passed to
this function, e.g. if you supply Vector objects you get back Vector objects, and likewise for
arrayrefs.

Unproject performs the opposite operation, taking a local point or vector and mapping out to
parent coordinates.

The C<_vector> variants do not add/subtract L</origin>, so vectors that were acting as
directional indicators will still be indicating that direction afterward regardless of this
space's C<origin>.

The C<_inplace> variants modify the points or vectors and return C<$self> for method chaining.

Variants:

=over

=item project

=item project_inplace

=item project_vector

=item project_vector_inplace

=item unproject

=item unproject_inplace

=item unproject_vector

=item unproject_vector_inplace

=back

=head2 normalize

Ensure that the eigenvectors are unit length and orthagonal to eachother.  The algorithm is:

  * make zv a unit vector
  * xv = yv cross zv, and make it a unit vector
  * yv = xv cross zv, and make it a unit vector

=head2 translate

  $space->translate($x, $y, $z);
  $space->translate([$x, $y, $z]);
  $space->translate($vec);
  # alias 'tr'
  $space->tr(...);

Translate the origin of the coordiante space, in terms of parent coordinates.

=for Pod::Coverage tr

=head2 travel

  $space->travel($x, $y, $z);
  $space->travel([$x, $y, $z]);
  $space->travel($vec);
  # alias 'go'
  $space->go(...);

Translate the origin of the coordiante space in terms of its own coordinates.
e.g. if your L</zv> vector is being used as "forward", you can make an object travel
forward with C<< $space->travel(0,0,1) >>.

=for Pod::Coverage go

=head2 set_scale

  $space->set_scale($uniform);
  $space->set_scale($x, $y, $z);
  $space->set_scale([$x, $y, $z]);
  $space->set_scale($vector);

Reset the scale of the axes of this space.  For instance, C<< ->set_scale(1) >> normalizes the
vectors so that the scale is identical to the parent coordinate space.

=head2 scale

  $space->scale($uniform);
  $space->scale($x, $y, $z);
  $space->scale([$x, $y, $z]);
  $space->scale($vector);

Scale the axes of this space by a multiplier to the existing scale.

=head2 rotate

  $space->rotate($revolutions, $x, $y, $z);
  $space->rotate($revolutions, [$x, $y, $z]);
  $space->rotate($revolutions, $vec);
  $space->rot(...); # shorthand
  $space->rot_x($revolutions);
  $space->rot_xv($revolutions);

This rotates the C<xv>, C<yv>, and C<zv> by an angle (measured in rotations rather than degrees
or radians, so .25 is a quarter rotation) relative to some other vector.

The vector is defined in terms of the parent coordinate space.  If you want to rotate around an
arbitrary vector defined in *local* coordinates, just unproject it out to the parent coordiante
space first.

The following (more efficient) variants are available for rotating about the parent's axes or
this space's own axes:

=for Pod::Coverage rot

=over

=item rot_x

=item rot_y

=item rot_z

=item rot_xv

=item rot_yv

=item rot_zv

=back

=cut

