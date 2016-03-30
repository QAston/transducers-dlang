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
Is true when $(D T) is a transducer type which can process $(D InputType) input.

Transducer is an object with $(D wrap!InputType) method taking a (possibly already $(D Decorated)) $(D Putter) object to decorate and returning a DecoratedPutter ($(D Putter) wrapped in $(PutterDecorator) instance). The returned DecoratedPutter accepts $(D InputType) input.
Transducer also has OutputType(InputType) alias which defines what type will be passed to DecoratedPutter on given input.
+/
enum isTransducer(T, InputType) = is(typeof((inout int = 0)
                                 {
                                     alias OutputType = T.OutputType!(InputType);
                                     auto decorated = T.init.wrap!InputType(Putter!(OutputType, void delegate(OutputType)).init);
                                     static assert(isPutter!(typeof(decorated)));
                                 }));

///
unittest{
    // a dummy transducer object
    struct Tducer{
        auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated) {
            struct PutterDecorator {
                mixin PutterDecoratorMixin!(Decorated, InType);
                this(Decorated putter) {
                    this.putter = putter;
                }
                void put(InputType p) {
                    std.range.put(putter, p);
                }
            }
            return PutterDecorator(putter);
        }
        alias OutputType(InputType) = InputType;
    }
    static assert (isTransducer!(Tducer, int));
}

/++
Mixin used to implement common code for all putter decorators.

Specific putter decorators provide additional capabilities to $(D Putter) by wrapping it and forwarding calls to the $(D Decorated) $(D putter) object.
For more information on how decorators work google "Decorator design pattern".
+/
mixin template PutterDecoratorMixin(Decorated, InType)
{
    private Decorated putter;

    /++
    Forwards to the $(D Decorated) $(D Putter.isAcceptingInput). Do not override.
    +/
    pragma(inline, true) bool isAcceptingInput()
    {
        return putter.isAcceptingInput();
    }
    /++
    Forwards to the $(D Decorated) $(D Putter.markNotAcceptingInput). Do not override.
    +/
    pragma(inline, true) void markNotAcceptingInput()
    {
        putter.markNotAcceptingInput();
    }
    /++
    PutterDecorators which do buffering need to override this method. By default forwards to the $(D Decorated) $(Putter.flush).

    This method should $(D Putter.put) any buffered data into the $(D Decorated) $(D putter).
    After all processing is done the decorator should forward to the $(D Decorated) $(D Putter.flush).
    +/
    pragma(inline, true) void flush()
    {
        putter.flush();
    }

    /++
    Forwards to the $(D Decorated) $(D Putter.to). Do not override.
    +/
    pragma(inline, true) ref auto to() @property
    {
        return putter.to();
    }

    /++
    Type of input taken by $(D Putter.put).
    +/
    alias InputType = InType;
}

/++
Wraps an $(D OutputRange) + $(D std.range.put) function in a struct providing early termination, buffering, and flushing.
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
