module transduced;

// goal - transformation composition separate from types on which it's defined
//  is this even needed?
//    can write adapters that convert to seq?
// would this solve output range problem?
//  putting sequentially into anything: output range, another input range, socket...
// allow composition of transforms without types to be applied later onto types
// would that even be useful?

/*
dlang input ranges:
-pull primitives
-composed using wrapper structures

output ranges:
-push primitives
-not composed by default

-transducers
	-compose operations separately to not commit to push/pull
	-doesn't require materializing the struct
*/

import std.stdio;
import std.algorithm.iteration;
import std.range;
import std.functional;
import std.range.primitives;
import std.array;
import std.traits;

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
	Decorated process;
	// those 2 could possibly be free function, but they'd have access issues with transducers defined in other modules?
	bool isTerminatedEarly() @property {
		return process.isTerminatedEarly();
	}
	void markTerminatedEarly() {
		process.markTerminatedEarly();
	}
	// only buffered transducers need flush
	void flush() {
		process.flush();
	}
}

mixin template ProcessMixin() {
	private bool terminatedEarly;
	bool isTerminatedEarly() @property {
		return terminatedEarly;
	}
	void markTerminatedEarly() {
		terminatedEarly = true;
	}
	void flush() {
	}
}

// transducer which calls step function more than once
// merges input ranges found in the input
auto catting(){
	static struct Catting(Decorated) {
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
		auto opCall(Decorated)(Decorated process) { // process is a TransducibleProcess to decorate, possibly already decorated
			static struct ProcessDecorator {
				mixin ProcessDecoratorMixin!(Decorated);
				this(Decorated process) {
					this.process = process;
				}
				void step(T) (T elem) {
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
		auto opCall(Decorated)(Decorated process) {
			static struct ProcessDecorator {
				mixin ProcessDecoratorMixin!(Decorated);
				private size_t howMany;
				this(Decorated process, size_t howMany) {
					this.process = process;
					this.howMany = howMany;
				}
				void step(T) (T elem) {
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

// TransducibleContext

// transduce
//basic transform of step fn
//reduce but with completion call at the end
//implies step fn must have arity-1

// step fn alone won't work because it has no arity 1!
// by default we could wrap regular fn with completed step that just returns
// note that clojure has IReduce interface which lets a collection implement reduce on it's own
/*auto transduce(alias stepFn, R, Transducer, S)(R r, S s, Transducer t) {
	auto transducerStack = t.wrap(stepFn);//
	auto returnValue = s;// reduce!((, ){} )(r, s); //here in clojure reduced is checked, D doesn't have a mechanism to stop reduce, so we need our own reduce
	// for now we could just run in a loop to test
	return transducerStack.completed(returnValue);
}*/
}

// populates output range with input range processed by a transducer
auto into(Out, Transducer, R)(Out to, Transducer t, R from) {
	static struct IntoProcess {
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
	IntoProcess process = IntoProcess(to);
	auto transducerStack = t(process);
	foreach (el; from) {
		transducerStack.step(el);
		if(transducerStack.isTerminatedEarly())
			break;
	}
	transducerStack.flush();
	return process.accumulator;
}

// educe
// pin collection to transducer, created a sequence on which element reads execute transducer code

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
	auto opCall(Decorated)(Decorated next) {
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