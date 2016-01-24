/++
dlang input ranges:
-pull primitives
-sequential operations provided using wrapper structures - like map, filter...

output ranges:
-push primitives
-no sequential operations provided for those

-transducers
	-sequence transformations that are independent of execution strategy and transformed type
	-composable
	-easier to write than range wrappers
	-more algorithms (mapcat - finally!)
	-usable both in pull and push contexts
	-work with input ranges, output ranges and anything else you make it!
		-streams, message queues, observables (Reactive Extensions)...
	-transformation as an object
		-but any transformation can be used as an object whenn there are function objects available
	-compared to ranges
		-works only with plain input ranges, no random access transformations
		-buffered transducers allocate and require underlying process to allocate too
		-therfore may be slower than input ranges transformations
		-only transformations, do not produce values
		-works with stack functors (range methods like map allocate them on heap - see http://forum.dlang.org/post/kpwbtskhnkkiwkdsfzby@forum.dlang.org)
	-like std.range.tee (which just does map) generalized for all possible transformations

TODO: this module should contain usage examples for what's already implemented
+/
module transduced;

public import transduced.contexts;
public import transduced.core;
public import transduced.transducers;
