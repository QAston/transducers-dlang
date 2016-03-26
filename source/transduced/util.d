/++
Utility module for implementing transducers.
+/
module transduced.util;
import std.experimental.allocator;
import std.algorithm : move;
import std.traits : Parameters, ReturnType, isCallable;

/++
Returns true if type T is copyable.
+/
enum isCopyable(T) = is(typeof((T a) => { T b = a; }));

/++
Takes ownership from provided lvalue into an rvalue. Then ownership of the rvalue can be transfered freely according to the rules of D language.

For copyable types this is simply returns the value.
For non-copyable types returns result of calling $(D std.algorithm.move), which copies from given $(D src) into an rvalue, and resets $(D src) using init.
+/
pragma(inline, true) auto own(T)(ref T src)
{
    static if (isCopyable!T)
    {
        return src;
    }
    else
    {
        return move(src);
    }
}

version (unittest)
{
    struct S
    {
        int a;
        @disable this(this);
    }

    struct U
    {
        S s;
    }

    static assert(!isCopyable!S);
    static assert(!isCopyable!U);
    static assert(isCopyable!int);
    int requiresForward(S s)
    {
        return s.a;
    }

    int requiresForward(int a)
    {
        return a;
    }
}

unittest
{
    S s;
    s.a = 2;
    assert(requiresForward(own(s)) == 2);
    int a = 3;
    assert(requiresForward(own(a)) == 3);
}

/++
Returns true when given static function can be wrapped using $(D StaticFn)
+/
template isStaticFn(alias f)
{
    enum bool isStaticFn = __traits(isStaticFunction, f);
}

struct MapFnWrapper(alias f)
{
    alias ParameterType = Parameters!f;
    static pragma(inline, true) ReturnType!f opCall(ParameterType arg)
    {
        return f(arg);
    }
}

struct PredFnWrapper(alias pred)
{
    alias ParameterType = Parameters!pred;
    static pragma(inline, true) bool opCall(ParameterType arg)
    {
        return pred(arg);
    }
}

// TODO: implement those
package enum isPutter(T) = true;

package enum isTransducer(T) = true; // TODO tests for work with non-copyable putters

package enum isPutterBuffer(T) = true;

version (unittest)
{
    void testPutterBuffer()
    {
    }
}

/++
A queue like buffer that works in 2 phases: filling element by element using $(D put) and removing element by element using removeFront() until it's empty.

Non-copyable. Owns allocated memory and frees it upon destruction.
+/
package struct PutterBuffer(T, Allocator)
{
    private Allocator _allocator;
    private T[] _array;
    private size_t _begin;
    private size_t _end;

    @disable this(this);

    this(Allocator allocator, size_t initialCap)
    {
        _allocator = allocator;
        _array = _allocator.makeArray(initialCap, T.init);
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

    size_t capacity()
    {
        return _array.length;
    }

    bool reserve(size_t cap)
    {
        assert(cap >= capacity());
        return expandArray(_allocator, _array, cap - capacity());
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

package auto putterBuffer(T)(size_t initialCap = 1)
{
    return PutterBuffer!(T, typeof(theAllocator()))(theAllocator(), initialCap);
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
