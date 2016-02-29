/++
Utility module for implementing transducers.
+/
module transduced.util;
import std.experimental.allocator;
import std.algorithm : move;

/++
Returns true if type T is copyable.
+/
enum isCopyable (T) = is(typeof((T a) => {T b = a;}));

/++
Prepares lvalues of copyable and non-copyable types for being forwarded to function calls. For copyable types this is a no-op.
For non-copyable types returns result of calling $(D std.algorithm.move), which copies from given $(D src) into an rvalue, and resets $(D src) using init.

Rvalues are forwared in D regardless of copyability.
+/
pragma(inline, true)
auto forwardLvalue(T)(ref T src) {
    static if (isCopyable!T) {
        return src;
    }
    else {
        return move(src);
    }
}

version(unittest){
    struct S {
        int a;
        @disable this(this);
    }
    struct U {
        S s;
    }
    static assert(!isCopyable!S);
    static assert(!isCopyable!U);
    static assert(isCopyable!int);
    int requiresForward(S s) {
        return s.a;
    }
    int requiresForward(int a){
        return a;
    }
}

unittest {
    S s;
    s.a = 2;
    assert(requiresForward(forwardLvalue(s)) == 2);
    int a = 3;
    assert(requiresForward(forwardLvalue(a)) == 3);
}

/++
Returns true when given static function can be wrapped using $(D StaticFn)
+/
template isStaticFn(alias f)
{
    enum bool isStaticFn = __traits(isStaticFunction, f);
}

/++
Wrapper object for static functions, for use as callable objects.

Allows using the same code by delegates/callable objs and static functions, while preserving optimizations for static functions.

Examples:
---
auto mapper(alias f)() if (isStaticFn!f) {
    return mapper(StaticFn!(f).init); // forward to version taking a callable object
}
auto mapper(F)(F f) {
...
}
---
+/
struct StaticFn(alias f)
{
    pragma(inline, true) auto opCall(T...)(auto ref T args) inout
    {
        return f(args);
    }
}
// TODO: implement those
enum isPutter(T) = true;

enum isTransducer(T) = true; // TODO tests for work with non-copyable putters

enum isPutterBuffer(T) = true;

version (unittest)
{
    void testPutterBuffer()
    {
    }
}

/++
A queue like buffer that's first filled up with put, then depopulated using removeFront() until it's empty.
Keeps memory allocated until desctruction
Should take param how large initial allocation should be.
+/
struct PutterBuffer(T, Allocator)
{
    private Allocator _allocator;
    private T[] _array;
    private size_t _begin;
    private size_t _end;

    @disable this(this);

    this(Allocator allocator)
    {
        _allocator = allocator;
        _array = _allocator.makeArray(1, T.init);
    }

    void put(T t)
    {
        assert(_begin == 0); // only allow insertion if nothing removed from the buffer
        assert(_end <= _array.length);

        if (_end == _array.length)
        {
            bool expanded = expandArray(_allocator, _array, 1);
            assert(expanded);
        }
        _array[_end] = t;
        ++_end;
    }

    T removeFront()
    {
        assert(!empty());

        T t = _array[_begin];

        static if (hasElaborateDestructor!(typeof(_array[0])))
        {
            destroy(_array[_begin]);
        }
        _begin++;

        if (_begin == _end)
        {
            _begin = _end = 0;
        }

        return t;
    }

    size_t length()
    {
        assert(_end >= _begin);
        return _end - _begin;
    }

    bool empty() @property
    {
        return _begin == _end;
    }

    void clear()
    {
        static if (hasElaborateDestructor!(typeof(_array[0])))
        {
            foreach (ref e; _array[_begin .. _end])
            {
                destroy(e);
            }
        }
        _begin = 0;
        _end = 0;
    }

    T[] data() @property
    {
        return _array[_begin .. _end];
    }

    ~this()
    {
        if (_array !is null)
        {
            _allocator.dispose(_array);
            _array = null;
        }
    }
}

auto putterBuffer(T)()
{
    return PutterBuffer!(T, typeof(theAllocator()))(theAllocator());
}

unittest
{
    import std.range;

    static assert(isOutputRange!(PutterBuffer!(int, typeof(theAllocator())), int));

    auto a = putterBuffer!int();
    assert(a.empty());
    put(a, 3);
    put(a, 5);
    put(a, 7);
    assert(!a.empty());
    assert(a.length() == 3);
    assert(a.data == [3, 5, 7]);
    assert(a.removeFront() == 3);
    assert(a.removeFront() == 5);
    assert(a.removeFront() == 7);
    assert(a.empty());
    assert(a.length() == 0);
    a.clear();
    assert(a.empty());
    assert(a.length() == 0);
    put(a, 3);
    assert(a.length() == 1);
    assert(!a.empty());
    assert(a.data == [3]);
    a.clear();
    assert(a.empty());
    assert(a.length() == 0);
}
