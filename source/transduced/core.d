/++
Module introducing core concepts of the library.

Containing specifications for transducers, transducible processes, transducible contexts and process decorators.

TODO: This module documentation should explain the contracts and how to implement stuff.
+/
module transduced.core;

import std.range;
import std.array;

/++
Mixin used to implement common code for all transducible process decorators.
+/
mixin template ProcessDecoratorMixin(Decorated)
{
    private Decorated process;
    /++
	Returns ref to the underlying process struct that's decorated. Do not override.
	+/
    pragma(inline, true) ref typeof(process.decoratedProcess()) decoratedProcess() @property
    {
        return process.decoratedProcess;
    }
    /++
	ProcessDecorators which do buffering need to override this flush method.
	This method allows to process remaining input and feed it to the wrapped process by calling step, just like step methods do.
	After all processing is done the decorator should call process on wrapped process.
	+/
    pragma(inline, true) void flush()
    {
        process.flush();
    }
}
/++
Returns true when process is marked for early termination.

Transducible context should check for this after every step, and if true stop calling $(D step), call $(D flush) and finish.
+/
bool isTerminatedEarly(Process)(ref Process process)
{
    return process.decoratedProcess().isTerminatedEarly();
}

/++
Marks underlying process for early termination.

Use inside ProcessDecorator.step() method prevent the transducible context from feeding the process more input.
When marked, no new input can be fed to the process using $(D step), outside of $(D flush) method.
+/
void markTerminatedEarly(Process)(ref Process process)
{
    process.decoratedProcess().markTerminatedEarly();
}

/++
Mixin used to implement common code for all transducible processes.
+/
mixin template ProcessMixin()
{
    pragma(inline, true) ref typeof(this) decoratedProcess()
    {
        return this;
    }

    private bool terminatedEarly;
    bool isTerminatedEarly() @property
    {
        return terminatedEarly;
    }

    void markTerminatedEarly()
    {
        terminatedEarly = true;
    }
    // could be called multiple times
    void flush()
    {
    }
}

interface VirtualProcess(T)
{
    void step(T elem);
    void flush();
    bool isTerminatedEarly() @property;
    void markTerminatedEarly();
}
