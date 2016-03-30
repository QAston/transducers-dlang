/++
Module providing transducers - objects encapsulating transformations of putters i.e. map, filter; abstracting from concrete type they operate on.
+/
module transduced.transducers;

import transduced.util;
import transduced.core;
import std.range;

// function returning a transducer
// transducer holds the info about what to do with input, but doesn't know the overall job
// wrap wraps the given Putter in PutterDecorator
/++
Returns a transducer modifying the putter by transforming each input using $(D f) function. 

Only pass static functions to alias variant, passing delegates will result in can't find overload error. Can't guard that reliably, sorry.
+/
auto mapper(alias f)()
{
    return mapper((MapFnWrapper!f).init);
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
    [1, 2, 3, 4].into(mapper!((x) => -x), output);
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

    auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated)
    {
        static struct PutterDecorator
        {
            mixin PutterDecoratorMixin!(Decorated, InType);
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
    alias OutputType(InputType) = typeof(f(InputType.init));
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
// when transducer stack has !isAcceptingInput flag no more input should be supplied to the Putter stack using Putter.put method
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
    [1, 2, 3, 4].into(taker(2), output);
    assert(output.data == [1, 2]);
}

/++
Returns a transducer modifying the putter by taking inputs while $(D p $(LPAREN)input$(RPAREN) == true) and skipping remaining ones.

Only pass static functions to alias variant, passing delegates will result in can't find overload error. Can't guard that reliably, sorry.
+/
auto taker(PRED)(PRED p)
{
    return Taker!PRED(p);
}
/// ditto
pragma(inline, true) auto taker(alias pred)()
{
    return taker(PredFnWrapper!pred.init);
}
///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4, 1, 2].into(taker!((x) => x < 4), output);
    assert(output.data == [1, 2, 3]);
}

private struct Taker(F)
{
    private F f;
    private this(F f)
    {
        this.f = own(f);
    }

    auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated)
    {
        static struct PutterDecorator
        {
            mixin PutterDecoratorMixin!(Decorated, InType);
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
    alias OutputType(InputType) = InputType;
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
    [1, 2, 3, 4].into(dropper(1), output);
    assert(output.data == [2, 3, 4]);
}

/++
Returns a transducer modifying the putter by dropping inputs while $(D p $(LPAREN)input$(RPAREN) == true), and using all the rest.

Only pass static functions to alias variant, passing delegates will result in can't find overload error. Can't guard about that reliably, sorry.
+/
auto dropper(PRED)(PRED p)
{
    return Dropper!PRED(p);
}
/// ditto
pragma(inline, true) auto dropper(alias pred)()
{
    return dropper(PredFnWrapper!pred.init);
}
///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4, 1, 2].into(dropper!((x) => x < 4), output);
    assert(output.data == [4, 1, 2]);
}

private struct Dropper(F)
{
    private F f;
    private this(F f)
    {
        this.f = own(f);
    }

    auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated)
    {
        static struct PutterDecorator
        {
            mixin PutterDecoratorMixin!(Decorated, InType);
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
    alias OutputType(InputType) = InputType;
}

/++
Returns a transducer modifying the putter by forwarding only inputs satisfying $(D pred).

Only pass static functions to alias variant, passing delegates will result in can't find overload error. Can't guard that reliably, sorry.
+/
auto filterer(alias pred)()
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
    [1, 2, 3, 4].into(filterer!((x) => x % 2 == 1), output);
    assert(output.data == [1, 3]);
}

private struct Filterer(F)
{
    private F f;
    private this(F f)
    {
        this.f = own(f);
    }

    auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated)
    {
        static struct PutterDecorator
        {
            mixin PutterDecoratorMixin!(Decorated, InType);
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
    alias OutputType(InputType) = InputType;
}

/++
Returns a transducer modifying the putter by converting $(D InputRange) inputs to a series of inputs with all $(D InputRange) elements.
+/
Flattener flattener()
{
    return Flattener.init;
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

//transducer which calls put function more than once
private struct Flattener
{
    auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated)
    {
        static struct PutterDecorator
        {
            mixin PutterDecoratorMixin!(Decorated, InType);
            private this(Decorated putter)
            {
                this.putter = own(putter);
            }

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
    alias OutputType(InputType) = ElementType!(InputType);
    
}

/++
Composition of mapper and flattener.

Only pass static functions to alias variant, passing delegates will result in can't find overload error. Can't guard that reliably, sorry.
+/
pragma(inline, true) auto flatMapper(alias f)()
{
    return flatMapper(MapFnWrapper!(f).init);
}
/// ditto
auto flatMapper(F)(F f)
{
    return comp(mapper(own(f)), flattener());
}
///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4].into(flatMapper!((x) => [x, x])(), output);
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
    auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated)
    {
        static struct PutterDecorator(Buffer)
        {
            mixin PutterDecoratorMixin!(Decorated, InType);
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
    alias OutputType(InputType) = InputType;
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
    [1, 2, 3, 4].into(comp(mapper!((x) => -x), taker(2)), output);
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

    auto wrap(InType, Decorated)(Decorated next)
    {
        return t.wrap!(InType)(u.wrap!(T.OutputType!(InType))(own(next)));
    }

    alias OutputType(InputType) = U.OutputType!(T.OutputType!(InputType));
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
    [1, 2, 3, 4, 5, 6, 7].into(strider(2), output);
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
    [1, 2, 3, 4].into(doer((int i) => std.range.put(sideffectOutput, i)), output);
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

    auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated)
    {
        static struct PutterDecorator
        {
            mixin PutterDecoratorMixin!(Decorated, InType);
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
    alias OutputType(InputType) = InputType;
}

/++
Returns a transducer modifying the putter by transforming chunks of $(D chunkSize) using $(D f) function.

Only pass static functions to alias variant, passing delegates will result in can't find overload error. Can't guard that reliably, sorry.

Params:
f: auto function(scope InputType[] chunkView) - don't escape/return $(D chunkView) or its contents, copy or move them out to use outside $(D f)
+/
auto chunkMapper(alias f)(size_t chunkSize)
{
    return chunkMapper(MapFnWrapper!f.init, chunkSize);
}
/// ditto
auto chunkMapper(F)(F f, size_t chunkSize)
{
    return ChunkMapper!F(own(f), chunkSize);
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[][])();
    // the chunkView.dup is REQUIRED here because the reference to it is returned from the function
    // you can use any other method to allocate an array to return
    [1, 2, 3, 4, 5, 6, 7].into(
        chunkMapper!((scope int[] chunkView) => chunkView.dup)(3), output);
    assert(output.data == [[1, 2, 3], [4, 5, 6], [7]]);
}

///
unittest
{
    import std.array;
    import transduced.range;

    auto output = appender!(int[])();
    [1, 2, 3, 4, 5, 6, 7].into(
        chunkMapper!((scope int[] chunkView) => chunkView[0])(3), output);
    assert(output.data == [1, 4, 7]);
}

private struct ChunkMapper(F)
{
    private size_t chunkSize;
    private F f;
    private this(F f, size_t chunkSize)
    {
        assert(chunkSize >= 1);
        this.f = own(f);
        this.chunkSize = chunkSize;
    }

    auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated)
    {
        static struct PutterDecorator(Buffer)
        {
            mixin PutterDecoratorMixin!(Decorated, InType);
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

        return PutterDecorator!(typeof(putterBuffer!(BufferElementType)()))(own(putter),
            putterBuffer!(BufferElementType)(chunkSize), own(f));
    }
    alias OutputType(InputType) = typeof(f([InputType.init]));
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
        auto res = transduceSource([1, 2, 3, 4], comp(taker(2),
            mapper!minus, mapper!twice)).array();
        assert(res == [-2, -4]);
    }

    unittest
    {
        auto res = transduceSource([[1, 2, 3, 4]], flattener).array();
        assert(res == [1, 2, 3, 4]);
    }

    bool even(int i)
    {
        return !(i % 2);
    }

    unittest
    {
        auto res = transduceSource([1, 2, 3, 4], filterer!even()).array();
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
        auto res = transduceSource([1, 2, 3, 4], flatMapper!(duplicate)).array();
        assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
    }

    unittest
    {
        auto dupper = Dup!int(2);
        auto res = transduceSource([1, 2, 3, 4], flatMapper(dupper)).array();
        assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
    }

    unittest
    {
        auto dupper = Dup!int(2);
        int a = 2;
        auto res = transduceSource([1, 2, 3, 4], flatMapper((int x) => [a,
            a])).array();
        assert(res == [2, 2, 2, 2, 2, 2, 2, 2]);
    }
}
