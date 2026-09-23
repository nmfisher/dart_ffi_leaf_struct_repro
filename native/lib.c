#include <stddef.h>

typedef struct {
    float a;
    int c;
} Small; /* 8 bytes: returned in registers on macOS arm64. */

typedef struct {
    float a;
    const char *b;
    int c;
} Big; /* 24 bytes on macOS arm64: returned via hidden sret pointer. */

Small make_small(int x) {
    Small s;
    s.a = (float)x;
    s.c = 42;
    return s;
}

Small make_small_from_ptr(const unsigned char *x) {
    Small s;
    s.a = (float)x[0];
    s.c = 42;
    return s;
}

Big make_big(int x) {
    Big s;
    s.a = (float)x;
    s.b = "ok";
    s.c = 42;
    return s;
}

Big make_big_from_ptr(const unsigned char *x) {
    Big s;
    s.a = (float)x[0];
    s.b = "ok";
    s.c = 42;
    return s;
}

int make_int_from_ptr(const unsigned char *x) { return x[0] + 42; }

int take_big(Big s) { return (int)s.a + s.c; }
