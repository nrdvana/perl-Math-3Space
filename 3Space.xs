#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <math.h>

struct m3s_space;
typedef struct m3s_space m3s_space_t;

#define SPACE_XV(s)     ((s)->mat + 0)
#define SPACE_YV(s)     ((s)->mat + 3)  
#define SPACE_ZV(s)     ((s)->mat + 6)
#define SPACE_ORIGIN(s) ((s)->mat + 9)
struct m3s_space {
	NV mat[12];
};

typedef NV m3s_vector_t[3];
typedef NV *m3s_vector_p;

/*------------------------------------------------------------------------------------
 * Definitions of Perl MAGIC that attach C structs to Perl SVs
 * All instances of Math::3Space have a magic-attached struct m3s_space_t
 */

// destructor for m3s_space_t
static int m3s_space_magic_free(pTHX_ SV* sv, MAGIC* mg) {
	m3s_space_t *space;
    if (mg->mg_ptr) {
		Safefree(mg->mg_ptr);
		mg->mg_ptr= NULL;
	}
    return 0; // ignored anyway
}
#ifdef USE_ITHREADS
static int m3s_space_magic_dup(pTHX_ MAGIC *mg, CLONE_PARAMS *param) {
    m3s_space_t *space;
	PERL_UNUSED_VAR(param);
	Newxz(space, 1, m3s_space_t);
	memcpy(space, mg->mg_ptr, sizeof(m3s_space_t));
	mg->mg_ptr= (char*) space;
    return 0;
};
#else
#define m3s_space_magic_dup NULL
#endif

// magic table for m3s_space
static const MGVTBL m3s_space_magic_vt= {
	NULL, /* get */
	NULL, /* write */
	NULL, /* length */
	NULL, /* clear */
	m3s_space_magic_free,
	NULL, /* copy */
	m3s_space_magic_dup
#ifdef MGf_LOCAL
	,NULL
#endif
};

// Return the m3s_space struct attached to a Perl object via MAGIC.
// The 'obj' should be a reference to a blessed SV.
// Use AUTOCREATE to attach magic and allocate a struct if it wasn't present.
// Use OR_DIE for a built-in croak() if the return value would be NULL.
#define AUTOCREATE 1
#define OR_DIE     2
static m3s_space_t* m3s_get_magic_space(SV *obj, int flags) {
	SV *sv;
	MAGIC* magic;
    m3s_space_t *space;
	if (!sv_isobject(obj)) {
		if (flags & OR_DIE)
			croak("Not an object");
		return NULL;
	}
	sv= SvRV(obj);
	if (SvMAGICAL(sv)) {
        /* Iterate magic attached to this scalar, looking for one with our vtable */
        for (magic= SvMAGIC(sv); magic; magic = magic->mg_moremagic)
            if (magic->mg_type == PERL_MAGIC_ext && magic->mg_virtual == &m3s_space_magic_vt)
                /* If found, the mg_ptr points to the fields structure. */
                return (m3s_space_t*) magic->mg_ptr;
    }
    if (flags & AUTOCREATE) {
        Newxz(space, 1, m3s_space_t);
        magic= sv_magicext(sv, NULL, PERL_MAGIC_ext, &m3s_space_magic_vt, (const char*) space, 0);
#ifdef USE_ITHREADS
        magic->mg_flags |= MGf_DUP;
#endif
        return space;
    }
    else if (flags & OR_DIE)
        croak("Object lacks 'm3s_space_t' magic");
	return NULL;
}

// Return existing Node object, or create a new one.
// Returned SV is a reference with active refcount, which is what the typemap
// wants for returning a "struct TreeRBXS_item*" to perl-land
static SV* m3s_wrap_space(m3s_space_t *space) {
	SV *obj;
	MAGIC *magic;
	// Since this is used in typemap, handle NULL gracefully
	if (!space)
		return &PL_sv_undef;
	// Create a node object
	obj= newRV_noinc((SV*)newHV());
	sv_bless(obj, gv_stashpv("Math::3Space", GV_ADD));
	magic= sv_magicext(SvRV(obj), NULL, PERL_MAGIC_ext, &m3s_space_magic_vt, (const char*) space, 0);
#ifdef USE_ITHREADS
	magic->mg_flags |= MGf_DUP;
#else
	(void)magic; // suppress warning
#endif
	return obj;
}

void m3s_read_vector_from_sv(m3s_vector_p vec, SV *in) {
	SV **el;
	AV *vec_av;
	size_t i, n;
	if (SvROK(in) && SvTYPE(SvRV(in)) == SVt_PVAV) {
		vec_av= (AV*) SvRV(in);
		n= av_len(vec_av)+1;
		if (n != 3 && n != 2)
			croak("Vector arrayref must have 2 or 3 elements");
		vec[2]= 0;
		for (i=0; i < n; i++) {
			el= av_fetch(vec_av, i, 0);
			if (!el || !*el || !looks_like_number(*el))
				croak("Vector element %d is not a number", i);
			vec[i]= SvNV(*el);
		}
	} else if (SvROK(in) && SvPOK(SvRV(in)) && SvCUR(SvRV(in)) == sizeof(NV)*3) {
		memcpy(vec, SvPV_nolen(SvRV(in)), sizeof(NV)*3);
	} else
		croak("Can't read vector from %s", sv_reftype(in, 1));
}

#define DOUBLE_ALIGNMENT_MASK 7
static SV* m3s_wrap_vector(m3s_vector_p vec_array) {
	SV *obj, *buf;
	char *p;
	buf= newSVpvn((char*) vec_array, sizeof(NV)*3);
	p= SvPV_nolen(buf);
	// ensure double alignment
	if ((intptr_t)p & DOUBLE_ALIGNMENT_MASK) {
		SvGROW(buf, sizeof(NV)*4);
		p= SvPV_nolen(buf);
		sv_chop(buf, p + sizeof(NV) - ((intptr_t)p & DOUBLE_ALIGNMENT_MASK));
		SvCUR_set(buf, sizeof(NV)*3);
		p= SvPV_nolen(buf);
	}
	obj= newRV_noinc(buf);
	sv_bless(obj, gv_stashpv("Math::3Space::Vector", GV_ADD));
	return obj;
}

static NV * m3s_vector_get_array(SV *vector) {
	char *p= NULL;
	STRLEN len= 0;
	if (sv_isobject(vector) && SvPOK(SvRV(vector)))
		p= SvPV(SvRV(vector), len);
	if (len != sizeof(NV)*3 || ((intptr_t)p & DOUBLE_ALIGNMENT_MASK) != 0)
		croak("Invalid or corrupt Math::3Space::Vector object");
	return (NV*) p;
}

static void m3s_space_project_vector(m3s_space_t *sp, NV *vec) {
	NV x, y, z, *mat= sp->mat;
	vec[0] -= mat[9];
	vec[1] -= mat[10];
	vec[2] -= mat[11];
	x= vec[0] * mat[0] + vec[1] * mat[1] + vec[2] * mat[2];
	y= vec[0] * mat[3] + vec[1] * mat[4] + vec[2] * mat[5];
	y= vec[0] * mat[6] + vec[1] * mat[7] + vec[2] * mat[8];
	vec[0]= x;
	vec[1]= y;
	vec[2]= z;
}

static void m3s_space_unproject_vector(m3s_space_t *sp, NV *vec) {
	NV x, y, z, *mat= sp->mat;
	x= vec[0] * mat[0] + vec[1] * mat[3] + vec[2] * mat[6];
	y= vec[0] * mat[1] + vec[1] * mat[4] + vec[2] * mat[7];
	z= vec[0] * mat[2] + vec[1] * mat[5] + vec[2] * mat[8];
	vec[0]= x + mat[9];
	vec[1]= y + mat[10];
	vec[2]= z + mat[11];
}

static inline void m3s_vector_cross(NV *dest, NV *vec1, NV *vec2) {
	dest[0]= vec1[1]*vec2[2] - vec1[2]*vec2[1];
	dest[1]= vec1[0]*vec2[2] - vec1[2]*vec2[0];
	dest[2]= vec1[0]*vec2[1] - vec1[1]*vec2[0];
}

static inline NV m3s_vector_dotprod(NV *vec1, NV *vec2) {
	NV mag1= vec1[0]*vec1[0] + vec1[1]*vec1[1] + vec1[2]*vec1[2];
	NV mag2= vec2[0]*vec2[0] + vec2[1]*vec2[1] + vec2[2]*vec2[2];
	NV prod= vec1[0]*vec2[0] + vec1[1]*vec2[1] + vec1[2]*vec2[2];
	if (mag1 == 0 || mag2 == 0)
		croak("Can't calculate dot product of vector with length == 0");
	return prod / sqrt(mag1 * mag2);
}

MODULE = Math::3Space              PACKAGE = Math::3Space

void
_init(obj, source=NULL)
	SV *obj
	SV *source
	INIT:
		m3s_space_t *space= m3s_get_magic_space(obj, AUTOCREATE);
		m3s_space_t *src_space;
		HV *attrs;
		SV **field;
	CODE:
		if (source) {
			if (sv_isobject(source)) {
				src_space= m3s_get_magic_space(source, OR_DIE);
				memcpy(space, src_space, sizeof(*space));
			} else if (SvROK(source) && SvTYPE(source) == SVt_PVHV) {
				attrs= (HV*) SvRV(source);
				if ((field= hv_fetch(attrs, "xv", 2, 0)) && *field && SvOK(*field))
					m3s_read_vector_from_sv(SPACE_XV(space), *field);
				else
					SPACE_XV(space)[0]= 1;
				if ((field= hv_fetch(attrs, "yv", 2, 0)) && *field && SvOK(*field))
					m3s_read_vector_from_sv(SPACE_YV(space), *field);
				else
					SPACE_YV(space)[1]= 1;
				if ((field= hv_fetch(attrs, "zv", 2, 0)) && *field && SvOK(*field))
					m3s_read_vector_from_sv(SPACE_ZV(space), *field);
				else
					SPACE_ZV(space)[2]= 1;
				if ((field= hv_fetch(attrs, "origin", 6, 0)) && *field && SvOK(*field))
					m3s_read_vector_from_sv(SPACE_ORIGIN(space), *field);
			} else
				croak("Invalid source for _init");
		} else {
			SPACE_XV(space)[0]= 1;
			SPACE_YV(space)[1]= 1;
			SPACE_ZV(space)[2]= 1;
		}

SV*
clone(obj)
	SV *obj
	INIT:
		m3s_space_t *space= m3s_get_magic_space(obj, OR_DIE);
		HV *clone_hv;
	CODE:
		if (SvTYPE(SvRV(obj)) != SVt_PVHV)
			croak("Invalid source object"); // just to be really sure before next line
		clone_hv= newHVhv((HV*)SvRV(obj));
		RETVAL= newRV_noinc((SV*)clone_hv);
		sv_bless(RETVAL, gv_stashpv(sv_reftype(obj, 1), GV_ADD));
	OUTPUT:
		RETVAL

SV*
space(parent=NULL)
	SV *parent
	INIT:
		m3s_space_t *space;
	CODE:
		Newxz(space, 1, m3s_space_t);
		SPACE_XV(space)[0]= 1;
		SPACE_YV(space)[1]= 1;
		SPACE_ZV(space)[2]= 1;
		RETVAL= m3s_wrap_space(space);
		if (parent) {
			if (!m3s_get_magic_space(parent, 0))
				croak("Invalid parent, must be instance of Math::3Space");
			hv_store((HV*)SvRV(RETVAL), "parent", 6, newSVsv(parent), 0);
		}
	OUTPUT:
		RETVAL

SV*
xv(space, x_or_vec=NULL, y=NULL, z=NULL)
	m3s_space_t *space
	SV *x_or_vec
	SV *y
	SV *z
	ALIAS:
		Math::3Space::yv = 1
		Math::3Space::zv = 2
		Math::3Space::origin = 3
	INIT:
		NV *vec= space->mat + ix * 3;
		AV *vec_av;
	PPCODE:
		if (x_or_vec) {
			if (y) {
				vec[0]= SvNV(x_or_vec);
				vec[1]= SvNV(y);
				vec[2]= z? SvNV(z) : 0;
			} else {
				m3s_read_vector_from_sv(vec, x_or_vec);
			}
			// leave $self on stack as return value
		} else {
			ST(0)= sv_2mortal(m3s_wrap_vector(vec));
		}
		XSRETURN(1);

SV*
move(space, x_or_vec, y=NULL, z=NULL)
	m3s_space_t *space
	SV *x_or_vec
	SV *y
	SV *z
	ALIAS:
		Math::3Space::move_rel = 1
	INIT:
		NV vec[3], *matp;
	PPCODE:
		if (y) {
			vec[0]= SvNV(x_or_vec);
			vec[1]= SvNV(y);
			vec[2]= z? SvNV(z) : 0;
		} else {
			m3s_read_vector_from_sv(vec, x_or_vec);
		}
		if (ix == 0) {
			matp= SPACE_ORIGIN(space);
			*matp++ += vec[0];
			*matp++ += vec[1];
			*matp++ += vec[2];
		} else {
			matp= space->mat;
			matp[9] += vec[0] * matp[0] + vec[1] * matp[3] + vec[2] * matp[6];
			++matp;
			matp[9] += vec[0] * matp[0] + vec[1] * matp[3] + vec[2] * matp[6];
			++matp;
			matp[9] += vec[0] * matp[0] + vec[1] * matp[3] + vec[2] * matp[6];
		}
		XSRETURN(1);

SV*
scale(space, xscale_or_vec, yscale=NULL, zscale=NULL)
	m3s_space_t *space
	SV *xscale_or_vec
	SV *yscale
	SV *zscale
	ALIAS:
		math::3Space::set_scale = 1
	INIT:
		NV vec[3], s, m, *matp= SPACE_XV(space);
		size_t i;
	PPCODE:
		if (SvROK(xscale_or_vec) && yscale == NULL) {
			m3s_read_vector_from_sv(vec, xscale_or_vec);
		} else {
			vec[0]= SvNV(xscale_or_vec);
			vec[1]= yscale? SvNV(yscale) : vec[0];
			vec[2]= zscale? SvNV(zscale) : vec[0];
		}
		for (i= 0; i < 3; i++) {
			s= vec[i];
			if (ix == 1) {
				m= sqrt(matp[0]*matp[0] + matp[1]*matp[1] + matp[2]*matp[2]);
				if (m > 0)
					s /= m;
				else
					warn("can't scale magnitude=0 vector");
			}
			*matp++ *= s;
			*matp++ *= s;
			*matp++ *= s;
		}
		XSRETURN(1);

SV*
rotate(space, angle, x_or_vec, y=NULL, z=NULL)
	m3s_space_t *space
	NV angle
	SV *x_or_vec
	SV *y
	SV *z
	INIT:
		NV s= sin(angle * 2 * M_PI), c= cos(angle * 2 * M_PI);
		m3s_space_t tmp_sp;
		NV *rmat= tmp_sp.mat, mag, scale, *axis, tmp1, tmp2;
		int i;
	PPCODE:
		if (y) {
			if (!z) croak("Missing z coordinate in space->(angle, x, y, z)");
			rmat[0]= SvNV(x_or_vec);
			rmat[1]= SvNV(y);
			rmat[2]= SvNV(z);
		} else {
			m3s_read_vector_from_sv(rmat, x_or_vec);
		}
		// construct rotation matrix from vector and angle
		mag= sqrt(rmat[0]*rmat[0] + rmat[1]*rmat[1] + rmat[2]*rmat[2]);
		if (mag == 0)
			croak("Can't rotate around vector with 0 magnitude");
		scale= 1/mag;
		rmat[0] *= scale;
		rmat[1] *= scale;
		rmat[2] *= scale;
		// set y vector to any vector not colinear with x vector
		rmat[3]= 1;
		rmat[4]= 0;
		rmat[5]= 0;
		// z = normalize( x cross y )
		m3s_vector_cross(rmat+6, rmat+0, rmat+3);
		mag= rmat[6]*rmat[6] + rmat[7]*rmat[7] + rmat[8]*rmat[8];
		if (mag < 1e-50) {
			// try again with a different vector
			rmat[3]= 0;
			rmat[4]= 1;
			m3s_vector_cross(rmat+6, rmat+0, rmat+3);
			mag= rmat[6]*rmat[6] + rmat[7]*rmat[7] + rmat[8]*rmat[8];
			if (mag == 0)
				croak("BUG: failed to find perpendicular vector");
		}
		scale= 1 / sqrt(mag);
		rmat[6] *= scale;
		rmat[7] *= scale;
		rmat[8] *= scale;
		// y = z cross x (and should be normalized already because right angles)
		m3s_vector_cross(rmat+3, rmat+6, rmat+0);
		// Now for each axis vector, project it into this space, rotate it (around X), and project it back out
		for (axis=space->mat + 6; axis >= space->mat; axis-= 3) {
			m3s_space_project_vector(&tmp_sp, axis);
			tmp1= c * axis[1] - s * axis[2];
			tmp2= s * axis[1] + c * axis[2];
			axis[1]= tmp1;
			axis[2]= tmp2;
			m3s_space_unproject_vector(&tmp_sp, axis);
		}
		XSRETURN(1);

SV*
rotate_x(space, angle)
	m3s_space_t *space
	NV angle
	ALIAS:
		Math::3Space::rotate_y = 1
		Math::3Space::rotate_z = 2
		Math::3Space::rotate_xv = 3
		Math::3Space::rotate_yv = 4
		Math::3Space::rotate_zv = 5
	INIT:
		NV *matp, *matp2, tmp1, tmp2, tmpvec1[3], tmpvec2[3];
		size_t ofs1, ofs2;
		NV s= sin(angle * 2 * M_PI), c= cos(angle * 2 * M_PI);
	PPCODE:
		if (ix < 3) { // Rotate around axis of parent
			matp= SPACE_XV(space);
			ofs1= ix == 0? 1 : 0;
			ofs2= ix == 2? 1 : 2;
			tmp1= c * matp[ofs1] - s * matp[ofs2];
			tmp2= s * matp[ofs1] + c * matp[ofs2];
			matp[ofs1]= tmp1;
			matp[ofs2]= tmp2;
			matp += 3;
			tmp1= c * matp[ofs1] - s * matp[ofs2];
			tmp2= s * matp[ofs1] + c * matp[ofs2];
			matp[ofs1]= tmp1;
			matp[ofs2]= tmp2;
			matp += 3;
			tmp1= c * matp[ofs1] - s * matp[ofs2];
			tmp2= s * matp[ofs1] + c * matp[ofs2];
			matp[ofs1]= tmp1;
			matp[ofs2]= tmp2;
		} else {
			matp=  ix == 3? SPACE_YV(space) : SPACE_XV(space);
			matp2= ix == 5? SPACE_YV(space) : SPACE_ZV(space);
			tmpvec1[0]= c * matp[0] - s * matp2[0];
			tmpvec1[1]= c * matp[1] - s * matp2[1];
			tmpvec1[2]= c * matp[2] - s * matp2[2];
			tmpvec2[0]= s * matp[0] + c * matp2[0];
			tmpvec2[1]= s * matp[1] + c * matp2[1];
			tmpvec2[2]= s * matp[2] + c * matp2[2];
			matp[0]= tmpvec1[0];
			matp[1]= tmpvec1[1];
			matp[2]= tmpvec1[2];
			matp2[0]= tmpvec2[0];
			matp2[1]= tmpvec2[1];
			matp2[2]= tmpvec2[2];
		}
		XSRETURN(1);

MODULE = Math::3Space              PACKAGE = Math::3Space::Vector

m3s_vector_p
vec3(vec_or_x, y=NULL, z=NULL)
	SV* vec_or_x
	SV* y
	SV* z
	INIT:
		m3s_vector_t vec;
	CODE:
		if (y) {
			vec[0]= SvNV(vec_or_x);
			vec[1]= SvNV(y);
			vec[2]= z? SvNV(z) : 0;
		} else {
			m3s_read_vector_from_sv(vec, vec_or_x);
		}
		RETVAL = vec;
	OUTPUT:
		RETVAL



SV*
x(vec, newval=NULL)
	m3s_vector_p vec
	SV *newval
	ALIAS:
		Math::3Space::Vector::y = 1
		Math::3Space::Vector::z = 2
	PPCODE:
		if (newval) {
			vec[ix]= SvNV(newval);
		} else {
			ST(0)= sv_2mortal(newSVnv(vec[ix]));
		}
		XSRETURN(1);

void
xyz(vec)
	m3s_vector_p vec
	PPCODE:
		EXTEND(SP, 3);
		PUSHs(sv_2mortal(newSVnv(vec[0])));
		PUSHs(sv_2mortal(newSVnv(vec[1])));
		PUSHs(sv_2mortal(newSVnv(vec[2])));

SV*
magnitude(vec, scale=NULL)
	m3s_vector_p vec
	SV *scale
	INIT:
		NV s, m= sqrt(vec[0]*vec[0] + vec[1]*vec[1] + vec[2]*vec[2]);
	PPCODE:
		if (scale) {
			if (m > 0) {
				s= SvNV(scale) / m;
				vec[0] *= s;
				vec[1] *= s;
				vec[2] *= s;
			} else
				warn("can't scale magnitude=0 vector");
			// return $self
		} else {
			ST(0)= sv_2mortal(newSVnv(m));
		}
		XSRETURN(1);

SV*
set(vec1, vec2_or_x, y=NULL, z=NULL)
	m3s_vector_p vec1
	SV *vec2_or_x
	SV *y
	SV *z
	ALIAS:
		Math::3Space::Vector::add = 1
		Math::3Space::Vector::sub = 2
	INIT:
		NV vec2[3];
	PPCODE:
		if (y || looks_like_number(vec2_or_x)) {
			vec2[0]= SvNV(vec2_or_x);
			vec2[1]= y? SvNV(y) : 0;
			vec2[2]= z? SvNV(z) : 0;
		} else {
			m3s_read_vector_from_sv(vec2, vec2_or_x);
		}
		if (ix == 0) {
			vec1[0]= vec2[0];
			vec1[1]= vec2[1];
			vec1[2]= vec2[2];
		} else if (ix == 1) {
			vec1[0]+= vec2[0];
			vec1[1]+= vec2[1];
			vec1[2]+= vec2[2];
		} else {
			vec1[0]-= vec2[0];
			vec1[1]-= vec2[1];
			vec1[2]-= vec2[2];
		}
		XSRETURN(1);

SV*
scale(vec1, vec2_or_x, y=NULL, z=NULL)
	m3s_vector_p vec1
	SV *vec2_or_x
	SV *y
	SV *z
	INIT:
		NV vec2[3];
	PPCODE:
		// single value should be treated as ($x,$x,$x) inatead of ($x,0,0)
		if (looks_like_number(vec2_or_x)) {
			vec2[0]= SvNV(vec2_or_x);
			vec2[1]= y? SvNV(y) : vec2[0];
			vec2[2]= z? SvNV(z) : y? 1 : vec2[0];
		}
		else {
			m3s_read_vector_from_sv(vec2, vec2_or_x);
		}
		vec1[0]*= vec2[0];
		vec1[1]*= vec2[1];
		vec1[2]*= vec2[2];
		XSRETURN(1);

NV
dot(vec1, vec2_or_x, y=NULL, z=NULL)
	m3s_vector_p vec1
	SV *vec2_or_x
	SV *y
	SV *z
	INIT:
		NV vec2[3];
	CODE:
		if (y) {
			vec2[0]= SvNV(vec2_or_x);
			vec2[1]= SvNV(y);
			vec2[2]= z? SvNV(z) : 0;
		} else {
			m3s_read_vector_from_sv(vec2, vec2_or_x);
		}
		RETVAL= m3s_vector_dotprod(vec1, vec2);
	OUTPUT:
		RETVAL

void
cross(vec1, vec2_or_x, vec3_or_y=NULL, z=NULL)
	m3s_vector_p vec1
	SV *vec2_or_x
	SV *vec3_or_y
	SV *z
	INIT:
		m3s_vector_t vec2, vec3;
	PPCODE:
		if (!vec3_or_y) { // RET = vec1->cross(vec2)
			m3s_read_vector_from_sv(vec2, vec2_or_x);
			m3s_vector_cross(vec3, vec1, vec2);
			ST(0)= sv_2mortal(m3s_wrap_vector(vec3));
		} else if (z || !SvROK(vec2_or_x) || looks_like_number(vec2_or_x)) { // RET = vec1->cross(x,y,z)
			vec2[0]= SvNV(vec2_or_x);
			vec2[1]= SvNV(vec3_or_y);
			vec2[2]= z? SvNV(z) : 0;
			m3s_vector_cross(vec3, vec1, vec2);
			ST(0)= sv_2mortal(m3s_wrap_vector(vec3));
		} else {
			m3s_read_vector_from_sv(vec2, vec2_or_x);
			m3s_read_vector_from_sv(vec3, vec3_or_y);
			m3s_vector_cross(vec1, vec2, vec3);
			// leave $self on stack
		}
		XSRETURN(1);
