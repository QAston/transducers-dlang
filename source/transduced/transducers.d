/++
Module providing transducers - objects encapsulating transformations of putters i.e. map, filter; abstracting from concrete type they operate on.
+/
module transduced.transducers;

import transduced.util;
import transduced.core;
import std.range;
import std.algorithm : move;

// function returning a transducer
// transducer holds the info about what to do with input, but doesn't know the overall putter
// opCall applies the transducer to given putter
// can be shared
/++
Returns a transducer modifying the putter by transforming each input using $(D f) function. 
+/
auto mapper(alias f)() if (isStaticFn!f)
{
    return mapper(StaticFn!(f).init);
}
/// ditto
auto mapper(F)(F f)
{
    // transducers create an object which apply the given job description to given TransduciblePutter
    // the created objs are used privately
    // type specialization cannot be done at runtime, so templates needed
    static struct Mapper
    { // transducer
        private F f;
        this(F f)
        {
            this.f = f;
        }

        auto opCall(Decorated)(auto ref Decorated putter)
        { // putter is a TransduciblePutter to decorate, possibly already decorated
            static struct PutterDecorator
            {
                mixin PutterDecoratorMixin!(Decorated);
                private F f;
                private this(Decorated putter, F f)
                {
                    this.f = f;
                    this.putter = putter;
                }

                void put(T)(auto ref T elem)
                {
                    putter.put(f(elem));
                }
            }

            return PutterDecorator(putter, f);
        }
    }

    return Mapper(f);
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into(mapper!((int x) => -x), output);
    assert(output.data == [-1, -2, -3, -4]);
}

// transducer with early termination
// when transducer stack has isTerminatedEarly flag, TransduciblePutter must not supply more input (using put method)
// buffered transducer can still call put method in flush() to putter input buffered earlier
/++
Returns a transducer modifying the putter by forwarding only first $(D howMany) inputs.
+/
auto taker(size_t howMany)
{
    static struct Taker
    {
        private size_t howMany;
        this(size_t howMany)
        {
            this.howMany = howMany;
        }

        auto opCall(Decorated)(auto ref Decorated putter)
        {
            static struct PutterDecorator
            {
                mixin PutterDecoratorMixin!(Decorated);
                private size_t howMany;
                private this(Decorated putter, size_t howMany)
                {
                    this.putter = putter;
                    this.howMany = howMany;
                }

                void put(T)(auto ref T elem)
                {
                    if (--howMany == howMany.max)
                    {
                        putter.markNotAcceptingInput();
                    }
                    else
                    {
                        putter.put(elem);
                    }
                }
            }

            return PutterDecorator(putter, howMany);
        }
    }

    return Taker(howMany);
}
///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into(taker(2), output);
    assert(output.data == [1, 2]);
}

/++
Returns a transducer modifying the putter by forwarding only inputs satisfying $(D pred).
+/
auto filterer(alias pred)() if (isStaticFn!pred)
{
    return filterer(StaticFn!(pred).init);
}
/// ditto
auto filterer(F)(F pred)
{
    static struct Filterer
    {
        private F f;
        this(F f)
        {
            this.f = f;
        }

        auto opCall(Decorated)(auto ref Decorated putter)
        {
            static struct PutterDecorator
            {
                mixin PutterDecoratorMixin!(Decorated);
                private F f;
                private this(Decorated putter, F f)
                {
                    this.f = f;
                    this.putter = putter;
                }

                void put(T)(auto ref T elem)
                {
                    if (f(elem))
                        putter.put(elem);
                }
            }

            return PutterDecorator(putter, f);
        }
    }

    return Filterer(pred);
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into(filterer!((int x) => x % 2 == 1), output);
    assert(output.data == [1, 3]);
}

/++
Returns a transducer modifying the putter by converting $(D InputRange) inputs to a series of inputs with all $(D InputRange) elements.
+/
//transducer which calls put function more than once
//merges input ranges found in the input
//just a variable - no need for a constructor when there's no state
immutable(Flattener) flattener;
/// ditto
static struct Flattener
{
    auto opCall(Decorated)(auto ref Decorated putter) inout
    {
        static struct PutterDecorator
        {
            mixin PutterDecoratorMixin!(Decorated);
            private this(Decorated putter)
            {
                this.putter = putter;
            }

            void put(R)(auto ref R elem) if (isInputRange!R)
            {
                foreach (e; elem)
                {
                    putter.put(e);
                }
            }
        }

        return PutterDecorator(putter);
    }
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [[1, 2], [3, 4]].into(flattener, output);
    assert(output.data == [1, 2, 3, 4]);
}

/++
Composition of mapper and flattener.
+/
pragma(inline, true)
auto flatMapper(alias f)() if (isStaticFn!f)
{
    return flatMapper(StaticFn!(f).init);
}
/// ditto
pragma(inline, true)
auto flatMapper(F)(F f)
{
    return comp(mapper(f), flattener);
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into(flatMapper!((int x) => [x, x])(), output);
    assert(output.data == [1, 1, 2, 2, 3, 3, 4, 4]);
}

/++
Returns a transducer modifying the putter by buffering all the input and transforming it using given $(D f) function on f $(D flush).

This function allows one to plug input range algorithms into transducers ecosystem.
Note that this transducer buffers all puts input until $(D flush), that results in following sideffects:
    - no puts are done untill flush, so putter is not really continuous
    - internal transducer buffer has to allocate memory for that 

Params:
    f = a function taking an input range, and returning one.
        The function will be executed on flush with a random access range having all input data accumulated. 
        Returned range will be forwarded to the decorated putter.
+/
auto flusher(alias f)() if (isStaticFn!f)
{
    return flusher(StaticFn!(f).init);
}
/// ditto
auto flusher(F)(F f)
{
    static struct Flusher
    {
        private F f;
        private this(F f)
        {
            this.f = f;
        }

        auto opCall(Decorated)(auto ref Decorated putter)
        {
            /*
            static struct PutterDecorator {
                mixin PutterDecoratorMixin!(Decorated);
                private F f;
                this(Decorated putter, F f) {
                    this.f = f;
                    this.putter = putter;
                }
                void put(T) (auto ref T elem) {
                    if (f(elem))
                        putter.put(elem);
                }
            }
            return PutterDecorator(putter, f);
            */
        }
    }

    return Flusher(f);
}

/++
Returns a transducer modifying the putter by wrapping it with the composition of given transducers.
+/
pragma(inline, true)
auto comp(T1, T...)(T1 t1, T args)
{
    return compImpl(t1, args);
}

pragma(inline, true)
auto compImpl(T1, T...)(auto ref T1 t1, auto ref T args)
{
    static if (T.length == 0)
    {
        return t1;
    }
    else static if (T.length == 1)
    {
        return Composer!(T1, T[0])(copyOrMove(t1), copyOrMove(args[0]));
    }
    else
    {
        return compImpl(t1, compImpl(args));
    }
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into(comp(mapper!((int x) => -x), taker(2)), output);
    assert(output.data == [-1, -2]);
}

private struct Composer(T, U)
{
    private T t;
    private U u;
    
    pragma(inline, true) private this(T t, U u)
    {
        static if (isCopyable!T) {
            this.t = t;
        }
        else {
            move(t, this.t);
        }
        static if (isCopyable!U) {
            this.u = u;
        }
        else {
            move(u, this.u);
        }
    }

    static if (!isCopyable!T || !isCopyable!U) {
        @disable this(this);
    }

    auto opCall(Decorated)(auto ref Decorated next)
    {
        return t(u(next));
    }
}

version (unittest)
{
    import std.array;
    import transduced.range;
    import std.range;

    int minus(int i)
    {
        return -i;
    }

    unittest
    {

        int[] ar = new int[](4);
        [1, 2, 3, 4].into(mapper!(minus), ar);
        assert(ar == [-1, -2, -3, -4]);
    }

    unittest
    {
        int[] ar = new int[](4);
        [1, 2, 3, 4].into(taker(2), ar);
        assert(ar == [1, 2, 0, 0]);
    }

    unittest
    {
        int[] ar = new int[](4);

        [1, 2, 3, 4].into(comp(taker(2), mapper!minus), ar);
        assert(ar == [-1, -2, 0, 0]);
    }

    int twice(int i)
    {
        return i * 2;
    }

    unittest
    {

        int[] ar = new int[](4);

        [1, 2, 3, 4].into(comp(taker(2), mapper!minus, mapper!twice), ar);
        assert(ar == [-2, -4, 0, 0]);
    }

    unittest
    {
        auto res = transduceSource!(int)([1, 2, 3, 4], comp(taker(2), mapper!minus, mapper!twice)).array();
        assert(res == [-2, -4]);
    }

    unittest
    {
        auto res = transduceSource!(int)([[1, 2, 3, 4]], flattener).array();
        assert(res == [1, 2, 3, 4]);
    }

    int even(int i)
    {
        return !(i % 2);
    }

    unittest
    {
        auto res = transduceSource!(int)([1, 2, 3, 4], filterer!even()).array();
        assert(res == [2, 4]);
    }

    int[] duplicate(int i)
    {
        return [i, i];
    }

    static struct Dup(T)
    {
        size_t times;
        this(size_t times)
        {
            this.times = times;
        }

        ~this()
        {
            times = 0;
        }

        T[] opCall(T t)
        {
            return repeat(t, times).array();
        }
    }

    unittest
    {
        auto res = transduceSource!(int)([1, 2, 3, 4], flatMapper!duplicate()).array();
        assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
    }

    unittest
    {
        auto dupper = Dup!int(2);
        auto res = transduceSource!(int)([1, 2, 3, 4], flatMapper(dupper)).array();
        assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
    }

    unittest
    {
        auto dupper = Dup!int(2);
        int a = 2;
        auto res = transduceSource!(int)([1, 2, 3, 4], flatMapper((int x) => [a, a])).array();
        assert(res == [2, 2, 2, 2, 2, 2, 2, 2]);
    }
}
