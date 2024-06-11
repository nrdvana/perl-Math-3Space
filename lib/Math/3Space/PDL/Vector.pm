package Math::3Space::PDL::Vector;

# VERSION
# ABSTRACT: Object wrapping a PDL buffer of three NVs

use strict; use warnings;
use Exporter 'import';
our @EXPORT_OK= qw( vec3 );

use PDL::Lite;
use Config;
use Carp;

use overload '""' => sub { $_[0]{pdl}.'' };

=head1 SYNOPSIS

  use Math::3Space::PDL::Vector 'vec3';

  $vec= vec3(1,2,3);

  say $vec->x;
  $vec->x(12);

  ($x, $y, $z)= $vec->xyz;
  $vec->set(4,3,2);

  $dot_product= vec3(0,1,0)->dot(1,0,0);
  $cross_product= vec3(1,0,0)->cross(0,0,1);

=head1 DESCRIPTION

This object is a blessed hash-ref with a PDL buffer of double-precision
numbers. The zero-th dimension is always length 3.  For more general
vector classes, see many other modules on CPAN.  This is simply an
efficient way for the 3Space object to pass vectors around without fully
allocating Perl structures for them.

=head1 CONSTRUCTOR

=head2 vec3

  $vec= vec3($x, $y, $z);
  $vec= vec3([ $x, $y, $z ]);
  $vec2= vec3($vec);

=cut

sub vec3 {
  __PACKAGE__->new(
    (@_ == 1 && ref $_[0] && UNIVERSAL::isa($_[0], 'PDL')) ? $_[0] :
    (@_ == 1 && ref $_[0] && UNIVERSAL::isa($_[0], __PACKAGE__)) ? $_[0]{pdl} :
    @_ > 1 ? \@_ : @_
  )
}

=head2 new

  $vec= Math::3Space::PDL::Vector->new(); # 0,0,0
  $vec= Math::3Space::PDL::Vector->new([ $x, $y, $z ]);
  $vec= Math::3Space::PDL::Vector->new(x => $x, y => $y, z => $z);
  $vec= Math::3Space::PDL::Vector->new({ x => $x, y => $y, z => $z });

=cut

sub _parseargs {
  my ($x_or_vec, $y, $z) = @_;
  if (defined $y) {
    return pdl($x_or_vec, $y, $z);
  } elsif (ref $x_or_vec eq 'ARRAY') {
    return pdl($x_or_vec);
  } elsif (ref $x_or_vec eq 'HASH') {
    return pdl(@$x_or_vec{qw(x y z)});
  } elsif (ref $x_or_vec and UNIVERSAL::isa($x_or_vec, 'PDL')) {
    return $x_or_vec;
  } elsif (ref $x_or_vec and UNIVERSAL::isa($x_or_vec, __PACKAGE__)) {
    return $x_or_vec->{pdl};
  } elsif (length($x_or_vec) == 3*$Config{nvsize}) {
    my $type = PDL::Type->new($Config{nvsize} == 8 ? 'double' : $Config{nvsize} == 4 ? 'float' : die "Unknown NV size $Config{nvsize}");
    my $vec = PDL->zeroes($type, 3);
    ${$vec->get_dataref} = $x_or_vec;
    $vec->upd_data;
    return $vec;
  } else {
    croak "Can't handle ($x_or_vec, @{[$y//'undef']}, @{[$z//'undef']})";
  }
}

sub new {
  my ($class, @vals) = @_;
  my $val;
  if (!@vals) {
    $val = [0,0,0];
  } elsif (!(@vals % 2)) {
    $val = {@vals};
  } elsif (@vals != 1) {
    croak "Expected even-length list or one element, got (@vals)";
  } elsif (ref $vals[0] and ref $vals[0] ne 'ARRAY' and ref $vals[0] ne 'HASH' and !UNIVERSAL::isa($vals[0], 'PDL')) {
    croak "Expected one hash- or array-ref, got (@vals)";
  } else {
    $val = $vals[0];
  }
  my $vec = _parseargs($val);
  bless {pdl=>$vec}, $class;
}

=head1 ATTRIBUTES

=head2 x

Read/write 'x' field.

=head2 y

Read/write 'y' field.

=head2 z

Read/write 'z' field.

=cut

for (['x', 0], ['y', 1], ['z', 2]) {
  my ($name, $offset) = @$_;
  no strict 'refs';
  *$name = sub {
    my ($self, $val) = @_;
    return $self->{pdl}->at($offset) if !defined $val;
    $self->{pdl}->set($offset, $val);
    $self;
  };
}

=head2 xyz

Return list of (x,y,z).

=cut

sub xyz {my ($self) = @_; $self->{pdl}->list;}

=head2 magnitude

  $mag= $vector->magnitude;
  $vector->magnitude($new_length);

Read/write length of vector.  Attempting to write to a vector with length 0 emits a warning and
does nothing.

=cut

sub magnitude {
  my ($self, $newval) = @_;
  my $length = $self->{pdl}->ipow(2)->sumover->sqrt;
  return $length if !defined $newval;
  warn("Attempting to write to a vector with length 0"), return if !$length;
  $self->{pdl} *= $newval / $length;
  $self;
}

=head1 METHODS

=head2 set

  $vector->set($vec2);
  $vector->set($x,$y,$z);
  $vector->set([$x,$y,$z]);

=head2 add

  $vector->add($vec2);
  $vector->add($x,$y);
  $vector->add($x,$y,$z);
  $vector->add([$x,$y,$z]);

=head2 sub

  $vector->sub($vec2);
  $vector->sub($x,$y);
  $vector->sub($x,$y,$z);
  $vector->sub([$x,$y,$z]);

=cut

for ([qw(set assgn)], [qw(add plus)], [qw(sub minus)]) {
  my ($name, $op) = @$_;
  no strict 'refs';
  *$name = sub {
    my ($self, @vals) = @_;
    if (!ref $vals[0]) {
      $vals[$_] //= 0 for 1..2;
    }
    my $vec = _parseargs(@vals);
    if ($op eq 'assgn') {
      $vec->$op($self->{pdl});
    } else {
      $self->{pdl}->inplace->$op($vec);
    }
    $self;
  };
}

=head2 scale

  $vector->scale($scale); # x= y= z= $scale
  $vector->scale($x, $y); # z= 1
  $vector->scale($x, $y, $z);
  $vector->scale([$x, $y, $z]);
  $vector->scale($vec2);

Multiply each component of the vector by a scalar.

=cut

sub scale {
  my ($self, @vals) = @_;
  if (!ref $vals[0] and 0+@vals == 1) {
    @vals = (@vals) x 3;
  } elsif (!ref $vals[0]) {
    $vals[$_] //= 1 for 1..2;
  }
  my $vec = _parseargs(@vals);
  $self->{pdl}->inplace;
  $self->{pdl}->mult($vec);
  $self;
}

=head2 dot

  $prod= $vector->dot($vector2);
  $prod= $vector->dot($x,$y,$z);
  $prod= $vector->dot([$x,$y,$z]);

Dot product with another vector.

=cut

sub dot {
  my ($self, @vals) = @_;
  my $vec = _parseargs(@vals);
  $self->{pdl}->inner($vec);
}

=head2 cos

  $cos= $vector->cos($vector2);
  $cos= $vector->cos($x,$y,$z);
  $cos= $vector->cos([$x,$y,$z]);

Return the vector-cosine to the other vector.  This is the same as the dot product divided by
the magnitudes of the vectors, or identical to the dot product when the vectors are unit-length.
This dies if either vector is zero length (or too close to zero for available floating precision).

=cut

sub cos {
  my ($self, @vals) = @_;
  my $vec = _parseargs(@vals);
  my $actual_dot_product = $self->{pdl}->inner($vec);
  my ($abs2_1, $abs2_2) = map $_->ipow(2)->sumover, $self->{pdl}, $vec;
  $actual_dot_product->divide($abs2_1->mult($abs2_2)->sqrt);
}

=head2 cross

  $c= $a->cross($b);
  $c= $a->cross($bx, $by, $bz);
  $c= $a->cross([$bx, $by, $bz]);
  $c->cross($a, $b);

Return a new vector which is the cross product C<< A x B >>, or if called with 2 parameters
assign the cross product to the object itself.

=cut

sub cross {
  my ($self, @vals) = @_;
  my ($vec, $vec2);
  if (@vals == 2) {
    ($vec, $vec2) = map _parseargs($_), @vals;
  } else {
    $vec = _parseargs(@vals);
  }
  if (defined $vec2) {
    $self->{pdl} .= $vec->crossp($vec2);
    return $self;
  }
  bless {pdl=>$self->{pdl}->crossp($vec)}, ref($self);
}

1;
