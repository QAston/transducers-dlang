module transduced.contexts;

import std.range.primitives;
import std.array;
import std.container.array;
import transduced.util;
import transduced.core;

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
	auto transducerRange(R, Transducer)(R range, Transducer t, size_t initialBufferSize = 1) if(isInputRange!R) {
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

private struct TransducibleProcessRange(Range, Process, ElementType) if(isInputRange!Range) {
	import std.traits:Unqual;
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
auto into(Out, Transducer, R)(Out to, auto ref Transducer t, R from) if (isInputRange!R && isOutputRange!(Out, ElementType!Out)) {
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