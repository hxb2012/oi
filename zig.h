#define zig_extern extern
#define bool char
#define false 0
#define true  1
extern void abort();
#define zig_unreachable() abort()
