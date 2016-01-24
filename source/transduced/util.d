module transduced.util;

template isStaticFn(alias f) {
	enum bool isStaticFn = __traits(isStaticFunction, f);
}

// wrapper object for static functions
// needed so we can use function object syntax with static functions
// allows to use same code by delegates/callable objs and static functions
struct StaticFn(alias f)  {
	pragma(inline, true)
		auto opCall(T...)(auto ref T args) inout {
			return f(args);
		}
}