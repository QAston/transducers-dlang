/++
Module providing transducers - objects encapsulating transformations of sequential processes i.e. map, filter.
+/
module transduced.transducers;

import transduced.util;
import transduced.core;
import std.range;

// function returning a transducer
// transducer holds the info about what to do with input, but doesn't know the overall process
// opCall applies the transducer to given process
// can be shared
/++
Returns a transducer modifying the process by transforming each step input using $(D f) function. 
+/
auto mapper(alias f)() if (isStaticFn!f) {
	return mapper(StaticFn!(f).init);
}
/// ditto
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

///
unittest {
	import std.array;
	import transduced.contexts;
	
	auto output = appender!(int[])();
	[1, 2, 3, 4].into(mapper!((int x) => -x), output);
	assert(output.data == [-1, -2, -3, -4]);
}

// transducer with early termination
// when transducer stack has isTerminatedEarly flag, TransducibleProcess must not supply more input (using step method)
// buffered transducer can still call step method in flush() to process input buffered earlier
/++
Returns a transducer modifying the process by forwarding only first $(D howMany) step inputs.
+/
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
///
unittest {
	import std.array;
	import transduced.contexts;

	auto output = appender!(int[])();
	[1, 2, 3, 4].into(taker(2), output);
	assert(output.data == [1, 2]);
}

/++
Returns a transducer modifying the process by forwarding only step inputs satisfying $(D pred).
+/
auto filterer(alias pred)() if (isStaticFn!pred) {
	return filterer(StaticFn!(pred).init);
}
/// ditto
auto filterer(F)(F pred) {
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
	return Filterer(pred);
}

///
unittest {
	import std.array;
	import transduced.contexts;

	auto output = appender!(int[])();
	[1, 2, 3, 4].into(filterer!((int x) => x % 2 == 1), output);
	assert(output.data == [1, 3]);
}


/++
Returns a transducer modifying the process by converting $(D InputRange) inputs to a series of inputs with all $(D InputRange) elements.
+/
//transducer which calls step function more than once
//merges input ranges found in the input
//just a variable - no need for a constructor when there's no state
immutable(Flattener) flattener;
/// ditto
static struct Flattener {
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

///
unittest {
	import std.array;
	import transduced.contexts;

	auto output = appender!(int[])();
	[[1, 2], [3, 4]].into(flattener, output);
	assert(output.data == [1, 2, 3, 4]);
}

/++
Composition of mapper and flattener.
+/
auto flatMapper(alias f)() if (isStaticFn!f) {
	return flatMapper(StaticFn!(f).init);
}
/// ditto
auto flatMapper(F)(F f) {
	return comp(mapper(f), flattener);
}

///
unittest {
	import std.array;
	import transduced.contexts;

	auto output = appender!(int[])();
	[1, 2, 3, 4].into(flatMapper!((int x) => [x, x])(), output);
	assert(output.data == [1, 1, 2, 2, 3, 3, 4, 4]);
}

/++
Returns a transducer modifying the process by buffering all the input and transforming it using given $(D f) function on f $(D flush).

This function allows one to plug range algorithms into transducers ecosystem.
Note that this transducer buffers all steps input until $(D flush), that results in following sideffects:
	- no steps are done untill flush, so process is not really continuous
	- internal transducer buffer has to allocate memory for that 

Params:
	f = a function taking an input range, and returning one.
		The function will be executed on flush with a random access range having all input data accumulated. 
		Returned range will be forwarded to the decorated process.
+/
auto flusher(alias f)() if (isStaticFn!f) {
	return flusher(StaticFn!(f).init);
}
/// ditto
auto flusher(F)(F f) {
	static struct Flusher {
		private F f;
		this(F f) {
			this.f = f;
		}
		auto opCall(Decorated)(auto ref Decorated process) {
			/*
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
			*/
		}
	}
	return Flusher(f);
}

/++
Returns a transducer modifying the process by wrapping it with the composition of given transducers.
+/
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

///
unittest {
	import std.array;
	import transduced.contexts;

	auto output = appender!(int[])();
	[1, 2, 3, 4].into(comp(mapper!((int x) => -x), taker(2)), output);
	assert(output.data == [-1, -2]);
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
		[1, 2, 3, 4].into(transducer, ar);
		assert( ar == [-1, -2, -3, -4]);
	}

	unittest {
		int[] ar = new int[](4);
		auto transducer = taker(2);
		[1, 2, 3, 4].into(transducer, ar);
		assert( ar == [1, 2, 0, 0]);
	}

	unittest {
		int[] ar = new int[](4);

		auto transducer = comp(taker(2), mapper!minus);

		[1, 2, 3, 4].into(transducer, ar);
		assert( ar == [-1, -2, 0, 0]);
	}

	int twice(int i) {
		return i*2;
	}
	unittest {

		int[] ar = new int[](4);

		auto transducer = comp(taker(2), mapper!minus, mapper!twice);

		[1, 2, 3, 4].into(transducer, ar);
		assert( ar == [-2, -4, 0, 0]);
	}

	unittest {
		auto transducer = comp(taker(2), mapper!minus, mapper!twice);

		auto res = transducerRange!(int)([1, 2, 3, 4], transducer).array();
		assert(res == [-2, -4]);
	}

	unittest {
		auto res = transducerRange!(int)([[1, 2, 3, 4]], flattener).array();
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
		auto res = transducerRange!(int)([1, 2, 3, 4], flatMapper!duplicate()).array();
		assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
	}

	unittest {
		auto dupper = Dup!int(2);
		auto res = transducerRange!(int)([1, 2, 3, 4], flatMapper(dupper)).array();
		assert(res == [1, 1, 2, 2, 3, 3, 4, 4]);
	}

	unittest {
		auto dupper = Dup!int(2);
		int a = 2;
		auto res = transducerRange!(int)([1, 2, 3, 4], flatMapper((int x)=>[a, a])).array();
		assert(res == [2,2,2,2,2,2,2,2]);
	}
}