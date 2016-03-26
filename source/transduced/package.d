/++
<h1>Transduced</h1>
<p>Implementation of sequential operations on <a href="http://dlang.org/phobos/std_range_primitives.html">InputRanges/OutputRanges</a> insprited by <a href="http://clojure.org/reference/transducers">Clojure transducers</a>.</p>
<p>This library complements phobos with operations for transforming output ranges, but also allows using those operations on input ranges. Designed to integrate well with any range code.</p>

<h2>Motivation</h2>
<p>Ever since I've learned about transducers in clojure I wanted to implement them in D, and so this library came to be.
Resulting library explores various design possibilities which could be useful in phobos, like stack closures and allocating ranges.</p>

<h2>Comparison with sequential operations from phobos</h2>
<ul>
<li>
transducers allow working with output ranges while std doesn't (except std.range.tee, but that doesn't allow composition)
</li>
<li>
transducers are objects which can be composed on their own, without specifying InputRange/OutputRange to apply them on
</li>
<li>
transducers could work on any sequential processing, not just ranges because they're independent of execution strategy (push/pull) and transformed type (could work with Reactive Extensions library for example)
</li>
<li>
transducers provide different set of sequential operations (eg. flatMaper, taker, windower)
</li>
<li>
transducers can work with stack functors, while phobos functor data is <a href="http://forum.dlang.org/post/kpwbtskhnkkiwkdsfzby@forum.dlang.org"> allocated on heap </a>
</li>
<li>
transducers have a bit heavier syntax
</li>
<li>
transducers can't use additional information about InputRanges like bidirectionality/forward ranges and random access that's used by std.algorithm
</li>
<li>
some transducers allocate and own memory, while std ranges do not, therfore transducers can be a bit slower
</li>
<li>
transducers have more methods to inline
</li>
</ul>

<h2>Differences from clojure transducers</h2>
<p>Basically everything is different except the concept. Transducers are objects instead of functions. Design patterns/OOP terminology is used instead of mathematical terminology. Implementation has different constraints: statically typed using templates, cannot freely copy objects, share references. Adopts Dlang conventions and practices. Bound to transducible context at compile time</p>

<h2>Usage examples</h2>
---
import transduced;
---
+/
module transduced;

public import transduced.range;
public import transduced.core;
public import transduced.transducers;
