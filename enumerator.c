/*
 * This file is covered by the Ruby license. See COPYING for more details.
 * 
 * Copyright (C) 2007-2011, Apple Inc. All rights reserved.
 * Copyright (C) 2001-2003 Akinori MUSHA
 */

#include "macruby_internal.h"
#include "id.h"
#include "ruby/node.h"
#include "vm.h"

/*
 * Document-class: Enumerable::Enumerator
 *
 * A class which provides a method `each' to be used as an Enumerable
 * object.
 */
VALUE rb_cEnumerator;
static VALUE sym_each;

VALUE rb_eStopIteration;

struct enumerator {
    VALUE obj;
    SEL   sel;
    VALUE args;
    VALUE fib;
    VALUE dst;
    VALUE no_next;
};

static struct enumerator *
enumerator_ptr(VALUE obj)
{
    struct enumerator *ptr;

    Data_Get_Struct(obj, struct enumerator, ptr);
#if 0
    if (RDATA(obj)->dmark != enumerator_mark) {
	rb_raise(rb_eTypeError,
		 "wrong argument type %s (expected %s)",
		 rb_obj_classname(obj), rb_class2name(rb_cEnumerator));
    }
#endif
    if (!ptr) {
	rb_raise(rb_eArgError, "uninitialized enumerator");
    }
    return ptr;
}

/*
 *  call-seq:
 *    obj.to_enum(method = :each, *args)
 *    obj.enum_for(method = :each, *args)
 *
 *  Returns Enumerable::Enumerator.new(self, method, *args).
 *
 *  e.g.:
 *
 *     str = "xyz"
 *
 *     enum = str.enum_for(:each_byte)
 *     a = enum.map {|b| '%02x' % b } #=> ["78", "79", "7a"]
 *
 *     # protects an array from being modified
 *     a = [1, 2, 3]
 *     some_method(a.to_enum)
 *
 */
static VALUE
obj_to_enum(VALUE obj, SEL sel, int argc, VALUE *argv)
{
    VALUE meth = sym_each;

    if (argc > 0) {
	--argc;
	meth = *argv++;
    }

    ID meth_id = rb_to_id(meth);
    SEL enum_sel = rb_vm_id_to_sel(meth_id, argc);
    return rb_enumeratorize(obj, enum_sel, argc, argv);
}

static VALUE
each_slice_i(VALUE val, VALUE *memo)
{
    VALUE ary = memo[0];
    VALUE v = Qnil;
    long size = (long)memo[1];

    rb_ary_push(ary, val);

    if (RARRAY_LEN(ary) == size) {
	v = rb_yield(ary);
	memo[0] = rb_ary_new2(size);
    }

    return v;
}

/*
 *  call-seq:
 *    e.each_slice(n) {...}
 *    e.each_slice(n)
 *
 *  Iterates the given block for each slice of <n> elements.  If no
 *  block is given, returns an enumerator.
 *
 *  e.g.:
 *      (1..10).each_slice(3) {|a| p a}
 *      # outputs below
 *      [1, 2, 3]
 *      [4, 5, 6]
 *      [7, 8, 9]
 *      [10]
 *
 */
static VALUE
enum_each_slice(VALUE obj, SEL sel, VALUE n)
{
    long size = NUM2LONG(n);
    VALUE args[2], ary;

    if (size <= 0) rb_raise(rb_eArgError, "invalid slice size");
    RETURN_ENUMERATOR(obj, 1, &n);
    args[0] = rb_ary_new2(size);
    args[1] = (VALUE)size;

    rb_objc_block_call(obj, selEach, 0, 0, each_slice_i, (VALUE)args);

    ary = args[0];
    if (RARRAY_LEN(ary) > 0) rb_yield(ary);

    return Qnil;
}

static VALUE
each_cons_i(VALUE val, VALUE *memo)
{
    VALUE ary = memo[0];
    VALUE v = Qnil;
    long size = (long)memo[1];

    if (RARRAY_LEN(ary) == size) {
	rb_ary_shift(ary);
    }
    rb_ary_push(ary, val);
    if (RARRAY_LEN(ary) == size) {
	v = rb_yield(rb_ary_dup(ary));
    }
    return v;
}

/*
 *  call-seq:
 *    each_cons(n) {...}
 *    each_cons(n)
 *
 *  Iterates the given block for each array of consecutive <n>
 *  elements.  If no block is given, returns an enumerator.a
 *
 *  e.g.:
 *      (1..10).each_cons(3) {|a| p a}
 *      # outputs below
 *      [1, 2, 3]
 *      [2, 3, 4]
 *      [3, 4, 5]
 *      [4, 5, 6]
 *      [5, 6, 7]
 *      [6, 7, 8]
 *      [7, 8, 9]
 *      [8, 9, 10]
 *
 */
static VALUE
enum_each_cons(VALUE obj, SEL sel, VALUE n)
{
    long size = NUM2LONG(n);
    VALUE args[2];

    if (size <= 0) rb_raise(rb_eArgError, "invalid size");
    RETURN_ENUMERATOR(obj, 1, &n);
    args[0] = rb_ary_new2(size);
    args[1] = (VALUE)size;

    rb_objc_block_call(obj, selEach, 0, 0, each_cons_i, (VALUE)args);

    return Qnil;
}

static VALUE
enumerator_allocate(VALUE klass, SEL sel)
{
    struct enumerator *ptr;
    return Data_Make_Struct(klass, struct enumerator,
			    NULL, -1, ptr);
}

static VALUE
enumerator_each_i(VALUE v, VALUE enum_obj, int argc, VALUE *argv)
{
    return rb_yield_values2(argc, argv);
}

static VALUE
enumerator_init(VALUE enum_obj, VALUE obj, SEL sel, int argc, VALUE *argv)
{
    struct enumerator *ptr = enumerator_ptr(enum_obj);

    GC_WB(&ptr->obj, obj);
    ptr->sel = sel;
    if (argc > 0) {
	GC_WB(&ptr->args, rb_ary_new4(argc, argv));
    }
    ptr->fib = 0;
    ptr->dst = Qnil;
    ptr->no_next = Qfalse;

    return enum_obj;
}

/*
 *  call-seq:
 *    Enumerable::Enumerator.new(obj, method = :each, *args)
 *
 *  Creates a new Enumerable::Enumerator object, which is to be
 *  used as an Enumerable object using the given object's given
 *  method with the given arguments.
 *
 *  Use of this method is not discouraged.  Use Kernel#enum_for()
 *  instead.
 */
static VALUE
enumerator_initialize(VALUE obj, SEL sel, int argc, VALUE *argv)
{
    VALUE recv, meth = sym_each;

    if (argc == 0)
	rb_raise(rb_eArgError, "wrong number of argument (0 for 1)");
    recv = *argv++;
    if (--argc) {
	meth = *argv++;
	--argc;
    }
    ID meth_id = rb_to_id(meth);
    SEL meth_sel = rb_vm_id_to_sel(meth_id, argc);
    return enumerator_init(obj, recv, meth_sel, argc, argv);
}

/* :nodoc: */
static VALUE
enumerator_init_copy(VALUE obj, SEL sel, VALUE orig)
{
    struct enumerator *ptr0, *ptr1;

    ptr0 = enumerator_ptr(orig);
    if (ptr0->fib) {
	/* Fibers cannot be copied */
	rb_raise(rb_eTypeError, "can't copy execution context");
    }
    ptr1 = enumerator_ptr(obj);

    GC_WB(&ptr1->obj, ptr0->obj);
    ptr1->sel = ptr0->sel;
    if (ptr0->args != 0) {
	GC_WB(&ptr1->args, ptr0->args);
    }
    ptr1->fib  = 0;

    return obj;
}

VALUE
rb_enumeratorize(VALUE obj, SEL sel, int argc, VALUE *argv)
{
    return enumerator_init(enumerator_allocate(rb_cEnumerator, 0), obj, sel,
	    argc, argv);
}

static VALUE
enumerator_block_call(VALUE obj, VALUE (*func)(ANYARGS), VALUE arg)
{
    struct enumerator *e;
    int argc = 0;
    const VALUE *argv = 0;

    e = enumerator_ptr(obj);
    if (e->args != 0) {
	argc = RARRAY_LEN(e->args);
	argv = RARRAY_PTR(e->args);
    }
    return rb_objc_block_call(e->obj, e->sel, argc, (VALUE *)argv,
	    func, arg);
}

/*
 *  call-seq:
 *    enum.each {...}
 *
 *  Iterates the given block using the object and the method specified
 *  in the first place.  If no block is given, returns self.
 *
 */
static VALUE
enumerator_each(VALUE obj, SEL sel)
{
    if (!rb_block_given_p()) {
	return obj;
    }
    return enumerator_block_call(obj, enumerator_each_i, obj);
}

static VALUE
enumerator_with_index_i(VALUE val, VALUE m, int argc, VALUE *argv)
{
    VALUE idx;
    VALUE *memo = (VALUE *)m;

    idx = INT2FIX(*memo);
    ++*memo;

    if (argc <= 1)
	return rb_yield_values(2, val, idx);

    return rb_yield_values(2, rb_ary_new4(argc, argv), idx);
}

/*
 *  call-seq:
 *    e.with_index(offset = 0) {|(*args), idx| ... }
 *    e.with_index
 *
 *  Iterates the given block for each elements with an index, which
 *  starts from +offset+.  If no block is given, returns an enumerator.
 *
 */
static VALUE
enumerator_with_index(VALUE obj, SEL sel, int argc, VALUE *argv)
{
    VALUE memo;

    rb_scan_args(argc, argv, "01", &memo);
    RETURN_ENUMERATOR(obj, argc, argv);
    memo = NIL_P(memo) ? 0 : (VALUE)NUM2LONG(memo);
    return enumerator_block_call(obj, enumerator_with_index_i, (VALUE)&memo);
}

/*
 *  call-seq:
 *    e.each_with_index {|(*args), idx| ... }
 *    e.each_with_index
 *
 *  Same as Enumeartor#with_index, except each_with_index does not
 *  receive an offset argument.
 *
 */
static VALUE
enumerator_each_with_index(VALUE obj, SEL sel)
{
    return enumerator_with_index(obj, sel, 0, NULL);
}

static VALUE
enumerator_with_object_i(VALUE val, VALUE memo, int argc, VALUE *argv)
{
    if (argc <= 1) {
	return rb_yield_values(2, val, memo);
    }

    return rb_yield_values(2, rb_ary_new4(argc, argv), memo);
}

/*
 *  call-seq:
 *    e.with_object(obj) {|(*args), memo_obj| ... }
 *    e.with_object(obj)
 *
 *  Iterates the given block for each element with an arbitrary
 *  object given, and returns the initially given object.
 *
 *  If no block is given, returns an enumerator.
 *
 */
static VALUE
enumerator_with_object(VALUE obj, SEL sel, VALUE memo)
{
    RETURN_ENUMERATOR(obj, 1, &memo);
    enumerator_block_call(obj, enumerator_with_object_i, memo);
    return memo;
}

#if 0
static VALUE
next_ii(VALUE i, VALUE obj, int argc, VALUE *argv)
{
    rb_fiber_yield(argc, argv);
    return Qnil;
}

static VALUE
next_i(VALUE curr, VALUE obj)
{
    struct enumerator *e = enumerator_ptr(obj);
    VALUE rnil = Qnil;

    rb_block_call(obj, rb_intern("each"), 0, 0, next_ii, obj);
    e->no_next = Qtrue;
    return rb_fiber_yield(1, &rnil);
}

static void
next_init(VALUE obj, struct enumerator *e)
{
    VALUE curr = rb_fiber_current();
    e->dst = curr;
    e->fib = rb_fiber_new(next_i, obj);
}
#endif

/*
 * call-seq:
 *   e.next   => object
 *
 * Returns the next object in the enumerator, and move the internal
 * position forward.  When the position reached at the end, internal
 * position is rewinded then StopIteration is raised.
 *
 * Note that enumeration sequence by next method does not affect other
 * non-external enumeration methods, unless underlying iteration
 * methods itself has side-effect, e.g. IO#each_line.
 *
 */

static VALUE
enumerator_next(VALUE obj, SEL sel)
{
    // TODO
#if 0
    struct enumerator *e = enumerator_ptr(obj);
    VALUE curr, v;
    curr = rb_fiber_current();

    if (!e->fib || !rb_fiber_alive_p(e->fib)) {
	next_init(obj, e);
    }

    v = rb_fiber_resume(e->fib, 1, &curr);
    if (e->no_next) {
	e->fib = 0;
	e->dst = Qnil;
	e->no_next = Qfalse;
	rb_raise(rb_eStopIteration, "iteration reached at end");
    }
    return v;
#endif
    return Qnil;
}

/*
 * call-seq:
 *   e.rewind   => e
 *
 * Rewinds the enumeration sequence by the next method.
 */

static VALUE
enumerator_rewind(VALUE obj, SEL sel)
{
    struct enumerator *e = enumerator_ptr(obj);

    e->fib = 0;
    e->dst = Qnil;
    e->no_next = Qfalse;
    return obj;
}

void
Init_Enumerator(void)
{
    rb_objc_define_method(rb_mKernel, "to_enum", obj_to_enum, -1);
    rb_objc_define_method(rb_mKernel, "enum_for", obj_to_enum, -1);

    rb_objc_define_method(rb_mEnumerable, "each_slice", enum_each_slice, 1);
    rb_objc_define_method(rb_mEnumerable, "each_cons", enum_each_cons, 1);

    rb_cEnumerator = rb_define_class("Enumerator", rb_cObject);
    rb_include_module(rb_cEnumerator, rb_mEnumerable);

    rb_objc_define_method(*(VALUE *)rb_cEnumerator, "alloc", enumerator_allocate, 0);
    rb_objc_define_method(rb_cEnumerator, "initialize", enumerator_initialize, -1);
    rb_objc_define_method(rb_cEnumerator, "initialize_copy", enumerator_init_copy, 1);
    rb_objc_define_method(rb_cEnumerator, "each", enumerator_each, 0);
    rb_objc_define_method(rb_cEnumerator, "each_with_index", enumerator_each_with_index, 0);
    rb_objc_define_method(rb_cEnumerator, "each_with_object", enumerator_with_object, 1);
    rb_objc_define_method(rb_cEnumerator, "with_index", enumerator_with_index, -1);
    rb_objc_define_method(rb_cEnumerator, "with_object", enumerator_with_object, 1);
    rb_objc_define_method(rb_cEnumerator, "next", enumerator_next, 0);
    rb_objc_define_method(rb_cEnumerator, "rewind", enumerator_rewind, 0);

    rb_eStopIteration   = rb_define_class("StopIteration", rb_eIndexError);

    sym_each	 	= ID2SYM(rb_intern("each"));
}
