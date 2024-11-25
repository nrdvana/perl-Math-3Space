package Math::3Space::Projection;

# VERSION
# ABSTRACT: Object wrapping a 4D projection, for rendering use

use Exporter 'import';
our @EXPORT_OK= qw( perspective frustum );

# All methods handled by XS
require Math::3Space;

use overload '""' => sub { "[@{[$_[0]->get_gl_matrix]}]" };

1;
__END__

=head1 SYNOPSIS

  use Math::3Space 'space';
  use Math::3Space::Projection 'perspective';
  
  my $projection= perspective(1/5, 4/3, 1, 10000);
  my $modelview= space;
  glLoadMatrixf_p($projection->gl_matrix($modelview));
  # or
  glLoadMatrixf_s($projection->gl_matrix_packed_float($modelview));

=head1 DESCRIPTION

While the 3Space objects can represent all 3D affine coordinate transformations, they cannot
represent the final 4D transformation that OpenGL uses for a perspective projection.  The
perspective transformation stretches the near-Z coordinates while squashing the far-Z
coordinates, which can't be described by 3D eigenvectors.  This is the reason all the typical
3D math is using 4x4 matrices.

But, in keeping with the theme of this module collection, you can in fact take a 3x4 Space
matrix and multiply it by a (logically) 4x4 projection matrix in many fewer multiplications
than invoking the full 4x4 matrix math.  Multiplying two 4x4 matrices is nominally 64
multiplications, but this module does it in 20, or 12 for a centered frustum!

=head1 EXPORTED FUNCTIONS

=head2 perspective

  my $projection= perspective($vertical_field_of_view, $aspect, $near_z, $far_z);

C<$vertical_field_of_view> is in "revolutions", not radians.  This saves you from needing to
mention Pi in your parameter.

C<$aspect> is the typical "4/3" ot "16/9" ratio of width over height.

C<$near_z> and C<far_z> are the range of Z coordinates of the space to be projected.

=head2 frustum

  my $perspective= frustum($left, $right, $bottom, $top, $near_z, $far_z);

Same as OpenGL's L<glFrustum|https://docs.gl/gl3/glFrustum>.  It describes the edges of the
near face of a stretched box where the sides of the box are planes that pass through the origin
and the edge of the viewport at C<$near_z>, continuing outward until they reach C<$far_z>.

=head1 CONSTRUCTOR

=head2 new

  $projection= Math::3Space::Projection->new(
    left   => 1,
    right  => 1,
    width  => 2,
    top    => 1,
    bottom => 1,
    height => 2,
    near   => 1,
    far    => 10000,
    aspect => 16/9,
    fov    => 1/5,
  );

Create a projection from named attributes.  If you under-specify a frustum the missing details
will be filled with the OpenGL default of C<< [-1,1] >> ranges.

=head1 METHODS

=head2 gl_matrix

  @mat16= $projection->gl_matrix;         # the matrix of the projection itself
  @mat16= $projection->gl_matrix($space); # the space transformed by the projection

Returns the 16 floating point values of the 4x4 matrix, in column-major order as used by OpenGL.

=head2 gl_matrix_packed_float

  $gl_float_buffer= $projection->gl_matrix_packed_float;
  $gl_float_buffer= $projection->gl_matrix_packed_float($space);

Same as C<gl_matrix>, but pack the numbers into a scalar of floats.

=head2 gl_matrix_packed_double

  $gl_double_buffer= $projection->gl_matrix_packed_double;
  $gl_double_buffer= $projection->gl_matrix_packed_double($space);

Same as C<gl_matrix>, but pack the numbers into a scalar of doubles.

=cut
