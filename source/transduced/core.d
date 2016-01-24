module transduced.core;

import std.range.primitives;
import std.array;

mixin template ProcessDecoratorMixin(Decorated) {
	private Decorated process;
	pragma(inline, true)
		ref typeof(process.decoratedProcess()) decoratedProcess() @property {
			return process.decoratedProcess;
		}
	// only buffered transducers need to override flush
	pragma(inline, true)
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
	pragma(inline, true)
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

interface VirtualProcess(T) {
	void step(T elem);
	void flush();
	bool isTerminatedEarly() @property;
	void markTerminatedEarly();
}