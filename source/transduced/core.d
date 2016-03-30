/++
Module introducing core concepts of the library.
+/
module transduced.core;

import std.range;
import std.array;
import transduced.util;
import std.traits : hasMember;

/++
An extended output range is a $(D std.range.OutputRange) with 2 additional capabilities: early termination using $(D O.isAcceptingInput()) and buffering using $(D O.flush()) which flushes the range buffer.

All extended output ranges are also regular output ranges.
All $(D Putter)s are also extended output ranges.
+/
enum isExtendedOutputRange(O, ElementType) = isOutputRange!(O,ElementType) && is(typeof((inout int = 0)
                                                                                       {
                                                                                           O o = O.init;
                                                                                           bool a = o.isAcceptingInput();
                                                                                           o.flush();
                                                                                       }));

///
unittest {
    static assert (isExtendedOutputRange!(Putter!(int, int[]), int));
}

private template baseInputType(P)
{
    static if (hasMember!(P, "decorated")) {
        alias baseInputType = baseInputType!(typeof(P.decorated));
    }
    else {
        alias baseInputType = P.InputType;
    }
}


/++
Is true when P is a type providing $(D transduced.core.Putter) methods.

All DecoratedPutters must pass this check too.
Every putter is also $(D isExtendedOutputRange).
+/
enum isPutter(P) = isExtendedOutputRange!(P,P.InputType) && is(typeof((inout int = 0)
                                                                      {
                                                                          P p = P.init;
                                                                          p.markNotAcceptingInput();
                                                                          std.range.put(p.to(), (baseInputType!P).init);
                                                                      }));

///
unittest {
    static assert (isPutter!(Putter!(int, int[])));
}
/++
Is true when $(D T) is a transducer type capable of producing output of type $(D OutputType). Transducers are factory objects which take a $(D Putter) objects to decorate and return those object wrapped in a PutterDecorator object.
+/
enum isTransducer(T, OutputType) = is(typeof((inout int = 0)
                                 {
                                     auto decorated = T.init(Putter!(OutputType, void delegate(OutputType)).init);
                                     static assert(isPutter!(typeof(decorated)));
                                 }));

///
unittest{
    // a dummy transducer object
    struct Tducer{
        auto opCall(Decorated)(Decorated putter) if (isPutter!Decorated) {
            struct PutterDecorator {
                mixin PutterDecoratorMixin!(Decorated);
                void put(InputType p) {
                    std.range.put(putter, p);
                }
            }
            return PutterDecorator.init;
        }
    }
    static assert (isTransducer!(Tducer, int));
}


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
public struct Putter(ElementType, OutputRange) if (isOutputRange!(OutputRange, ElementType))
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
    Returns false if isExtendedOutputRange(OutputRange) and wrapped output range doesn't accept input anymore.
    +/
    bool isAcceptingInput()
    {
        static if (isExtendedOutputRange!(OutputRange, InputType)) {
            if (!_to.isAcceptingInput())
                return false;
        }
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
    Flushes any input buffered so far by PutterDecorators using $(D Putter.put).

    Called when finished $(D Putter.put)ting.
    If the wrapped OutputRange is an extended OutputRange, forward call to flush of that range.
    +/
    void flush()
    {
        static if (isExtendedOutputRange!(OutputRange, InputType)) {
            _to.flush();
        }
    }

    /++
    Returns the output range that's being $(D std.range.put) input into by this $(D Putter).
    +/
    ref OutputRange to() @property
    {
        return _to;
    }
}
