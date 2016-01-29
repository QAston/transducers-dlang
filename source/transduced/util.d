/++
Utility module for implementing transducers.
+/
module transduced.util;
import std.experimental.allocator;

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

/++
A queue like buffer that's first filled up with put, then depopulated using removeFront() until it's empty.
Keeps memory allocated until desctruction
Should take param how large initial allocation should be.
+/
struct PutterBuffer (T, Allocator)
{
    private Allocator _allocator;
    private T[] _array;
    private size_t _begin;
    private size_t _end;

    @disable this(this);

    this(Allocator allocator) {
        _allocator = allocator;
        _array = _allocator.makeArray(1, T.init);
    }

    void put(T t) {
        assert(_begin == 0); // only allow insertion if nothing removed from the buffer
        assert(_end <= _array.length);
        
        if(_end == _array.length) {
            bool expanded = expandArray(_allocator, _array, 1);
            assert(expanded);
        }
        _array[_end] = t;
        ++_end;
    }

    T removeFront() {
        assert(!empty());

        T t = _array[_begin];
        
        static if (hasElaborateDestructor!(typeof(_array[0]))) {
            destroy(_array[_begin]);
        }
        _begin++;

        if (_begin == _end) {
            _begin = _end = 0;
        }

        return t;
    }

    size_t length() {
        assert(_end >= _begin);
        return _end - _begin;
    }
    
    bool empty() @property {
        return _begin == _end;
    }

    void clear() {
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

    T[] data() @property {
        return _array[_begin .. _end];
    }
    ~this() {
        if(_array !is null) {
            _allocator.dispose(_array);
            _array = null;
        }
    }
}

auto refCountedPutterBuffer(T)() {
    import std.typecons;
    import std.algorithm;
    
    return RefCounted!(PutterBuffer!(T, typeof(theAllocator())), RefCountedAutoInitialize.no)(theAllocator());
}


unittest {
    import std.range;
    static assert (isOutputRange!(PutterBuffer!(int, typeof(theAllocator())), int));

    auto a = refCountedPutterBuffer!int();
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