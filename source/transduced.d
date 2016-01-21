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
	Decorated next;
	final bool isReduced() @property {
		return next.isReduced();
	}
	final void markReduced() {
		next.markReduced();
	}
	auto completed(ReturnType!(Decorated.completed) seed) {
		return next.completed(seed);
	}
}

auto catting(){
	static struct Catting(Decorated) {
	}
}


// function returning a transducer
// transducer holds the info on what to do, is a runtime object in clojure
// does not know anything about the process
// can be shared
auto mapping(alias f)() {
	// transducers create an object which apply the given job description to given step function
	// the created objs are used privately
	// type specialization cannot be done at runtime, so polymorphism needed
	// or not, if transducing contexts are just parametrized with type, but then it'd generate code for int params:(

	static struct Mapping { // transducer
		auto opCall(Decorated)(Decorated next) { //next is a stackof step Structs, at the bottom of which is the transducing process
			static struct ProcessDecorator { // step "function", no arity-0 equivalent for D because the pattern is not popular in D
				mixin ProcessDecoratorMixin!(Decorated);
				this(Decorated next) {
					this.next = next;
				}
				auto step(T) (ReturnType!(Decorated.completed) seed, T elem) {
					return next.step(seed, f(elem));
				}
			}
			return ProcessDecorator(next);
		}
	}
	Mapping m;
	return m;
}

//if a transducer gets a reduced value from nested step call it must never call that step function again with input
//if the step func returns a reduced value, the process must not supply any more input 
// the reduced value is final accumulation value
// final accumulation value is still subject to completion

// reduced value could be implemented by some kind of variant type
// or maybe by a transducer method instead?

auto taking(size_t howMany) {
	static struct Taking {
		private size_t howMany;
		this(size_t howMany) {
			this.howMany = howMany;
		}
		auto opCall(Decorated)(Decorated next) {
			static struct ProcessDecorator {
				mixin ProcessDecoratorMixin!(Decorated);
				private size_t howMany;
				this(Decorated next, size_t howMany) {
					this.next = next;
					this.howMany = howMany;
				}
				auto step(T) (ReturnType!(Decorated.completed) seed, T elem) {
					if (--howMany == howMany.max) {
						this.markReduced();
						return seed;
					}
					auto result = next.step(seed, elem);
					return result;
				}
			}
			return ProcessDecorator(next, howMany);
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
auto transduce(alias stepFn, R, Transducer, S)(R r, S s, Transducer t) {
	auto transducerStack = t.wrap(stepFn);//
	auto returnValue = s;// reduce!((, ){} )(r, s); //here in clojure reduced is checked, D doesn't have a mechanism to stop reduce, so we need our own reduce
	// for now we could just run in a loop to test
	return transducerStack.completed(returnValue);
}

// populates output range with input range processed by a transducer
auto into(Out, Transducer, R)(Out to, Transducer t, R from) {
	static struct IntoProcess {
		private bool reduced;
		final bool isReduced() @property {
			return reduced;
		}
		final void markReduced() {
			reduced = true;
		}
		Out completed(Out seed) {
			return seed;
		}
		Out step(Out seed, ElementType!Out elem) {
			put(seed, elem);
			return seed;
		}
	}
	auto transducerStack = t(IntoProcess());
	foreach (el; from) {
		to = transducerStack.step(to, el);
		if(transducerStack.isReduced())
			break;
	}
	return transducerStack.completed(to);
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