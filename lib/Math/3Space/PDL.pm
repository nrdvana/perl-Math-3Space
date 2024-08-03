package Math::3Space::PDL;

# VERSION
# ABSTRACT: 3D Coordinate math with an intuitive cross-space mapping API

use strict;
use warnings;
use Carp;
use PDL::Lite;
use PDL::Constants qw(PI);
use constant NV_tolerance => 1e-14;
use Scalar::Util qw(refaddr);

use overload
  '""' => sub { $_[0]{pdl}.'' },
  '==' => sub { (refaddr($_[0])//0) == (refaddr($_[1])//0) }, # reference equality
  ;

=head1 SYNOPSIS

  use Math::3Space::PDL 'vec3', 'space';

  my $boat= space;
  my $sailor= space($boat);
  my $dock= space;

  # boat moves, carrying sailor with it
  $boat->translate(0,0,1)->rotate(.001, [0,1,0]);

  # sailor walks onto the dock
  $sailor->translate(10,0,0);
  $sailor->reparent($dock);

  # The boat and dock are both floating
  for ($dock, $boat) {
    $_->translate(rand(.1), rand(.1), rand(.1))
      ->rotate(rand(.001), [1,0,0])
      ->rotate(rand(.001), [0,0,1]);
  }

  # Sailor is holding a rope at 1,1,1 relative to themself.
  # Where is the end of the rope in boat-space?
  my $rope_end= vec3(1,1,1);
  $sailor->unproject_inplace($rope_end);
  $dock->unproject_inplace($rope_end);
  $boat->project_inplace($rope_end);

  # Do the same thing in bulk with fewer calculations
  my $sailor_to_boat= space($boat)->reparent($sailor);
  @boat_points= $sailor_to_boat->project(@sailor_points);

  # Interoperate with OpenGL
  @float16= $boat->get_gl_matrix;

=head1 DESCRIPTION

This module implements the sort of 3D coordinate space math that would typically be done using
a 4x4 matrix, but instead uses a 3x4 matrix composed of axis vectors C<xv>, C<yv>, C<zv>
(i.e. vectors that point along the axes of the coordinate space) plus an origin point.
This results in significantly fewer math operations needed to project points, and gives you a
more useful mental model to work with, like being able to see which direction the coordinate
space is "facing", or which way is "up".

The coordinate spaces track their L</parent> coordinate space, so you can perform advanced
projections from a space inside a space out to a different space inside a space inside a space
without thinking about the details.

The coordinate spaces can be exported as 4x4 matrices for use with OpenGL or other common 3D
systems.

Specifically, this module uses L<PDL> for all its data storage and
manipulation, unlike L<Math::3Space> which uses its own custom XS
vector code.

=cut

{ package Math::3Space::PDL::Exports;
	use Exporter::Extensible -exporter_setup => 1;
	require Math::3Space::PDL::Vector;
	*vec3= *Math::3Space::PDL::Vector::vec3;
	*space= *Math::3Space::PDL::space;
	export 'vec3', 'space';
}
sub import { shift; Math::3Space::PDL::Exports->import_into(scalar(caller), @_) }
*_parseargs = \&Math::3Space::PDL::Vector::_parseargs;

sub parent { $_[0]{parent} }

=head1 CONSTRUCTOR

=head2 space

  $space= Math::3Space::PDL::space();
  $space= Math::3Space::PDL::space($parent);
  $space= $parent->space;

Construct a space (optionally within C<$parent>) initialized to an identity:

  origin => [0,0,0],
  xv     => [1,0,0],
  yv     => [0,1,0],
  zv     => [0,0,1],

=cut

my $identity = pdl(
  [1,0,0],
  [0,1,0],
  [0,0,1],
  [0,0,0], # origin
);
sub space {
  my ($parent) = @_;
  my $self = bless {parent=>$parent}, __PACKAGE__;
  $self->{pdl} = $identity->copy;
  $self->{n_parents} = defined $parent ? $parent->{n_parents}+1 : 0;
  $self->{is_normal} = 1;
  $self;
}

=head2 new

  $space= Math::3Space::PDL->new(%attributes)

Initialize a space from raw attributes.

=head1 ATTRIBUTES

=head2 parent

Optional reference to parent coordinate space.  The origin and each of the axis vectors are
described in terms of the parent coordinate space.  A parent of C<undef> means the space is
described in terms of global absolute coordinates.

=head2 parent_count

Number of parent coordinate spaces above this one, i.e. the "depth" of this node in the
hierarchy.

=cut

sub parent_count {
  my ($space) = @_;
  $space->_recache_parent;
  $space->{n_parents};
}

=head2 origin

The C<< [x,y,z] >> vector (point) of this space's origin in terms of the parent space.

=head2 xv

The C<< [x,y,z] >> vector of the X axis (often named "I" in math text)

=head2 yv

The C<< [x,y,z] >> vector of the Y axis (often named "J" in math text)

=head2 zv

The C<< [x,y,z] >> vector of the Z axis (often named "K" in math text)

=cut

for (['xv', 0], ['yv', 1], ['zv', 2], ['origin', 3]) {
  my ($name, $offset) = @$_;
  no strict 'refs';
  *$name = sub {
    my ($space, @vals) = @_;
    my $vec = @vals ? _parseargs(@vals) : undef;
    my $slice = $space->{pdl}->slice(",($offset)");
    return Math::3Space::PDL::Vector::vec3($slice->sever) if !defined $vec;
    $slice .= $vec;
    $space->{is_normal} = -1 if $offset < 3;
    $space;
  };
}

=head2 is_normal

Returns true if all axis vectors are unit-length and orthogonal to each other.

=cut

sub is_normal {
  return $_[0]{is_normal} if $_[0]{is_normal} >= 0;
  my $pdl = $_[0]{pdl}->slice(',0:2');
  $_[0]{is_normal} = 0;
  return 0 if !$pdl->ipow(2)->sumover->approx(1, NV_tolerance)->all;
  my @vecs = $pdl->dog;
  for (map [$_-1,$_], 0..$#vecs) {
    return 0 if !$vecs[$_->[0]]->inner($vecs[$_->[1]])->approx(0, NV_tolerance);
  }
  $_[0]{is_normal} = 1;
}

=head1 METHODS

=head2 clone

Return a new space with the same values, including same parent.

=cut

sub clone {
  my ($space) = @_;
  bless {pdl=>$space->{pdl}->copy, parent=>$space->{parent}, n_parents=>$space->{n_parents}}, __PACKAGE__;
}

=head2 space

Return a new space describing an identity, with the current object as its parent.

=head2 reparent

Project this coordinate space into a different parent coordinate space.  After the projection,
this space still refers to the same absolute global coordinates as it did before, but it is
described in terms of a different parent coordinate space.

For example, in a 3D game where a player is riding in a vehicle, the parent of the player's
3D space is the vehicle, and the parent space of the vehicle is the ground.
If the player jumps off the vehicle, you would call C<< $player->reparent($ground); >> to keep
the player at their current position, but begin describing them in terms of the ground.

Setting C<$parent> to C<undef> means "global coordinates".

=cut

sub _recache_parent {
  my ($space_orig) = @_;
  my ($depth, $space, $prev, %seen) = 0;
  my $cur = $space_orig;
  while ($cur) {
    $prev = $space;
    croak("'parent' is not a Math::3Space : $cur")
      if !UNIVERSAL::isa($cur, __PACKAGE__);
    my $cur_parent = ($space = $cur)->{parent};
    $cur->{parent} = undef;
    if ($prev) {
      $prev->{parent} = $space;
      if (++$depth > 964) { # Check for cycles in the graph
        croak("Cycle detected in space->parent graph")
          if $seen{refaddr $space};
        $seen{refaddr $space} = 1; # signal that we've been here with any pointer value
      }
    }
    $cur = $cur_parent;
  }
  for ($space = $space_orig; $space; $space = $space->{parent}) {
    $space->{n_parents} = $depth--;
  }
}

sub _project_space { # args opposite order from XS
  my ($space, $parent) = @_;
  my ($space_pdl, $parent_pdl) = map $_->{pdl}, $space, $parent;
  my ($parent_basis, $parent_origin) = map $parent_pdl->slice($_), ',0:2', ',3';
  $space_pdl->slice(',3') -= $parent_origin;
  $space_pdl .= $space_pdl x $parent_basis->transpose;
  @$space{qw(parent n_parents)} = ($parent, $parent->{n_parents}+1);
}

sub _unproject_space { # args opposite order from XS
  my ($space, $parent) = @_;
  my ($space_pdl, $parent_pdl) = map $_->{pdl}, $space, $parent;
  my ($parent_basis, $parent_origin) = map $parent_pdl->slice($_), ',0:2', ',3';
  $space_pdl .= $space_pdl x $parent_basis;
  $space_pdl->slice(',3') += $parent_origin;
  @$space{qw(parent n_parents)} = @$parent{qw(parent n_parents)};
}

sub reparent {
  my ($space, $parent) = @_;
  if (defined $parent) {
    $parent->_recache_parent;
    my $cur = $parent;
    while ($cur) {
      croak "Attempt to create a cycle: new 'parent' is a child of this space" if $cur == $space;
      $cur = $cur->parent;
    }
  }
  return $space if $space->{parent} == $parent;
  # Walk back the stack of parents until it has fewer parents than 'space'.
  # This way space->parent has a chance to be 'common_parent'.
  my $common_parent = $parent;
  $common_parent = $common_parent->parent
    while $common_parent && $common_parent->{n_parents} >= $space->{n_parents};
  # Now unproject 'space' from each of its parents until its parent is 'common_parent'.
  while ($space->{n_parents} && !($space->parent == $common_parent)) {
    # Map 'space' out to be a sibling of its parent
    _unproject_space($space, $space->parent);
    # if 'space' reached the depth of common_parent+1 and the loop didn't stop,
    # then it wasn't actually the parent they have in common, yet.
    $common_parent = $common_parent->parent
      if $common_parent && $common_parent->{n_parents} + 1 == $space->{n_parents};
  }
  # At this point, 'space' is either a root 3Space, or 'common_parent' is its parent.
  # If the common parent is the original 'parent', then we're done.
  return $space if ($parent//0) == ($common_parent//0);
  # Calculate an equivalent space to 'parent' at this parent depth.
  croak("assertion failed: parent != NULL") if !defined $parent;
  my $sp_tmp = $parent->clone;
  _unproject_space($sp_tmp, $sp_tmp->{parent}),
    until ($sp_tmp->{parent}//0) == ($common_parent//0);
  # sp_tmp is now equivalent to projecting through the chain from common_parent to parent
  _project_space($space, $sp_tmp);
  $space->{parent} = $parent;
  $space->{n_parents} = $parent->{n_parents} + 1;
  # Note that any space which has 'space' as a parent will now have an invalid n_parents
  # cache, which is why those caches need rebuilt before calling this function.
  $space;
}

=head2 project

  @local_points= $space->project( @parent_points );
  @parent_points= $space->unproject( @local_points );
  @local_vectors= $space->project_vector( @parent_vectors );
  $space->project_inplace( @points );
  $space->project_vector_inplace( @vectors );

Project one or more points (or vectors) into (or out of) this coordinate space.

The C<project> and C<unproject> methods operate on points, meaning that they subtract or add
the Space's C<origin> to the result in addition to (un)projecting along each of the
C<(xv, yv, zv)> axes.

The C<_vector> variants do not add/subtract L</origin>, so vectors that were acting as
directional indicators will still be indicating that direction afterward regardless of this
space's C<origin>.

The C<_inplace> variants modify the points or vectors and return C<$self> for method chaining.

Each parameter is another vector to process.  The projected vectors are returned in a list the
same length and format as the list passed to this function, e.g. if you supply
L<Math::3Space::PDL::Vector> objects you get back C<Vector> objects.  If you supply C<[x,y,z]>
arrayrefs you get back arrayrefs.

Variants:

=over

=item project_vector_inplace

=item project_inplace

=item unproject_vector_inplace

=item unproject_inplace

=cut

for (['project_vector_inplace', 0], ['project_inplace', 1], ['unproject_vector_inplace', 2], ['unproject_inplace', 3]) {
  my ($name, $ix) = @$_;
  no strict 'refs';
  *$name = sub {
    my ($space, @vals) = @_;
    my $space_mat = $space->{pdl}->slice(',0:2');
    $space_mat = $space_mat->transpose if $ix <= 1;
    my $origin = ($ix % 2) ? $space->{pdl}->slice(',(3)') : undef;
    for my $val (@vals) {
      my $vec = _parseargs($val);
      $vec -= $origin if $ix == 1;
      $vec .= $vec x $space_mat;
      $vec += $origin if $ix == 3;
      if (ref($val) eq 'ARRAY') {
        my @list = $vec->list;
        @list = @list[0..$#$val] if @$val > @list;
        @$val = @list;
      }
    }
    $space;
  };
}

=item project_vector

=item project

=item unproject_vector

=item unproject

=cut

for (['project_vector', 0], ['project', 1], ['unproject_vector', 2], ['unproject', 3]) {
  my ($name, $ix) = @$_;
  no strict 'refs';
  *$name = sub {
    my ($space, @vals) = @_;
    my $space_mat = $space->{pdl}->slice(',0:2');
    $space_mat = $space_mat->transpose if $ix <= 1;
    my $origin = ($ix % 2) ? $space->{pdl}->slice(',(3)') : undef;
    my @ret;
    for my $val (@vals) {
      my $vec = _parseargs($val)->copy;
      $vec -= $origin if $ix == 1;
      $vec .= $vec x $space_mat;
      $vec += $origin if $ix == 3;
      push @ret, ref($val) eq 'ARRAY' ? [$vec->list] :
        UNIVERSAL::isa($val, 'PDL') ? $vec :
        Math::3Space::PDL::Vector::vec3($vec);
    }
    @ret == 1 ? $ret[0] : @ret;
  };
}

=back

=head2 normalize

Ensure that the C<xv>, C<yv>, and C<zv> axis vectors are unit length and orthogonal to
each other, like proper eigenvectors.  The algorithm is:

  * make zv a unit vector
  * xv = yv cross zv, and make it a unit vector
  * yv = xv cross zv, and make it a unit vector

=head2 translate

  $space->translate($x, $y, $z);
  $space->translate([$x, $y, $z]);
  $space->translate($vec);
  # alias 'tr'
  $space->tr(...);

Translate the origin of the coordinate space, in terms of parent coordinates.

=for Pod::Coverage tr

=cut

sub translate {
  my ($space, @vals) = @_;
  my $vec = _parseargs(@vals);
  my $origin = $space->{pdl}->slice(",(3)");
  $origin += $vec;
  $space;
}
*tr = \&translate;

=head2 travel

  $space->travel($x, $y, $z);
  $space->travel([$x, $y, $z]);
  $space->travel($vec);
  # alias 'go'
  $space->go(...);

Translate the origin of the coordinate space in terms of its own coordinates.
e.g. if your L</zv> vector is being used as "forward", you can make an object travel
forward with C<< $space->travel(0,0,1) >>.

=for Pod::Coverage go

=cut

sub travel {
  my ($space, @vals) = @_;
  my $vec = _parseargs(@vals);
  my $origin = $space->{pdl}->slice(",(3)");
  $origin += $vec x $space->{pdl}->slice(",0:2");
  $space;
}
*go = \&travel;

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

=cut

sub scale {
  my ($space, @vals) = @_;
  if (!ref $vals[0] and 0+@vals == 1) {
    @vals = (@vals) x 3;
  } elsif (!ref $vals[0] and @vals < 3) {
    $vals[$_] //= $vals[0] for 1..2;
  }
  my $vec = _parseargs(@vals);
  $space->{pdl}->slice(",0:2") *= $vec->transpose;
  $space->{is_normal} = -1;
  $space;
}

=head2 rotate

  $space->rotate($revolutions, $x, $y, $z);
  $space->rotate($revolutions, [$x, $y, $z]);
  $space->rotate($revolutions, $vec);

  $space->rot($revolutions => ...); # alias for 'rotate'

  $space->rot_x($revolutions);      # optimized for specific vectors
  $space->rot_xv($revolutions);

This rotates the C<xv>, C<yv>, and C<zv> axes by an angle around some other vector.  The angle
is measured in revolutions rather than degrees or radians, so C<1> is a full rotation back to
where you started, and .25 is a quarter rotation.  The vector is defined in terms of the parent
coordinate space.  If you want to rotate around an arbitrary vector defined in *local*
coordinates, just unproject it out to the parent coordinate space first.

=cut

my $ZEROVEC = pdl(0,0,0);
my $X_UNITVEC = pdl(1,0,0);
my $Y_UNITVEC = pdl(0,1,0);
sub rotate {
  my ($space, $angle, @vals) = @_;
  my $vec = _parseargs(@vals);
  croak "Can't rotate around vector with 0 magnitude" if $ZEROVEC->eq($vec)->all;
  my $zv = $vec->norm;
  my $xv = $X_UNITVEC->crossp($zv);
  $xv = $Y_UNITVEC->crossp($zv) if $xv->ipow(2)->sumover < NV_tolerance;
  my $yv = $zv->crossp($xv);
  my $rot_mat = pdl($xv, $yv, $zv)->norm;
  my $space_mat = $space->{pdl}->slice(',0:2');
  my $projected = $space_mat x $rot_mat->transpose;
  $angle *= 2 * PI;
  my ($s, $c) = (sin $angle, cos $angle);
  my ($mo1, $mo2) = map $projected->slice($_), 0, 1;
  my ($tmp1, $tmp2) = ($c * $mo1 - $s * $mo2, $s * $mo1 + $c * $mo2);
  $mo1 .= $tmp1;
  $mo2 .= $tmp2;
  $space_mat .= $projected x $rot_mat;
  $space;
}
*rot = \&rotate;

=pod

The following (more efficient) variants are available for rotating about the parent's axes or
this space's own axes:

=for Pod::Coverage rot

=over

=item rot_x

=item rot_y

=item rot_z

=cut

for (['rot_x', 0], ['rot_y', 1], ['rot_z', 2]) {
  my ($name, $ix) = @$_;
  no strict 'refs';
  my ($ofs1, $ofs2) = (($ix+1)%3, ($ix+2)%3);
  *$name = sub {
    my ($space, $angle) = @_;
    $angle *= 2 * PI;
    my ($s, $c) = (sin $angle, cos $angle);
    my $pdl = $space->{pdl}->slice(',0:2');
    my ($mo1, $mo2) = map $pdl->slice($_), $ofs1, $ofs2;
    my ($tmp1, $tmp2) = ($c * $mo1 - $s * $mo2, $s * $mo1 + $c * $mo2);
    $mo1 .= $tmp1;
    $mo2 .= $tmp2;
    $space;
  };
}

=item rot_xv

=item rot_yv

=item rot_zv

=cut

for (['rot_xv', 0], ['rot_yv', 1], ['rot_zv', 2]) {
  my ($name, $ix) = @$_;
  no strict 'refs';
  my ($ofs1, $ofs2) = (($ix+1)%3, ($ix+2)%3);
  *$name = sub {
    my ($space, $angle) = @_;
    return $space->rotate($angle, $space->{pdl}->slice(",($ix)")) if !$space->is_normal;
    $angle *= 2 * PI;
    my ($s, $c) = (sin $angle, cos $angle);
    my $space_mat = $space->{pdl}->slice(',0:2');
    if ($ix == 0) {
      my $rotated = pdl([0,$c,$s], [0,-$s,$c]); # yv, zv
      $space_mat->slice(',1:2') .= ($rotated x $space_mat);
    } elsif ($ix == 1) {
      my $rotated = pdl([$c,0,-$s], [$s,0,$c]); # xv, zv
      $space_mat->slice(',0:2:2') .= ($rotated x $space_mat);
    } else {
      my $rotated = pdl([$c,$s,0], [-$s,$c,0]); # xv, yv
      $space_mat->slice(',0:1') .= ($rotated x $space_mat);
    }
    $space;
  };
}

=back

=head2 get_gl_matrix

  @float16= $space->get_gl_matrix();
  $space->get_gl_matrix($buffer);

Get an OpenGL-compatible 16-element array representing a 4x4 matrix that would perform the same
projection as this space.  This can either be returned as 16 perl floats, or written into a
packed buffer of 16 doubles.

=cut

my $GL_app = pdl(0,0,0,1)->transpose;
sub get_gl_matrix {
  my ($space) = @_;
  my @floats = $space->{pdl}->append($GL_app)->list;
  return @floats if @_ < 2;
  $_[1] = pack(d16 => @floats);
}

1;
