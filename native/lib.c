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

/* The peer's native field points to a byte used in the result. Mutating the
 * input proves the native function was actually called. */
Small make_small_from_peer(const unsigned char *peer, unsigned char *x) {
    return make_small(peer[0] + x[0]++);
}

Big make_big_from_peer(const unsigned char *peer, unsigned char *x) {
    return make_big(peer[0] + x[0]++);
}

int make_int_from_peer(const unsigned char *peer, unsigned char *x) {
    return peer[0] + x[0]++ + 42;
}
