/++
Module introducing core concepts of the library.
+/
module transduced.core;

import std.range;
import std.array;
import transduced.util;

/++
An extended output range is a $(D std.range.OutputRange) with 2 additional capabilities: early termination using $(D O.isDone()) and buffering using $(D O.flush()) which flushes the range buffer.

All extended output ranges are also regular output ranges.
All $(D Putter)s are also extended output ranges.
+/
enum isExtendedOutputRange(O, ElementType) = isOutputRange!(O, ElementType)
        && is(typeof((inout int = 0) { O o = O.init; bool a = o.isDone(); o.flush();  }));

///
unittest
{
    static assert(isExtendedOutputRange!(Putter!(int, int[]), int));
}

/++
Is true when P is a type providing $(D transduced.core.Putter) methods.

All DecoratedPutters must pass this check too.
Every putter is also $(D isExtendedOutputRange).
+/
enum isPutter(P) = isExtendedOutputRange!(P, P.InputType) && is(typeof((inout int = 0) {
    P p = P.init;
    std.range.put(p.to(), P.TargetType.init);
}));

///
unittest
{
    static assert(isPutter!(Putter!(int, int[])));
}
/++
Is true when $(D T) is a transducer type which can process $(D InputType) input.

Transducer is an object with $(D wrap!InputType) method taking a (possibly already $(D Decorated)) $(D Putter) object to decorate and returning a DecoratedPutter ($(D Putter) wrapped in $(PutterDecorator) instance). The returned DecoratedPutter accepts $(D InputType) input.
Transducer also has OutputType(InputType) alias which defines what type will be passed to DecoratedPutter on given input.
+/
enum isTransducer(T, InputType) = is(typeof((inout int = 0) {
    alias OutputType = T.OutputType!(InputType);
    auto decorated = T.init.wrap!InputType(Putter!(OutputType, void delegate(OutputType)).init);
    static assert(isPutter!(typeof(decorated)));
}));

///
unittest
{
    // a dummy transducer object
    struct Tducer
    {
        auto wrap(InType, Decorated)(Decorated putter) if (isPutter!Decorated)
        {
            struct PutterDecorator
            {
                mixin PutterDecoratorMixin!(Decorated, InType);
                this(Decorated putter)
                {
                    this.putter = putter;
                }

                void put(InputType p)
                {
                    std.range.put(putter, p);
                }
            }

            return PutterDecorator(putter);
        }

        alias OutputType(InputType) = InputType;
    }

    static assert(isTransducer!(Tducer, int));
}

/++
Mixin used to implement common code for all putter decorators.

Specific putter decorators provide additional capabilities to $(D Putter) by wrapping it and forwarding calls to the $(D Decorated) $(D putter) object. $(D InType) - type for this decorator to take in $(D PutterDecorator.put).

For more information on how decorators work google "Decorator design pattern".
+/
mixin template PutterDecoratorMixin(Decorated, InType)
{
    private Decorated putter;

    /++
    PutterDecorators which do early termination need to override this method. By default forwards to the $(D Decorated) $(D Putter.isDone).

    For an example of overriding this method see $(D transduced.transducers.Taker).
    +/
    pragma(inline, true) bool isDone()
    {
        return putter.isDone();
    }
    /++
    PutterDecorators which do buffering need to override this method. By default forwards to the $(D Decorated) $(D Putter.flush).

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
    Type taken by wrapped output range. Do not override.
    +/
    alias TargetType = Decorated.TargetType;

    /++
    Type of input taken by $(D Putter.put). Do not override.
    +/
    alias InputType = InType;
}

/++
Wraps an $(D OutputRange) + $(D std.range.put) function in a struct providing early termination, buffering, and flushing.
+/
public struct Putter(ElementType, OutputRange) if (isOutputRange!(OutputRange, ElementType))
{
    private OutputRange _to;
    this(OutputRange to)
    {
        this._to = own(to);
    }

    /++
    Type taken in $(D put).
    +/
    alias InputType = ElementType;

    /++
    Type taken by wrapped $(D OutputRange).
    +/
    alias TargetType = InputType;

    /++
    Put the given $(D input) into the $(D Putter.to) output.
    
    A single step in a sequential process implemented using transducers.
    +/
    void put(InputType input)
    {
        std.range.put(_to, input);
    }

    /++
    Early termination. Returns true when there's a guarantee that this $(D Putter) won't $(D std.range.put) new data to $(D PutterDecorator.to) for any future $(D Putter.put) calls, so they can be skipped.

    This check can be used for performance (in loops - to reduce calls which won't result in any output) and to provide early termination semantics (i.e. when working with infinite ranges).

    By default always returns false. If the wrapped $(D OutputRange) is an $(D ExtendedOutputRange), forwards call to $(D ExtendedOutputRange.isDone).
    +/
    bool isDone()
    {
        static if (isExtendedOutputRange!(OutputRange, InputType))
        {
            return _to.isDone();
        }
        return false;
    }

    /++
    Flushes any input buffered so far by PutterDecorators using $(D Putter.put). Can be called multiple times, or even not called at all.

    Usually called when finished $(D Putter.put)ting.

    If the wrapped $(D OutputRange) is an $(D ExtendedOutputRange), forwards call to $(D ExtendedOutputRange.flush).
    +/
    void flush()
    {
        static if (isExtendedOutputRange!(OutputRange, InputType))
        {
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
