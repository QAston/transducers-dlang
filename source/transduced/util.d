/++
Utility module for implementing transducers.
+/
module transduced.util;

/++
Returns true when given static function can be wrapped using $(D StaticFn)
+/
template isStaticFn(alias f)
{
    enum bool isStaticFn = __traits(isStaticFunction, f);
}

/++
Wrapper object for static functions, for use as callable objects.

Allows using the same code by delegates/callable objs and static functions, while preserving optimizations for static functions.

Examples:
---
auto mapper(alias f)() if (isStaticFn!f) {
    return mapper(StaticFn!(f).init); // forward to version taking a callable object
}
auto mapper(F)(F f) {
...
}
---
+/
struct StaticFn(alias f)
{
    pragma(inline, true) auto opCall(T...)(auto ref T args) inout
    {
        return f(args);
    }
}
