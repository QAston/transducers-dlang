/++
Module providing transducers - objects encapsulating transformations of putters i.e. map, filter; abstracting from concrete type they operate on.
+/
module transduced.transducers;

import transduced.util;
import transduced.core;
import std.range;

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
    return Mapper!F(own(f));
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

// transducers create an object which apply the given job description to given Putter
// the created objs are used privately
// type specialization cannot be done at runtime, so templates needed
private struct Mapper(F)
{ // transducer
    private F f;
    private this(F f)
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

private struct TakeCnt
{
private:
    size_t howMany;
    this(size_t howMany)
    {
        this.howMany = howMany;
    }

    bool opCall(T)(T t)
    {
        return !(--howMany == howMany.max);
    }
}

// transducer with early termination
// when transducer stack has isTerminatedEarly flag, TransduciblePutter must not supply more input (using put method)
// buffered transducer can still call put method in flush() to putter input buffered earlier
/++
Returns a transducer modifying the putter by using only first $(D howMany) inputs.
+/
auto taker(size_t howMany)
{
    return Taker!TakeCnt(TakeCnt(howMany));
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
Returns a transducer modifying the putter by taking inputs while $(D p $(LPAREN)input$(RPAREN) == true) and skipping remaining ones.
+/
auto taker(PRED)(PRED p)
{
    return Taker!PRED(p);
}
///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4, 1, 2].into!int(taker((int x) => x < 4), output);
    assert(output.data == [1, 2, 3]);
}

private struct Taker(F)
{
    private F f;
    private this(F f)
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
                {
                    putter.put(elem);
                }
                else
                {
                    putter.markNotAcceptingInput();
                }
            }
        }

        return PutterDecorator(own(putter), own(f));
    }
}

private struct DropCnt
{
private:
    size_t howMany;
    this(size_t howMany)
    {
        this.howMany = howMany;
    }

    bool opCall(T)(T t)
    {
        return !(--howMany == howMany.max);
    }
}

/++
Returns a transducer modifying the putter by dropping first $(D howMany) inputs.
+/
auto dropper(size_t howMany)
{
    return Dropper!DropCnt(DropCnt(howMany));
}
///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into!int(dropper(1), output);
    assert(output.data == [2, 3, 4]);
}

/++
Returns a transducer modifying the putter by dropping inputs while $(D p $(LPAREN)input$(RPAREN) == true), and using all the rest.
+/
auto dropper(PRED)(PRED p)
{
    return Dropper!PRED(p);
}
///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4, 1, 2].into!int(dropper((int x) => x < 4), output);
    assert(output.data == [4, 1, 2]);
}

private struct Dropper(F)
{
    private F f;
    private this(F f)
    {
        this.f = own(f);
    }

    auto opCall(Decorated)(Decorated putter)
    {
        static struct PutterDecorator
        {
            mixin PutterDecoratorMixin!(Decorated);
            private F f;
            private bool dropped;
            private this(Decorated putter, F f)
            {
                this.f = own(f);
                this.putter = own(putter);
            }

            void put(InputType elem)
            {
                if (dropped)
                {
                    putter.put(elem);
                }
                else if (!f(elem))
                {
                    dropped = true;
                    putter.put(elem);
                }
            }
        }

        return PutterDecorator(own(putter), own(f));
    }
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
    return Filterer!F(own(pred));
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

private struct Filterer(F)
{
    private F f;
    private this(F f)
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

/++
Returns a transducer modifying the putter by converting $(D InputRange) inputs to a series of inputs with all $(D InputRange) elements.
+/
Flattener!InputRange flattener(InputRange)() if (isInputRange!InputRange)
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

//transducer which calls put function more than once
private struct Flattener(InputRange)
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
Composition of mapper and flattener.
+/
pragma(inline, true) auto flatMapper(InputRange, alias f)() if (isStaticFn!f)
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
    return Buffer.init;
}

///
unittest
{
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

private struct Buffer
{
    auto opCall(Decorated)(Decorated putter)
    {
        static struct PutterDecorator(Buffer)
        {
            mixin PutterDecoratorMixin!(Decorated);
            private Buffer buffer;
            private this(Decorated putter, Buffer buffer)
            {
                this.putter = own(putter);
                this.buffer = own(buffer);
            }

            void put(InputType elem)
            {
                buffer.put(elem);
            }

            void flush()
            {
                while (!buffer.empty())
                {
                    putter.put(buffer.removeFront());
                }
            }
        }

        return PutterDecorator!(typeof(putterBuffer!(Decorated.InputType)()))(
            own(putter), putterBuffer!(Decorated.InputType)());
    }
}

/++
Returns a transducer modifying the putter by wrapping it with the composition of given transducers.
+/
pragma(inline, true) auto comp(T1, T...)(T1 t1, T args)
{
    return compImpl(t1, args);
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

pragma(inline, true) auto compImpl(T1, T...)(auto ref T1 t1, auto ref T args)
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

private struct Composer(T, U)
{
    private T t;
    private U u;

    private this(T t, U u)
    {
        this.t = own(t);
        this.u = own(u);
    }

    auto opCall(Decorated)(Decorated next)
    {
        return t(u(own(next)));
    }
}

private struct StrideFilter
{
    private size_t stride;
    private size_t currentIndex;
    private this(size_t stride)
    {
        this.stride = stride;
    }

    bool opCall(T)(T t)
    {
        currentIndex = (currentIndex + 1) % stride;
        return currentIndex == 0;
    }
}

/++
Returns a transducer modifying the putter by using every $(D stride)-th input given. 
+/
auto strider(size_t stride)
{
    return Filterer!StrideFilter(StrideFilter(stride));
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4, 5, 6, 7].into!int(strider(2), output);
    assert(output.data == [2, 4, 6]);
}

/++
Returns a transducer modifying the putter by calling a given function with input for sideffects
+/
auto doer(F)(F f)
{
    return Doer!F(f);
}
///
unittest
{
    import std.array;
    import transduced.range;

    auto sideffectOutput = appender!(int[])();

    auto output = appender!(int[])();
    [1, 2, 3, 4].into!int(doer((int i) => std.range.put(sideffectOutput, i)), output);
    assert(output.data == [1, 2, 3, 4]);
    assert(output.data == sideffectOutput.data);
}

private struct Doer(F)
{
    private F f;
    private this(F f)
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
                f(elem);
                putter.put(elem);
            }
        }

        return PutterDecorator(own(putter), own(f));
    }
}

/++
Returns a transducer modifying the putter by transforming partitions of $(D partitionSize) using $(D f) function.

Params:
f: `auto function(scope InputType[] partitionView)` - don't escape/return $(D partitionView) or its contents, copy or move them out to use outside $(D f)
+/
auto partitionMapper(alias f)(size_t partitionSize) if (isStaticFn!f)
{
    return partitionMapper(MapFnWrapper!f.init, partitionSize);
}
/// ditto
auto partitionMapper(F)(F f, size_t partitionSize)
{
    return PartitionMapper!F(own(f), partitionSize);
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[][])();
    // the partitionView.dup is REQUIRED here because the reference to it is returned from the function
    // you can use any other method to allocate an array to return
    [1, 2, 3, 4, 5, 6, 7].into!(int[])(partitionMapper!((scope int[] partitionView) => partitionView.dup)(3), output);
    assert(output.data == [[1, 2, 3], [4, 5, 6], [7]]);
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4, 5, 6, 7].into!(int)(partitionMapper!((scope int[] partitionView) => partitionView[0])(3), output);
    assert(output.data == [1, 4, 7]);
}

private struct PartitionMapper(F)
{
    private size_t partitionSize;
    private F f;
    private this(F f, size_t partitionSize)
    {
        assert(partitionSize >= 1);
        this.f = own(f);
        this.partitionSize = partitionSize;
    }
    auto opCall(Decorated)(Decorated putter)
    {
        static struct PutterDecorator(Buffer)
        {
            mixin PutterDecoratorMixin!(Decorated);
            alias InputType = ElementType!(Parameters!(f)[0]);
            private Buffer buffer;
            private F f;
            private this(Decorated putter, Buffer buffer, F f)
            {
                this.putter = own(putter);
                this.buffer = own(buffer);
                this.f = own(f);
            }

            void put(InputType elem)
            {
                std.range.put(buffer, elem);
                if (buffer.capacity() == buffer.length())
                {
                    putter.put(f(buffer.data));
                    buffer.clear();
                }
            }

            void flush()
            {
                if (buffer.length() > 0)
                {
                    putter.put(f(buffer.data));
                    buffer.clear();
                }
            }
        }

        alias BufferElementType = ElementType!(Parameters!(f)[0]);
        
        return PutterDecorator!(typeof(putterBuffer!(BufferElementType)()))(
            own(putter), putterBuffer!(BufferElementType)(partitionSize), own(f));
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
        auto res = transduceSource!(int)([1, 2, 3, 4], comp(taker(2),
            mapper!minus, mapper!twice)).array();
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
        auto res = transduceSource!(int)([1, 2, 3, 4], flatMapper!(int[])((int x) => [a,
            a])).array();
        assert(res == [2, 2, 2, 2, 2, 2, 2, 2]);
    }
}
