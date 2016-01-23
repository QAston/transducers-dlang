module transduced;

/*
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
	-like std.range.tee (which just does map) generalized for all possible transformations
*/

import std.stdio;
import std.algorithm.iteration;
import std.range;
import std.functional;
import std.range.primitives;
import std.array;
import std.traits;
import std.container.array;

auto mapReducing(alias f, S, T)(S seed, T elem) {
	put(seed,f(elem));
	return seed;
}

auto filterReducing(f, S, T)(S seed, T elem) {
	if (f(elem))
		put(seed,elem);
	return seed;
}

auto mapl(alias f, S, R) (ref S s, R r) {
	return reduce!(mapReducing!(f, S, typeof(r.front)))(s, r);
}

auto filterl(alias f, S, R) (ref S s, R r) {
	return reduce!(filterReducing!(f, S, typeof(r.front)))(s, r);
}

mixin template ProcessDecoratorMixin(Decorated) {
	private Decorated process;
	ref typeof(process.decoratedProcess()) decoratedProcess() @property {
		return process.decoratedProcess;
	}
	// only buffered transducers need flush
	void flush() {
		process.flush();
	}
}

bool isTerminatedEarly(Process)(ref Process process) {
	return process.decoratedProcess().isTerminatedEarly();
}

void markTerminatedEarly(Process)(ref Process process) {
	process.decoratedProcess().markTerminatedEarly();
}

mixin template ProcessMixin() {
	ref typeof(this) decoratedProcess() {
		return this;
	}
	private bool terminatedEarly;
	bool isTerminatedEarly() @property {
		return terminatedEarly;
	}
	void markTerminatedEarly() {
		terminatedEarly = true;
	}
	// could be called multiple times
	void flush() {
	}
}

// function returning a transducer
// transducer holds the info on what to do, is a runtime object in clojure
// does not know anything about the process
// can be shared
auto mapping(alias f)() {
	// transducers create an object which apply the given job description to given TransducibleProcess
	// the created objs are used privately
	// type specialization cannot be done at runtime, so templates needed
	static struct Mapping { // transducer
		auto opCall(Decorated)(auto ref Decorated process) { // process is a TransducibleProcess to decorate, possibly already decorated
			static struct ProcessDecorator {
				mixin ProcessDecoratorMixin!(Decorated);
				this(Decorated process) {
					this.process = process;
				}
				void step(T) (auto ref T elem) {
					process.step(f(elem));
				}
			}
			return ProcessDecorator(process);
		}
	}
	Mapping m;
	return m;
}

// transducer with early termination
// when transducer stack has isTerminatedEarly flag, TransducibleProcess must not supply more input (using step method)
// buffered transducer can still call step method in flush() to process input buffered earlier
auto taking(size_t howMany) {
	static struct Taking {
		private size_t howMany;
		this(size_t howMany) {
			this.howMany = howMany;
		}
		auto opCall(Decorated)(auto ref Decorated process) {
			static struct ProcessDecorator {
				mixin ProcessDecoratorMixin!(Decorated);
				private size_t howMany;
				this(Decorated process, size_t howMany) {
					this.process = process;
					this.howMany = howMany;
				}
				void step(T) (auto ref T elem) {
					if (--howMany == howMany.max) {
						process.markTerminatedEarly();
					}
					else {
						process.step(elem);
					}
				}
			}
			return ProcessDecorator(process, howMany);
		}
	}
	return Taking(howMany);
}

auto filtering(alias f)(){
	static struct Filtering { // transducer
		auto opCall(Decorated)(auto ref Decorated process) { // process is a TransducibleProcess to decorate, possibly already decorated
			static struct ProcessDecorator {
				mixin ProcessDecoratorMixin!(Decorated);
				this(Decorated process) {
					this.process = process;
				}
				void step(T) (auto ref T elem) {
					if (f(elem))
						process.step(elem);
				}
			}
			return ProcessDecorator(process);
		}
	}
	Filtering m;
	return m;
}

// transducer which calls step function more than once
// merges input ranges found in the input
auto catting(){
	static struct Catting { // transducer
		auto opCall(Decorated)(auto ref Decorated process) { // process is a TransducibleProcess to decorate, possibly already decorated
			static struct ProcessDecorator {
				mixin ProcessDecoratorMixin!(Decorated);
				this(Decorated process) {
					this.process = process;
				}
				void step(R) (auto ref R elem)  if (isInputRange!R) {
					foreach (e; elem) {
						process.step(e);
					}
				}
			}
			return ProcessDecorator(process);
		}
	}
	Catting m;
	return m;
}

auto mapcatting(alias f)() {
	return comp(mapping!f, catting());
}

// when action is only done on flush, use a transducer wrapping a range
// example: take-last/reverse/sort

// returns a transducer which accumulates all the step inputs into a random access range
// and processes them on flush using given function
auto flushing() {
}

interface VirtualProcess(T) {
	void step(T elem);
	void flush();
	bool isTerminatedEarly() @property;
	void markTerminatedEarly();

}
// TransducibleContexts:

// what to have:
// interfacing with ranges
//	create transducer with a range?
//  void step(Range r) instead of buffered ranges (would transduces range at a time instead of el at a time)
//   every step(Range r) call would have to allocate - unacceptable
//   but would be great for streams of bytes, it could be the stream interface

// create a lazy range using a transducer
// range element type cannot be deduced because underlying process can live without transducers, types cannot be deduced by wrapper for underlying type
template transducerRange(ElementType) {
	auto transducerRange(R, Transducer)(R range, Transducer t, size_t initialBufferSize = 1) {
		auto transducerStack = t(RangeProcess!(ElementType)(initialBufferSize));
		return TransducibleProcessRange!(R, typeof(transducerStack), ElementType)(range, transducerStack);
	}
}

private struct RangeProcess(ElementType) {
	mixin ProcessMixin!();
	private Array!ElementType _buffer;
	this(size_t initialBufferSize = 1) {
		this._buffer.reserve(initialBufferSize);
	}
	void step(ElementType elem) {
		this._buffer.insertBack(elem);
	}
}

private struct TransducibleProcessRange(Range, Process, ElementType) {
    alias R = Unqual!Range;
    R _input;
	Process _process;
	size_t _currentIndex;

	private ref Array!ElementType buffer() @property {
		return _process.decoratedProcess()._buffer;
	}

	private bool isBufferEmpty() {
		return _currentIndex == size_t.max;
	}
	private void popBuffer() {
		_currentIndex++;
		if (_currentIndex >= buffer.length) {
			_currentIndex = size_t.max; // mark as empty
			buffer.clear();
			nextBufferValue();
		}
	}
	private void nextBufferValue() {
		assert(isBufferEmpty());
		assert(buffer.length == 0);

		while  (!_input.empty() && !_process.isTerminatedEarly()) {
			_process.step(_input.front());
			_input.popFront();
			if (_input.empty() || _process.isTerminatedEarly()) {
				// last step call
				_process.flush();
			}
			if (buffer.length > 0) {
				_currentIndex = 0; // buffer filled, start returning elements from the beginning
				break;
			}
		}
	}

    this(R r, Process process) {
		_process = process;
        _input = r;
		_currentIndex = size_t.max;
		nextBufferValue();
    }

    @property bool empty() {
		return isBufferEmpty();
	}

    void popFront() {
		popBuffer();
    }

    @property auto front() {
        return buffer[_currentIndex];
    }
}

// populates output range with input range processed by a transducer
auto into(Out, Transducer, R)(Out to, auto ref Transducer t, R from) {
	auto transducerStack = t(IntoProcess!(Out)(to));
	foreach (el; from) {
		transducerStack.step(el);
		if(transducerStack.isTerminatedEarly())
			break;
	}
	transducerStack.flush();
	return transducerStack.decoratedProcess().accumulator;
}

private struct IntoProcess(Out) {
	private Out accumulator;
	this(Out accumulator) {
		this.accumulator = accumulator;
	}
	mixin ProcessMixin!();
	alias InputType = ElementType!Out;
	void step(InputType elem) {
		put(accumulator, elem);
	}
}

//wrap output range, put method redirects to step function, has flush method which flushes
//transduceOutput? pretransduce?

// wrap std.stdio.file
// create a stream-like object for file, which has write and flush

// wrap std.stream...

int minus(int i) {
	return -i;
}


unittest {
	int[] ar = new int[](4);
	mapl!((int x)=> ar.length)(ar, [1, 2, 3, 4]);
	assert( ar == [4,4,4,4]);
}

unittest {
	int[] ar = new int[](4);
	mapl!(minus)(ar, [1, 2, 3, 4]);
	assert( ar == [-1, -2, -3, -4]);
}

unittest {
	int[] ar = new int[](4);
	auto transducer = mapping!minus;
	into(ar,transducer, [1, 2, 3, 4]);
	assert( ar == [-1, -2, -3, -4]);
}

unittest {
	int[] ar = new int[](4);
	auto transducer = taking(2);
	into(ar,transducer, [1, 2, 3, 4]);
	assert( ar == [1, 2, 0, 0]);
}

auto comp(T1, T...)(auto ref T1 t1, auto ref T args)
{
	static if (T.length == 0) {
		return args[0];
	}
	else static if (T.length == 1) {
		return Composing!(T1, T[0])(t1, args[0]);
	}
	else {
		return comp(t1, comp(args));
	}
}

private struct Composing(T, U) {
	private T t;
	private U u;
	this(T t, U u) {
		this.t = t;
		this.u = u;
	}
	auto opCall(Decorated)(auto ref Decorated next) {
		return t(u(next));
	}
}

unittest {
	int[] ar = new int[](4);
	
	auto transducer = comp(taking(2), mapping!minus);
	
	into(ar,transducer, [1, 2, 3, 4]);
	assert( ar == [-1, -2, 0, 0]);
}

int twice(int i) {
	return i*2;
}
unittest {
	
	int[] ar = new int[](4);

	auto transducer = comp(taking(2), mapping!minus, mapping!twice);

	into(ar,transducer, [1, 2, 3, 4]);
	assert( ar == [-2, -4, 0, 0]);
}

unittest {
	auto transducer = comp(taking(2), mapping!minus, mapping!twice);

	auto res = transducerRange!(int)([1, 2, 3, 4], transducer).array();
	assert(res == [-2, -4]);
}

unittest {
	auto res = transducerRange!(int)([[1, 2, 3, 4]], catting()).array();
	assert(res == [1, 2, 3, 4]);
}

int even(int i) {
	return !(i % 2);
}

unittest {
	auto res = transducerRange!(int)([1, 2, 3, 4], filtering!even()).array();
	assert(res == [2, 4]);
}

int[] duplicate(int i) {
	return [i, i];
}

unittest {

	static struct Dup(T) {
		this(size_t times) {
		}
		T[] opCall(T t) {
			return repeat(t);
		}
	}
	auto res = transducerRange!(int)([1, 2, 3, 4], mapcatting!duplicate()).array();
	writeln(res);
	assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
}

//transducers todo - from clojure:
// remove take-while take-nth take-last drop drop-while replace partition-by partition-all (chunks?) keep keep-indexed map-indexed distinct interpose dedupe random-(possibly implement as a transducer for clojure)
// from std.range
// chunks - fixed size chunks of input
// attach index, return tuples (std.range.enumerate)
// attach range to processed elements, return tuples (std.range.zip)
// front traversal - returns first items of input (map would be enough?)
// indexed 	Creates a range that offers a view of a given range as though its elements were reordered according to a given range of indices.
// stride - returns every n element from input: equal(stride(a, 3), [ 1, 4, 7, 10 ][])
// chain - rename comp to chain?
// from std.algorithm.iteration
// chunk by: 	chunkBy!((a,b) => a[1] == b[1])([[1, 1], [1, 2], [2, 2], [2, 1]]) returns a range containing 3 subranges: the first with just [1, 1]; the second with the elements [1, 2] and [2, 2]; and the third with just [2, 1].
// each - do sideffects
// group: 	group([5, 2, 2, 3, 3]) returns a range containing the tuples tuple(5, 1), tuple(2, 2), and tuple(3, 2).group([5, 2, 2, 3, 3])
// sum - just suming step for reduce
// uniq - 	Iterates over the unique elements in a range, which is assumed sorted.