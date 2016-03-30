/++
Module providing functions for working with ranges.
+/
module transduced.range;

import std.range;
import std.array;
import std.container.array;
import std.typecons;
import transduced.util;
import transduced.core;

/++
Returns a lazy range of $(D OutElementType) items, each item is taken from given $(D inputRange) and lazily transformed by provided transducer $(D t)

Range element type must be given and cannot be deduced from transducers because transducers are independent of what they decorate, range in this case.
+/
auto transduceSource(OutElementType, R, Transducer)(R inputRange, Transducer t) if (isInputRange!R && isTransducer!(Transducer, OutElementType))
{
    alias bufferType = typeof(putterBuffer!OutElementType());
    alias putterType = typeof(t(Putter!(OutElementType,
        bufferType)(putterBuffer!OutElementType())));
    return TransducedSource!(R, putterType, OutElementType)(inputRange,
        t(Putter!(OutElementType, bufferType)(putterBuffer!OutElementType())));
}

///
unittest
{
    import transduced.transducers;

    auto res = transduceSource!(int)([1, 2, 3, 4], comp(taker(2), mapper!minus, mapper!twice));
    assert(!res.empty);
    assert(res.front == -2);
    res.popFront();
    assert(!res.empty);
    assert(res.front == -4);
    res.popFront();
    assert(res.empty);
    foreach (int i; res)
    {
    }
}

private struct TransducedSource(Range, Putter, ElementType) if (isInputRange!Range)
{
    import std.traits : Unqual;

    alias R = Unqual!Range;
    R _input;
    Putter _putter;

    private ref auto buffer() @property
    {
        return _putter.to();
    }

    private void nextBufferValue()
    {
        assert(buffer.empty());

        while (!_input.empty() && _putter.isAcceptingInput())
        {
            _putter.put(_input.front());
            _input.popFront();
            if (_input.empty() || !_putter.isAcceptingInput())
            {
                // last step call
                _putter.flush();
            }
            if (!buffer.empty())
                break;
        }
    }

    this(R r, Putter putter)
    {
        _putter = own(putter);
        _input = r;
        nextBufferValue();
    }

    @property bool empty()
    {
        return buffer.empty();
    }

    void popFront()
    {
        buffer.removeFront();
        if (buffer.empty())
            nextBufferValue();
    }

    @property auto front()
    {
        return buffer.data[0];
    }

    // make range usable with foreach:
    int opApply(scope int delegate(ElementType) dg)
    {
        while (!empty())
        {
            int res = dg(front());
            if (res != 0)
                return res;
            popFront();
        }
        return 0;
    }

    int opApply(scope int delegate(size_t, ElementType) dg)
    {
        int i = 0;
        while (!empty())
        {
            int res = dg(i, front());
            if (res != 0)
                return res;
            ++i;
            popFront();
        }
        return 0;
    }
}

/++
Populates output range $(D to) with contents of input range $(D from) transformed by transducer $(D t). $(D to) has to take $(D OutElementType) as input.
+/
auto into(OutElementType, R, Transducer, Out)(R from, Transducer t, Out to) if (
        isInputRange!R && isOutputRange!(Out, OutElementType) && isTransducer!(Transducer, OutElementType))
{
    auto transducerStack = t(Putter!(OutElementType, Out)(to));
    foreach (el; from)
    {
        transducerStack.put(el);
        if (!transducerStack.isAcceptingInput())
            break;
    }
    transducerStack.flush();
    return transducerStack.to();
}

///
unittest
{
    import std.array;
    import transduced.transducers;

    auto output = appender!(int[])();

    [1, 2, 3, 4].into!(int)(comp(taker(2), mapper!minus, mapper!twice), output);
    assert(output.data == [-2, -4]);
}

public struct TransducedSink(Putter)
{
    private Putter _putter;

    alias InputType = Putter.InputType;
    this(Putter putter)
    {
        _putter = own(putter);
    }

    public bool isAcceptingInput() @property
    {
        return _putter.isAcceptingInput();
    }

    public void put(InputType input)
    {
        if (_putter.isAcceptingInput())
            _putter.put(input);
    }

    public void flush()
    {
        _putter.flush();
    }
}

/++
Returns an ExtendedOutputRange (see $(D transduced.core.isExtendedOutputRange)) of type $(D TransducedSink) which forwards input transformed by transducer $(D t) to OutputRange $(D o). $(D o) has to take $(D OutElementType) as input.
+/
auto transduceSink(OutElementType, Transducer, OutputRange)(Transducer t, OutputRange o) if (
        isOutputRange!(OutputRange, OutElementType) && isTransducer!(Transducer, OutElementType))
{
    alias putterType = typeof(t(Putter!(OutElementType, OutputRange)(o)));
    return TransducedSink!(putterType)(t(Putter!(OutElementType, OutputRange)(o)));
}

///
unittest
{
    import std.array;
    import transduced.transducers;

    auto output = appender!(int[])();
    auto transducedOutput = transduceSink!int(mapper!((int x) => -x), output);
    static assert(isOutputRange!(typeof(transducedOutput), int));
    static assert(isExtendedOutputRange!(typeof(transducedOutput), int));
    put(transducedOutput, 1);
    assert(output.data == [-1]);
    put(transducedOutput, 2);
    assert(output.data == [-1, -2]);
    put(transducedOutput, 3);
    assert(output.data == [-1, -2, -3]);
    assert(transducedOutput.isAcceptingInput());
}

///
unittest
{
    import std.array;
    import transduced.transducers;

    auto output = appender!(int[])();
    auto transducedOutput = transduceSink!int(taker(2), output);
    put(transducedOutput, 1);
    assert(transducedOutput.isAcceptingInput());
    assert(output.data == [1]);
    put(transducedOutput, 2);
    assert(output.data == [1, 2]);
    put(transducedOutput, 3);
    assert(output.data == [1, 2]);
    assert(!transducedOutput.isAcceptingInput());
}
