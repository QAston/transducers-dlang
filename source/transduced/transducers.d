/++
Module providing transducers - objects encapsulating transformations of putters i.e. map, filter; abstracting from concrete type they operate on.
+/
module transduced.transducers;

import transduced.util;
import transduced.core;
import std.range;
import std.algorithm : move;


// function returning a transducer
// transducer holds the info about what to do with input, but doesn't know the overall job
// opCall applies the transducer to given putter
// can be shared
/++
Returns a transducer modifying the putter by transforming each input using $(D f) function. 
+/
auto mapper(alias f)() if (isStaticFn!f)
{
    return mapper(MapFnWrapper!f.init);
}
/// ditto
auto mapper(F)(F f)
{
    // transducers create an object which apply the given job description to given Putter
    // the created objs are used privately
    // type specialization cannot be done at runtime, so templates needed
    static struct Mapper
    { // transducer
        private F f;
        this(F f)
        {
            this.f = own(f);
        }

        auto opCall(Decorated)(Decorated putter)
        {
            static struct PutterDecorator
            {
                mixin PutterDecoratorMixin!(Decorated);
                alias InputType = Parameters!(f)[0];
                private F f;
                private this(Decorated putter, F f)
                {
                    this.f = own(f);
                    this.putter = own(putter);
                }

                void put(InputType elem)
                {
                    putter.put(f(elem));
                }
            }

            return PutterDecorator(own(putter), own(f));
        }
    }

    return Mapper(own(f));
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into!int(mapper!((int x) => -x), output);
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

        auto opCall(Decorated)(Decorated putter)
        {
            static struct PutterDecorator
            {
                mixin PutterDecoratorMixin!(Decorated);
                private size_t howMany;
                private this(Decorated putter, size_t howMany)
                {
                    this.putter = own(putter);
                    this.howMany = howMany;
                }

                void put(InputType elem)
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

            return PutterDecorator(own(putter), howMany);
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
    [1, 2, 3, 4].into!int(taker(2), output);
    assert(output.data == [1, 2]);
}

/++
Returns a transducer modifying the putter by forwarding only inputs satisfying $(D pred).
+/
auto filterer(alias pred)() if (isStaticFn!pred)
{
    return filterer(PredFnWrapper!pred.init);
}
/// ditto
auto filterer(F)(F pred)
{
    static struct Filterer
    {
        private F f;
        this(F f)
        {
            this.f = own(f);
        }

        auto opCall(Decorated)(Decorated putter)
        {
            static struct PutterDecorator
            {
                mixin PutterDecoratorMixin!(Decorated);
                private F f;
                private this(Decorated putter, F f)
                {
                    this.f = own(f);
                    this.putter = own(putter);
                }

                void put(InputType elem)
                {
                    if (f(elem))
                        putter.put(elem);
                }
            }

            return PutterDecorator(own(putter), own(f));
        }
    }

    return Filterer(own(pred));
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into!int(filterer!((int x) => x % 2 == 1), output);
    assert(output.data == [1, 3]);
}


//transducer which calls put function more than once
static struct Flattener(InputRange)
{
    auto opCall(Decorated)(Decorated putter)
    {
        static struct PutterDecorator
        {
            mixin PutterDecoratorMixin!(Decorated);
            private this(Decorated putter)
            {
                this.putter = own(putter);
            }

            alias InputType = InputRange;

            void put(InputType elem)
            {
                foreach (e; elem)
                {
                    putter.put(e);
                }
            }
        }

        return PutterDecorator(own(putter));
    }
}

/++
Returns a transducer modifying the putter by converting $(D InputRange) inputs to a series of inputs with all $(D InputRange) elements.
+/
Flattener!InputRange flattener(InputRange)()  if (isInputRange!InputRange)
{
    return Flattener!InputRange.init;
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [[1, 2], [3, 4]].into!int(flattener!(int[]), output);
    assert(output.data == [1, 2, 3, 4]);
}

/++
Composition of mapper and flattener.
+/
pragma(inline, true)
auto flatMapper(InputRange, alias f)() if (isStaticFn!f)
{
    return flatMapper!InputRange(MapFnWrapper!(f).init);
}
/// ditto
auto flatMapper(InputRange, F)(F f)
{
    return comp(mapper(own(f)), flattener!InputRange());
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into!int(flatMapper!(int[], (int x) => [x, x])(), output);
    assert(output.data == [1, 1, 2, 2, 3, 3, 4, 4]);
}

/++
Returns a transducer buffering all input until $(D Putter.flush) call.
+/
auto buffer()
{
    static struct Buffer
    {
        auto opCall(Decorated)(Decorated putter)
        {
            static struct PutterDecorator(Buffer) {
                mixin PutterDecoratorMixin!(Decorated);
                private Buffer buffer;
                this(Decorated putter, Buffer buffer) {
                    this.putter = own(putter);
                    this.buffer = own(buffer);
                }

                void put(InputType elem) {
                    buffer.put(elem);
                }

                void flush() {
                    while (!buffer.empty()) {
                        putter.put(buffer.removeFront());
                    }
                }
            }
            return PutterDecorator!(typeof(putterBuffer!(Decorated.InputType)()))
                (own(putter), putterBuffer!(Decorated.InputType)());
        }
    }

    return Buffer.init;
}

unittest {
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    auto range = transduceSink!int(buffer(), output);
    assert(output.data() == []);
    range.put(1);
    range.put(2);
    assert(output.data() == []);
    range.flush();
    assert(output.data() == [1, 2]);
    range.put(3);
    range.put(4);
    assert(output.data() == [1, 2]);
    range.flush();
    assert(output.data() == [1, 2, 3, 4]);
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
auto flusher(F)(F f)
{
    return flusher(MapFnWrapper!(f).init);
}
/// ditto
auto flusher(F)(F factory)
{
    //TODO: implement this
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
        return Composer!(T1, T[0])(own(t1), own(args[0]));
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
    [1, 2, 3, 4].into!int(comp(mapper!((int x) => -x), taker(2)), output);
    assert(output.data == [-1, -2]);
}

private struct Composer(T, U)
{
    private T t;
    private U u;
    
    pragma(inline, true) private this(T t, U u)
    {
        this.t = own(t);
        this.u = own(u);
    }

    auto opCall(Decorated)(Decorated next)
    {
        return t(u(own(next)));
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
        [1, 2, 3, 4].into!int(mapper!(minus), ar);
        assert(ar == [-1, -2, -3, -4]);
    }

    unittest
    {
        int[] ar = new int[](4);
        [1, 2, 3, 4].into!int(taker(2), ar);
        assert(ar == [1, 2, 0, 0]);
    }

    unittest
    {
        int[] ar = new int[](4);

        [1, 2, 3, 4].into!int(comp(taker(2), mapper!minus), ar);
        assert(ar == [-1, -2, 0, 0]);
    }

    int twice(int i)
    {
        return i * 2;
    }

    unittest
    {

        int[] ar = new int[](4);

        [1, 2, 3, 4].into!int(comp(taker(2), mapper!minus, mapper!twice), ar);
        assert(ar == [-2, -4, 0, 0]);
    }

    unittest
    {
        auto res = transduceSource!(int)([1, 2, 3, 4], comp(taker(2), mapper!minus, mapper!twice)).array();
        assert(res == [-2, -4]);
    }

    unittest
    {
        auto res = transduceSource!(int)([[1, 2, 3, 4]], flattener!(int[])).array();
        assert(res == [1, 2, 3, 4]);
    }

    bool even(int i)
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
        auto res = transduceSource!(int)([1, 2, 3, 4], flatMapper!(int[], duplicate)).array();
        assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
    }

    unittest
    {
        auto dupper = Dup!int(2);
        auto res = transduceSource!(int)([1, 2, 3, 4], flatMapper!(int[])(dupper)).array();
        assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
    }

    unittest
    {
        auto dupper = Dup!int(2);
        int a = 2;
        auto res = transduceSource!(int)([1, 2, 3, 4], flatMapper!(int[])((int x) => [a, a])).array();
        assert(res == [2, 2, 2, 2, 2, 2, 2, 2]);
    }
}
