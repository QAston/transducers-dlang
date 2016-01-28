/++
Module providing transducible contexts.

A transducible context is a function or an object which uses decorated sequential process.
+/
module transduced.contexts;

import std.range;
import std.array;
import std.container.array;
import transduced.util;
import transduced.core;

/++
Returns a lazy range of $(D ElementType) items, each item is taken from given $(D range) and lazily processed by provided transducer $(D t)

Range element type must be given and cannot be deduced from transducers because transducers are independent of what they decorate, range in this case.
+/
template transducerRange(ElementType)
{
    auto transducerRange(R, Transducer)(R range, Transducer t, size_t initialBufferSize = 1) if (
            isInputRange!R)
    {
        auto process = t(RangeProcess!(ElementType)(initialBufferSize));
        return TransducibleProcessRange!(R, typeof(process), ElementType)(range,
            process);
    }
}

///
unittest
{
    import std.array;
    import transduced.transducers;
    auto transducer = comp(taker(2), mapper!minus, mapper!twice);

    auto res = transducerRange!(int)([1, 2, 3, 4], transducer).array();
    assert(!res.empty);
    assert(res.front == -2);
    res.popFront();
    assert(!res.empty);
    assert(res.front == -4);
    res.popFront();
    assert(res.empty);
}

private struct RangeProcess(ElementType)
{
    mixin ProcessMixin!();
    private Array!ElementType _buffer;
    this(size_t initialBufferSize = 1)
    {
        this._buffer.reserve(initialBufferSize);
    }

    void step(ElementType elem)
    {
        this._buffer.insertBack(elem);
    }
}

private struct TransducibleProcessRange(Range, Process, ElementType) if (isInputRange!Range)
{
    import std.traits : Unqual;

    alias R = Unqual!Range;
    R _input;
    Process _process;
    size_t _currentIndex;

    private ref Array!ElementType buffer() @property
    {
        return _process.decoratedProcess()._buffer;
    }

    private bool isBufferEmpty()
    {
        return _currentIndex == size_t.max;
    }

    private void popBuffer()
    {
        _currentIndex++;
        if (_currentIndex >= buffer.length)
        {
            _currentIndex = size_t.max; // mark as empty
            buffer.clear();
            nextBufferValue();
        }
    }

    private void nextBufferValue()
    {
        assert(isBufferEmpty());
        assert(buffer.length == 0);

        while (!_input.empty() && !_process.isTerminatedEarly())
        {
            _process.step(_input.front());
            _input.popFront();
            if (_input.empty() || _process.isTerminatedEarly())
            {
                // last step call
                _process.flush();
            }
            if (buffer.length > 0)
            {
                _currentIndex = 0; // buffer filled, start returning elements from the beginning
                break;
            }
        }
    }

    this(R r, Process process)
    {
        _process = process;
        _input = r;
        _currentIndex = size_t.max;
        nextBufferValue();
    }

    @property bool empty()
    {
        return isBufferEmpty();
    }

    void popFront()
    {
        popBuffer();
    }

    @property auto front()
    {
        return buffer[_currentIndex];
    }
}

/++
Populates output range $(D to) with contents of input range $(D from) processed by a transducer $(D t).
+/
auto into(R, Transducer, Out)(R from, auto ref Transducer t, Out to) if (isInputRange!R) // can't check for output range because output from transducer is unknown && isOutputRange!(Out, ElementType!Out)
{
    auto transducerStack = t(IntoProcess!(Out)(to));
    foreach (el; from)
    {
        transducerStack.step(el);
        if (transducerStack.isTerminatedEarly())
            break;
    }
    transducerStack.flush();
    return transducerStack.decoratedProcess().accumulator;
}

///
unittest
{
    import std.array;
    import transduced.transducers;
    auto transducer = comp(taker(2), mapper!minus, mapper!twice);
    auto output = appender!(int[])();

    [1, 2, 3, 4].into(transducer, output);
    assert(output.data == [-2, -4]);
}

private struct IntoProcess(Out)
{
    private Out accumulator;
    this(Out accumulator)
    {
        this.accumulator = accumulator;
    }

    mixin ProcessMixin!();
    void step(InputType)(InputType elem)
    {
        put(accumulator, elem);
    }
}

public struct TransducedSink(Process) {
    private Process _process;

    this(Process process) {
        _process = process;
    }

    public bool acceptsMore() @property {
        return !_process.isTerminatedEarly();
    }

    public void put(InputType)(InputType input) {
        if (!_process.isTerminatedEarly())
            _process.step(input);
    }

    public void flush() {
        _process.flush();
    }

    ~this() {
        flush();
    }
}

// transduceSink, transduceTo, transduceOutput, transduceOutputRange?
/++
Returns an output range of type TransducedSink which forwards input transformed by transducer $(D t) to output range $(D o).
+/
auto transduceSink(Transducer, OutputRange)(Transducer t, OutputRange o) {
    auto process = t(IntoProcess!(OutputRange)(o));
    return TransducedSink!(typeof(process))(process);
}

///
unittest
{
    import std.array;
    import transduced.transducers;

    auto output = appender!(int[])();
    auto transducedOutput = transduceSink(mapper!((int x) => -x), output);
    put(transducedOutput, 1);
    assert(output.data == [-1]);
    put(transducedOutput, 2);
    assert(output.data == [-1, -2]);
    put(transducedOutput, 3);
    assert(output.data == [-1, -2, -3]);
    assert(transducedOutput.acceptsMore());
}

///
unittest
{
    import std.array;
    import transduced.transducers;

    auto output = appender!(int[])();
    auto transducedOutput = transduceSink(taker(2), output);
    put(transducedOutput, 1);
    assert(transducedOutput.acceptsMore());
    assert(output.data == [1]);
    put(transducedOutput, 2);
    assert(output.data == [1, 2]);
    put(transducedOutput, 3);
    assert(output.data == [1, 2]);
    assert(!transducedOutput.acceptsMore());
}
