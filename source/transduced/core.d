/++
Module introducing core concepts of the library.
+/
module transduced.core;

import std.range;
import std.array;
import transduced.util;

//todo: isPutter template

/++
Mixin used to implement common code for all putter decorators.

Specific putter decorators provide additional capabilities to $(D Putter) by wrapping it and forwarding calls to the decorated $(D putter) object.
For more information on how decorators work google "Decorator design pattern".
+/
mixin template PutterDecoratorMixin(Decorated)
{
    private Decorated putter;

    /++
    Forwards to the decorated $(D Putter.isAcceptingInput). Do not override.
    +/
    pragma(inline, true) bool isAcceptingInput()
    {
        return putter.isAcceptingInput();
    }
    /++
    Forwards to the decorated $(D Putter.markNotAcceptingInput). Do not override.
    +/
    pragma(inline, true) void markNotAcceptingInput()
    {
        putter.markNotAcceptingInput();
    }
    /++
	PutterDecorators which do buffering need to override this method. By default forwards to the decorated $(Putter.flush).

	This method should $(D Putter.put) any buffered data into the decorated $(D putter).
	After all processing is done the decorator should forward to the decorated $(D Putter.flush).
	+/
    pragma(inline, true) void flush()
    {
        putter.flush();
    }

    /++
    Forwards to the decorated $(D Putter.to). Do not override.
    +/
    pragma(inline, true) ref auto to() @property
    {
        return putter.to();
    }

    /++
    By default PutterDecorators take same kind of input as the decorated putter.
    In a case when types are different this needs to be overridden.
    +/
    alias InputType = Decorated.InputType;
}

/++
Wraps an output range + put function in a struct providing early termination, buffering, and flushing.
+/
public struct Putter(ElementType, OutputRange)
{
    private OutputRange _to;
    private bool _acceptingInput;
    this(OutputRange to)
    {
        this._acceptingInput = true;
        this._to = own(to);
    }

    /++
    Type taken in $(D put).
    +/

    alias InputType = ElementType;

    /++
    Put the given $(D input) into the $(D Putter.to) output range.
    
    Advances the process represented by an output range by a single step.
    +/
    void put(InputType input)
    {
        std.range.put(_to, input);
    }

    /++
    Returns true when putter is no longer accepting input.

    Code using putters should check this after every step, and if false stop calling $(D Putter.put), call $(D Putter.flush) and finish.
    +/
    bool isAcceptingInput()
    {
        return _acceptingInput;
    }

    /++
    Mark putter to not accept input anymore.

    Use inside $(D PutterDecorator.put) method to signal that this putter won't accept any more external input.
    When marked, no new input can be fed to the process using $(D Putter.put), outside of $(D Putter.flush) method.
    +/
    void markNotAcceptingInput()
    {
        _acceptingInput = false;
    }

    /++
    Flushes any input buffered so far by PutterDecorators using $(Putter.put).

    Called when finished $(D Putter.put)ting.
	+/
    void flush()
    {
    }

    /++
    Returns the output range that's being $(D std.range.put) input into by this $(D Putter).
    +/
    ref OutputRange to() @property
    {
        return _to;
    }
}
