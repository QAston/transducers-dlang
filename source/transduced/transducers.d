module transduced.transducers;

import transduced.util;
import transduced.core;
import std.range.primitives;

// function returning a transducer
// transducer holds the info about what to do with input, but doesn't know the overall process
// opCall applies the transducer to given process
// can be shared
auto mapper(alias f)() if (isStaticFn!f) {
	return mapper(StaticFn!(f).init);
}
auto mapper(F)(F f) {
	// transducers create an object which apply the given job description to given TransducibleProcess
	// the created objs are used privately
	// type specialization cannot be done at runtime, so templates needed
	static struct Mapper { // transducer
		private F f;
		this(F f) {
			this.f = f;
		}
		auto opCall(Decorated)(auto ref Decorated process) { // process is a TransducibleProcess to decorate, possibly already decorated
			static struct ProcessDecorator {
				mixin ProcessDecoratorMixin!(Decorated);
				private F f;
				this(Decorated process, F f) {
					this.f  = f;
					this.process = process;
				}
				void step(T) (auto ref T elem) {
					process.step(f(elem));
				}
			}
			return ProcessDecorator(process, f);
		}
	}
	return Mapper(f);
}

// transducer with early termination
// when transducer stack has isTerminatedEarly flag, TransducibleProcess must not supply more input (using step method)
// buffered transducer can still call step method in flush() to process input buffered earlier
auto taker(size_t howMany) {
	static struct Taker {
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
	return Taker(howMany);
}

auto filterer(alias f)() if (isStaticFn!f) {
	return filterer(StaticFn!(f).init);
}
auto filterer(F)(F f) {
	static struct Filterer {
		private F f;
		this(F f) {
			this.f = f;
		}
		auto opCall(Decorated)(auto ref Decorated process) {
			static struct ProcessDecorator {
				mixin ProcessDecoratorMixin!(Decorated);
				private F f;
				this(Decorated process, F f) {
					this.f = f;
					this.process = process;
				}
				void step(T) (auto ref T elem) {
					if (f(elem))
						process.step(elem);
				}
			}
			return ProcessDecorator(process, f);
		}
	}
	return Filterer(f);
}


static struct Catter {
	auto opCall(Decorated)(auto ref Decorated process) inout {
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

// transducer which calls step function more than once
// merges input ranges found in the input
// just a variable - no need for a constructor when there's no state
immutable(Catter) catter;

auto mapcatter(alias f)() if (isStaticFn!f) {
	return mapcatter(StaticFn!(f).init);
}
auto mapcatter(F)(F f) {
	return comp(mapper(f), catter);
}

// when action is only done on flush, use a transducer wrapping a range
// example: take-last/reverse/sort

// returns a transducer which accumulates all the step inputs into a random access range
// and processes them on flush using given function
auto flusher() {
}

auto comp(T1, T...)(auto ref T1 t1, auto ref T args)
{
	static if (T.length == 0) {
		return args[0];
	}
	else static if (T.length == 1) {
		return Composer!(T1, T[0])(t1, args[0]);
	}
	else {
		return comp(t1, comp(args));
	}
}

private struct Composer(T, U) {
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

version(unittest) {
	import std.array;
	import transduced.contexts;
	import std.range;

	int minus(int i) {
		return -i;
	}

	unittest {
		int[] ar = new int[](4);
		auto transducer = mapper!(minus);
		into(ar,transducer, [1, 2, 3, 4]);
		assert( ar == [-1, -2, -3, -4]);
	}

	unittest {
		int[] ar = new int[](4);
		auto transducer = taker(2);
		into(ar,transducer, [1, 2, 3, 4]);
		assert( ar == [1, 2, 0, 0]);
	}

	unittest {
		int[] ar = new int[](4);

		auto transducer = comp(taker(2), mapper!minus);

		into(ar,transducer, [1, 2, 3, 4]);
		assert( ar == [-1, -2, 0, 0]);
	}

	int twice(int i) {
		return i*2;
	}
	unittest {

		int[] ar = new int[](4);

		auto transducer = comp(taker(2), mapper!minus, mapper!twice);

		into(ar,transducer, [1, 2, 3, 4]);
		assert( ar == [-2, -4, 0, 0]);
	}

	unittest {
		auto transducer = comp(taker(2), mapper!minus, mapper!twice);

		auto res = transducerRange!(int)([1, 2, 3, 4], transducer).array();
		assert(res == [-2, -4]);
	}

	unittest {
		auto res = transducerRange!(int)([[1, 2, 3, 4]], catter).array();
		assert(res == [1, 2, 3, 4]);
	}

	int even(int i) {
		return !(i % 2);
	}

	unittest {
		auto res = transducerRange!(int)([1, 2, 3, 4], filterer!even()).array();
		assert(res == [2, 4]);
	}

	int[] duplicate(int i) {
		return [i, i];
	}

	static struct Dup(T) {
		size_t times;
		this(size_t times) {
			this.times = times;
		}
		~this() {
			times = 0;
		}
		T[] opCall(T t) {
			return repeat(t, times).array();
		}
	}

	unittest {
		auto res = transducerRange!(int)([1, 2, 3, 4], mapcatter!duplicate()).array();
		assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
	}

	unittest {
		auto dupper = Dup!int(2);
		auto res = transducerRange!(int)([1, 2, 3, 4], mapcatter(dupper)).array();
		assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
	}

	unittest {
		auto dupper = Dup!int(2);
		int a = 2;
		auto res = transducerRange!(int)([1, 2, 3, 4], mapcatter((int x)=>[a, a])).array();
		assert(res == [2,2,2,2,2,2,2,2]);
	}
}