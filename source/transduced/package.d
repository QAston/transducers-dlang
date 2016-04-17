/++
<h1>Transduced</h1>
<p>Implementation of sequential operations on <a href="http://dlang.org/phobos/std_range_primitives.html">InputRanges/OutputRanges</a> inspired by <a href="http://clojure.org/reference/transducers">Clojure transducers</a>, as presented on this <a href="https://www.youtube.com/watch?v=6mTbuzafcII">strange loop video</a>.</p>
<p>This library complements phobos with operations for transforming OutputRanges (eg. map, filter, take), but also allows using those same operations on InputRanges. Designed to integrate with any range code.</p>
<h2>Motivation</h2>
<p>Ever since I've learned about transducers in clojure I wanted to implement them in D, and so this library came to be. Turns out it's possible to port a concept relying so on dynamic typing to a statically typed language.
Resulting library explores various design possibilities which could be useful in phobos, like stack closures and allocating ranges. No idea if anyone would actually use this library, but hey - it was fun to develop.</p>
<h2>Comparison with phobos sequence transformations</h2>
Transducers are better than phobos sequence transformations in these ways:
<ul>
<li>
transducers allow working with OutputRanges while phobos range algorithms don't (except std.range.tee, but that doesn't allow composition - ie you don't get a modified output range out of it)
</li>
<li>
transducers extend the OutputRange concept with buffering and early termination, see $(D transduced.core.isExtendedOutputRange)
</li>
<li>
transducers are objects which can be composed on their own, without specifying InputRange/OutputRange to apply them on
</li>
<li>
transducers are more reusable - could work on any sequential processing, not just plain ranges because they're independent of execution strategy (push/pull) and transformed type (eq. queues, ipc)
</li>
<li>
transducers provide different set of sequential operations (eg. flatMapper, taker with pred)
</li>
<li>
transducers can work with functors passed by value (callable structs for example), while phobos only works with functors passed by name (alias), which results in allocating data on heap <a href="http://forum.dlang.org/post/kpwbtskhnkkiwkdsfzby@forum.dlang.org"> allocating data on heap </a>
</li>
</ul>
Transducers are worse than phobos sequence transformations in the following ways:
<ul>
<li>
using transducers takes a bit more typing compared to range algorithms
</li>
<li>
transducers can't forward additional information about InputRanges like bidirectionality/forward ranges that can be forwarded by phobos sequence algorithms
</li>
<li>
some transducers allocate and own memory, while std ranges do not, therfore transducers can be a bit slower, but you can choose your allocator for those
</li>
<li>
transducers have more methods to inline, possibly resulting in more code bloat
</li>
<li>
transducers can't take inline delegates by name ("cannot access stack frame" compiler error, usually manifested as "can't find overload" because of template constraints), they can be only taken by value
</li>
</ul>
<ul>
Other differences:
<li>
when processing InputRanges transducers are lazy with respect to source range elements, each lazy step is generating all the output for that step at once; phobos functions are lazy with respect to generated output
</li>
</ul>

<h2>Differences from clojure transducers</h2>
<p>Basically everything is different except the core idea:
<ul>
<li>Transducers are objects instead of functions: different handling of early termination(flag on the object), completion (split between destructor and flush, flush can be called multiple times), no reducing function, etc.
<li>Design patterns/OOP terminology is used instead of mathematical terminology.
<li>Implementation has different constraints: statically typed using templates, cannot freely copy objects, cannot share references.
<li>Transduced adopts Dlang conventions and practices - while in clojure there are many possible transducible processes, in Dlang ExtendedOutputRanges encapsulate any possible process, so $(D transduced.core.Putter) as an only process is enough. 
</p>
</ul>
<h2>Usage examples</h2>
---
    import std.range;
    import std.array;
    import std.algorithm;

    // silly little domain model
    struct Baggage
    {
        int weight;
        bool food;
        bool ticking;
    }

    struct BaggageWithLabel
    {
        int weight;
        bool food;
        bool ticking;
        bool heavy;
    }

    class Plane
    {
        private Appender!(BaggageWithLabel[]) baggages;
        this()
        {
            baggages = appender!(BaggageWithLabel[]);
        }

        void load(BaggageWithLabel stuff)
        {
            baggages.put(stuff);
        }

        BaggageWithLabel[] getBaggages()
        {
            return baggages.data;
        }
    }

    // transducers describing process of dealing with baggage
    auto stopWhenTicking = taker!((bag) => !bag.ticking);

    auto filterNonFood = filterer!((bag) => !bag.food);

    auto labelHeavy = mapper!((bag) => BaggageWithLabel(bag.weight, bag.food,
        bag.ticking, bag.weight > 10));

    auto ontoPallets = chunkMapper!((scope BaggageWithLabel[] bagsView) => bagsView.dup)(3);

    // revert ontoPallets transformation - just an excercise
    auto offPallets = flattener();

    // compose a larger transducer from smaller ones
    auto baggageJob = comp(stopWhenTicking, filterNonFood, labelHeavy, ontoPallets,
        offPallets);

    auto baggages = [
        Baggage(10, false, false), Baggage(5, true, false), Baggage(20, false,
        false), Baggage(5, false, true), Baggage(2, true, false), Baggage(2,
        false, false), Baggage(30, false, false)
    ];

    // create an input range using a transducer
    auto lazyInputRange = baggages.transduceSource(baggageJob);
    static assert(isInputRange!(typeof(lazyInputRange)));

    assert(lazyInputRange.move().array() == [BaggageWithLabel(10, false, false,
        false), BaggageWithLabel(20, false, false, true)]);

    // similar (but simpler, I'm lazy) job using phobos:
    auto lazilyInputRangeUsingPhobos = baggages.take(5)
        .map!((bag) => BaggageWithLabel(bag.weight, bag.food, bag.ticking, bag.weight > 20));

    // create an output range using transducers
    Plane p = new Plane();
    void delegate(BaggageWithLabel) load = &p.load;
    // use the same transducer as for input range
    auto wrappedLoad = transduceSink!Baggage(baggageJob, load);

    // use an output range
    foreach (Baggage b; baggages)
    {
        // could check wrappedLoad.isDone here for early termination, but don't have to, can use extendedOutputRange just like regular one
        std.range.put(wrappedLoad, b);
    }

    wrappedLoad.flush(); // we're doing buffered transformations (ontoPallets), so we need to flush to get results

    assert(p.getBaggages() == [BaggageWithLabel(10, false, false, false),
        BaggageWithLabel(20, false, false, true)]);
---

<!--<h2>How this all works</h2>
What is a transducer
how it does what it does
how is it used
follow description of transducers in clojure?
<p>$(D transduced.core.Putter) - object wrapping an OutputRange, providing it with operations needed to implement transformations of sequential input: early termination and buffering (flush). Putter is itself an OutputRange. Wrapped OutputRange here represents a sequential process which we're manipulating. An example of that process is the process of building a new InputRange from an existing one. Each call to $(D OutputRange.put) adds a new item to our newly created InputRange. Depending on how and when we call $(D OutputRange.put), we get different resulting sequences of items.</p>
<p>PutterDecorator is a struct which wraps a Decorated $(D transduced.core.Putter) struct with input sequence transformation. The functionality is implemented inside $(D PutterDecorator.put) and $(D PutterDecorator.flush) by calling methods of a Decorated object:
<ul>
<li>forwarding no input to the decorated object - an example would be filter operation when based on a condition we either forward an input by calling $(D Decorated.put) or we don't
<li>forwarding each given input by calling $(D Decorated.put) - an example would be a map operation, which forwards transformed input
<li>forwarding more input than we're given - an example of that is flatten operation, where we merge given InputRanges together
<li>accumulating items - some transformations need to know about past inputs - an example of that is operation chunks, which agregates inputs into equally sized chunks. All accumulated items need to be processed on $(D Decorated.flush).
</ul>
</p>
<p>Transducer is a functor encapsulating sequence transformation description. For example: `auto transducer = mapper!((int x)=> x* 2)` is a transducer that doubles each given integer - the transducer object contains the description of that operation. Each transducer functor takes 1 argument - the possibly decorated $(D transduced.core.Putter) object and wraps it with associated PutterDecorator object (in case of mapper $(D transduced.transducers.Mapper)).</p>
<p>Transducers can be composed arbitrarily using $(D transduced.transducer.comp) function, which returns a transducer composed of given transducers, applied one-after-another, which when applied behave like InputRange composition in phobos (which are also decorators).
<p>-->
+/
module transduced;

public import transduced.range;
public import transduced.core;
public import transduced.transducers;

unittest
{
    import std.range;
    import std.array;
    import std.algorithm;

    // silly little domain model
    struct Baggage
    {
        int weight;
        bool food;
        bool ticking;
    }

    struct BaggageWithLabel
    {
        int weight;
        bool food;
        bool ticking;
        bool heavy;
    }

    class Plane
    {
        private Appender!(BaggageWithLabel[]) baggages;
        this()
        {
            baggages = appender!(BaggageWithLabel[]);
        }

        void load(BaggageWithLabel stuff)
        {
            baggages.put(stuff);
        }

        BaggageWithLabel[] getBaggages()
        {
            return baggages.data;
        }
    }

    // transducers describing process of dealing with baggage
    auto stopWhenTicking = taker!((bag) => !bag.ticking);

    auto filterNonFood = filterer!((bag) => !bag.food);

    auto labelHeavy = mapper!((bag) => BaggageWithLabel(bag.weight, bag.food,
        bag.ticking, bag.weight > 10));

    auto ontoPallets = chunkMapper!((scope BaggageWithLabel[] bagsView) => bagsView.dup)(3);

    // revert ontoPallets transformation - just an excercise
    auto offPallets = flattener();

    // compose a larger transducer from smaller ones
    auto baggageJob = comp(stopWhenTicking, filterNonFood, labelHeavy, ontoPallets,
        offPallets);

    auto baggages = [
        Baggage(10, false, false), Baggage(5, true, false), Baggage(20, false,
        false), Baggage(5, false, true), Baggage(2, true, false), Baggage(2,
        false, false), Baggage(30, false, false)
    ];

    // create an input range using a transducer
    auto lazyInputRange = baggages.transduceSource(baggageJob);
    static assert(isInputRange!(typeof(lazyInputRange)));

    assert(lazyInputRange.move().array() == [BaggageWithLabel(10, false, false,
        false), BaggageWithLabel(20, false, false, true)]);

    // similar (but simpler, I'm lazy) job using phobos:
    auto lazilyInputRangeUsingPhobos = baggages.take(5)
        .map!((bag) => BaggageWithLabel(bag.weight, bag.food, bag.ticking, bag.weight > 20));

    // create an output range using transducers
    Plane p = new Plane();
    void delegate(BaggageWithLabel) load = &p.load;
    // use the same transducer as for input range
    auto wrappedLoad = transduceSink!Baggage(baggageJob, load);

    // use an output range
    foreach (Baggage b; baggages)
    {
        // could check wrappedLoad.isDone here for early termination, but don't have to, can use extendedOutputRange just like regular one
        std.range.put(wrappedLoad, b);
    }

    wrappedLoad.flush(); // we're doing buffered transformations (ontoPallets), so we need to flush to get results

    assert(p.getBaggages() == [BaggageWithLabel(10, false, false, false),
        BaggageWithLabel(20, false, false, true)]);

}
