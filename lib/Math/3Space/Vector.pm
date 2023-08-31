package Math::3Space::Vector;
# All methods handled by XS
require Math::3Space;
1;
__END__

=head1 SYNOPSIS

  $vec= Math::3Space::Vector->new(1,2,3);
  say $vec->x;
  $vec->x(12);
  ($x, $y, $z)= $vec->xyz;
  $vec->xyz(4,3,2);

=head1 DESCRIPTION

This object is a blessed scalar-ref of a buffer of floating point numbers (Perl's float type,
either double or long double).  The vector is always 3 elements long.  For more general vector
classes, see many other modules on CPAN.  This is simply an efficient way for the 3Space object
to pass vectors around without fully allocating Perl structures for them.

=head1 CONSTRUCTOR

=head2 new

  $vec= Math::3Space::Vector->new($x, $y, $z);

=head1 ATTRIBUTES

=head2 x

Read/write 'x' field.

=head2 y

Read/write 'y' field.

=head2 z

Read/write 'z' field.

=head2 xyz

Read/write list of (x,y,z).

