#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <math.h>

struct m3s_space;
typedef struct m3s_space m3s_space_t;

struct m3s_space {
	NV origin[3],
		xv[3],
		yv[3],
		zv[3];
};

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

void m3s_read_vector_from_sv(double vec[3], SV *in) {
	SV **el;
	AV *vec_av;
	size_t i;
	if (SvROK(in) && SvTYPE(SvRV(in)) == SVt_PVAV) {
		vec_av= (AV*) SvRV(in);
		if (av_len(vec_av) != 2)
			croak("Vector arrayref must have 3 elements");
		for (i=0; i < 3; i++) {
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
static SV* m3s_wrap_vector(NV vec_array[3]) {
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
					m3s_read_vector_from_sv(space->xv, *field);
				else
					space->xv[0]= 1;
				if ((field= hv_fetch(attrs, "yv", 2, 0)) && *field && SvOK(*field))
					m3s_read_vector_from_sv(space->yv, *field);
				else
					space->yv[1]= 1;
				if ((field= hv_fetch(attrs, "zv", 2, 0)) && *field && SvOK(*field))
					m3s_read_vector_from_sv(space->zv, *field);
				else
					space->zv[2]= 1;
				if ((field= hv_fetch(attrs, "origin", 6, 0)) && *field && SvOK(*field))
					m3s_read_vector_from_sv(space->origin, *field);
			} else
				croak("Invalid source for _init");
		} else {
			space->xv[0]= 1;
			space->yv[1]= 1;
			space->zv[2]= 1;
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
		space->xv[0]= 1;
		space->yv[1]= 1;
		space->zv[2]= 1;
		RETVAL= m3s_wrap_space(space);
		if (parent) {
			if (!m3s_get_magic_space(parent, 0))
				croak("Invalid parent, must be instance of Math::3Space");
			hv_store((HV*)SvRV(RETVAL), "parent", 6, newSVsv(parent), 0);
		}
	OUTPUT:
		RETVAL

SV*
origin(space, newval=NULL)
	m3s_space_t *space
	SV *newval
	ALIAS:
		Math::3Space::xv = 1
		Math::3Space::yv = 2
		Math::3Space::zv = 3
	INIT:
		NV *vec= ix == 1? space->xv
			: ix == 2? space->yv
			: ix == 3? space->zv
			: space->origin;
		AV *vec_av;
	CODE:
		if (newval)
			m3s_read_vector_from_sv(vec, newval);
		RETVAL= m3s_wrap_vector(vec);
	OUTPUT:
		RETVAL

SV*
move(space, x_or_vec, y_sv=NULL, z_sv=NULL)
	m3s_space_t *space
	SV *x_or_vec
	SV *y_sv
	SV *z_sv
	ALIAS:
		Math::3Space::move_rel = 1
	INIT:
		NV vec[3];
	PPCODE:
		if (y_sv) {
			vec[0]= SvNV(x_or_vec);
			vec[1]= SvNV(y_sv);
			vec[2]= z_sv? SvNV(z_sv) : 0;
		} else {
			m3s_read_vector_from_sv(vec, x_or_vec);
		}
		if (ix == 0) {
			space->origin[0] += vec[0];
			space->origin[1] += vec[1];
			space->origin[2] += vec[2];
		} else {
			space->origin[0] += vec[0] * space->xv[0] + vec[1] * space->yv[0] + vec[2] * space->zv[0];
			space->origin[1] += vec[0] * space->xv[1] + vec[1] * space->yv[1] + vec[2] * space->zv[1];
			space->origin[2] += vec[0] * space->xv[2] + vec[1] * space->yv[2] + vec[2] * space->zv[2];
		}
		XSRETURN(1);

SV*
scale(space, xscale_or_vec, yscale=NULL, zscale=NULL)
	m3s_space_t *space
	SV *xscale_or_vec
	SV *yscale
	SV *zscale
	ALIAS:
		Math::3Space::scale_rel= 1
	INIT:
		NV vec[3];
	PPCODE:
		if (SvROK(xscale_or_vec) && yscale == NULL) {
			m3s_read_vector_from_sv(vec, xscale_or_vec);
		} else {
			vec[0]= SvNV(xscale_or_vec);
			vec[1]= yscale? SvNV(yscale) : vec[0];
			vec[2]= zscale? SvNV(zscale) : vec[0];
		}
		if (ix == 0) {
			space->xv[0] *= vec[0];
			space->xv[1] *= vec[1];
			space->xv[2] *= vec[2];
			space->yv[0] *= vec[0];
			space->yv[1] *= vec[1];
			space->yv[2] *= vec[2];
			space->zv[0] *= vec[0];
			space->zv[1] *= vec[1];
			space->zv[2] *= vec[2];
		} else {
			space->xv[0] *= vec[0];
			space->xv[1] *= vec[0];
			space->xv[2] *= vec[0];
			space->yv[0] *= vec[1];
			space->yv[1] *= vec[1];
			space->yv[2] *= vec[1];
			space->zv[0] *= vec[2];
			space->zv[1] *= vec[2];
			space->zv[2] *= vec[2];
		}
		XSRETURN(1);

/*
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
		NV mat[3][3];
		NV s= sin(angle * M_PI), c= cos(angle * M_PI);
	PPCODE:
		if (ix == 0) { // Rotate around X axis of parent
			space->xv[1]= c * space->xv[1] + s * space->xv[2];
			space->xv[2]= c * space->xv[2] + s * space->xv[1];
			space->yv[1]= 
			space->yv[2]=
			space->zv[1]= 
			space->zv[2]= 
		}
		XSRETURN(1);
*/

MODULE = Math::3Space              PACKAGE = Math::3Space::Vector

SV*
new(new_x, new_y, new_z)
	NV new_x
	NV new_y
	NV new_z
	INIT:
		NV vec[3]= { new_x, new_y, new_z };
	CODE:
		RETVAL= m3s_wrap_vector(vec);
	OUTPUT:
		RETVAL

SV*
x(vector, newval=NULL)
	SV *vector
	SV *newval
	ALIAS:
		Math::3Space::Vector::y = 1
		Math::3Space::Vector::z = 2
	INIT:
		NV *vec= m3s_vector_get_array(vector);
	CODE:
		RETVAL= newSVnv(vec[ix]);
	OUTPUT:
		RETVAL

void
xyz(vector, new_x=NULL, new_y=NULL, new_z=NULL)
	SV *vector
	SV *new_x
	SV *new_y
	SV *new_z
	INIT:
		NV *vec= m3s_vector_get_array(vector);
	PPCODE:
		if (new_x) vec[0]= SvNV(new_x);
		if (new_y) vec[1]= SvNV(new_y);
		if (new_z) vec[2]= SvNV(new_z);
		EXTEND(SP, 3);
		PUSHs(sv_2mortal(newSVnv(vec[0])));
		PUSHs(sv_2mortal(newSVnv(vec[1])));
		PUSHs(sv_2mortal(newSVnv(vec[2])));
