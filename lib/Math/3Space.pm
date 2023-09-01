package Math::3Space;

# VERSION
# ABSTRACT: 3D Coordinate Space math

use strict;
use warnings;
use Carp;

require XSLoader;
XSLoader::load('Math::3Space', $Math::3Space::VERSION);

=head1 SYNOPSIS

  use Math::3Space 'vec', 'space';
  my $s1= space();
  my $s2= space($s1);
  
  # changes relative to parent space
  $s1->look_at([3,1,2]);
  $s1->move([1,2,3]);
  $s1->rotate($yaw, $pitch, $roll);
  $s1->scale($uniform_scale);
  $s1->scale($xs, $ys, $zs);
  
  # changes relative to itself
  $s1->move_rel([1,2,3]);  
  $s1->rotate_rel($yaw, $pitch, $roll);
  $s1->scale_rel($uniform_scale);
  
  # Translate coordiantes between spaces
  $s2_vec= $s2->project($s1_vec, $s1);
  $s2->reparent(undef); # no longer nested

=head1 DESCRIPTION

This module implements the sort of 3D coordinate space math that would normally be done using
4x4 matrices, but instead using 3 eigenvectors (i.e. unit vectors that point along the axes of
the coordinate space) plus an origin point.  This results in overall fewer math operations
needed to project points, and gives you a more useful mental model to work with, like being
able to see which direction the coordinate space is "facing", or which way is "up".

The coordiante spaces track their 'parent' coordinate space, so you can perform advanced
projections from a space in side a space out to a different space inside a space inside a space
without thinking about the details.

The coordiante spaces can be exported as 4x4 matrices for use with OpenGL or other common 3D
systems.

=cut

package Math::3Space::Exports {
	use Exporter::Extensible -exporter_setup => 1;
	sub vec :Export { Math::3Space::Vector->new(@_) }
	sub space :Export { Math::3Space::space(@_) }
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

=head2 new_from_matrix

  $space= Math::3Space->new_from_matrix(\@vals);

Takes a 4x4 matrix as used by OpenGL and converts it to a 3Space.  Skew factors are lost by
this process.  You can provide an array of 16 values (column major order) or an array of arrays.

=head1 ATTRIBUTES

=head2 parent

Optional reference to parent coordinate space.  The origin and each of the axis vectors are
described in terms of the parent coordiante space.  A parent of C<undef> means the space is
described in terms of global absolute coordiantes.

=head2 origin

The C<< [x,y,z] >> vector (point) of this space's origin in terms of the parent space.

=head2 xv

The C<< [x,y,z] >> unit vector of the X axis (typically understood to be "rightward")

=head2 yv

The C<< [x,y,z] >> unit vector of the Y axis (typically understood to point "upward")

=head2 zv

The C<< [x,y,z] >> unit vector of the Z axis (typically understood to point "outward" toward
the eyes of the viewer)

=head1 METHODS

=head2 clone

Return a new space with the same values, including same parent.

=head2 space

Return a new space describing an identity, with the current object as its parent.

=head2 project

Project a point into this coordinate space.  You may optionally specify a space it is being
projected from, else this assumes it comes from global absolute coordinates.  A new vector
is returned (stored in the same format as you supplied)  You may also pass an array or buffer
of vectors.

=head2 reparent

Project this coordiante space into a different parent coordinate space, including C<undef> to
reference global absolute coordiantes.  (This is named 'reparent' rather than 'set_parent' to
emphasize that it changes the whole object, not just the parent attribute)

=head2 normalize

Ensure that the eigenvectors are unit length and orthagonal to eachother.  The algorithm is:

  * make zv a unit vector
  * xv = yv cross zv, and make it a unit vector
  * yv = xv cross zv, and make it a unit vector

=head2 move

  $space->move($x, $y, $z);
  $space->move([$x, $y, $z]);
  $space->move($vec);

Translate the origin of the coordiante space, in terms of parent coordinates.

=head2 move_rel

  $space->move_rel($x, $y, $z);
  $space->move_rel([$x, $y, $z]);
  $space->move_rel($vec);

Translate the origin of the coordiante space in terms of its own axes.

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

Scale the axes of this space.

=head2 rotate

  $space->rotate($revolutions, 'x');
  $space->rotate($revolutions, 'y');
  $space->rotate($revolutions, 'z');
  $space->rotate($revolutions, 'xv');
  $space->rotate($revolutions, 'yv');
  $space->rotate($revolutions, 'zv');
  $space->rotate($revolutions, $vec);
  $space->rotate($revolutions, $x, $y, $z);

This rotates the C<xv>, C<yv>, and C<zv> by an angle (measured in rotations rather than degrees
or radians, so .25 is a quarter rotation) relative to some other vector.

Vectors 'x', 'y', or 'z' refer to the parent coordinate space axes.  'xv', 'yv', or 'zv' refer
to the attributes of this coordinate space. (i.e. rotate it around its own axis)

If you supply C<$vec> or C<< ($x,$y,$z) >> they are considered as Parent coordiantes.  If you
want to rotate around an arbitrary vector *within* this coordinate sspace, just project it out
to the parent coordiante space first.

The following (slightly more efficient) aliases are available:

=over

=item rotate_x

=item rotate_y

=item rotate_z

=item rotate_xv

=item rotate_yv

=item rotate_zv

=back

=cut

