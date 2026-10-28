// Vidya — Dependent Types in C (C23)
//
// A dependent type depends on a VALUE: Vec n a is a vector whose length n
// is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
// v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
// values computed at run time; none of vidya's 11 languages can.
//
// C sits with Zig, Rust and Cyrius (compile-time values in types), near
// the weak end: an array's length is part of its type and static_assert
// does arithmetic on it, but nothing is generic over a length, so each
// length is its own struct. Past that, a constructor checks at run time,
// and a cast or a compound literal gets around it.

#include <stdio.h>
#include <string.h>

static int failures;

static void check(bool ok, const char *name) {
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", name);
        failures++;
    }
}

/* --- 1. Length-indexed vector --- */
/* One struct type per length. VLEN reads the length from the TYPE with
 * sizeof (which never evaluates its operand), and the compiler will not
 * pass one length where another is expected. Vec0's zero-length array is
 * a GNU extension the gate's flags accept; -pedantic refuses it ("ISO C
 * forbids zero-size array 'e'"). */
struct Vec0 { long e[0]; };
struct Vec2 { long e[2]; };
struct Vec3 { long e[3]; };
struct Vec5 { long e[5]; };

#define VLEN(v) (sizeof (v).e / sizeof (v).e[0])

constexpr size_t VEC2_LEN = sizeof(struct Vec2) / sizeof(long);
constexpr size_t VEC3_LEN = sizeof(struct Vec3) / sizeof(long);

/* head exists only for non-empty vector types; Vec0 has none. Handing
 * head3 the empty vector, or a Vec2, does not compile:
 *   head3(&empty);
 *   error: passing argument 1 of 'head3' from incompatible pointer type [-Wincompatible-pointer-types] */
static long head2(const struct Vec2 *v) { return v->e[0]; }
static long head3(const struct Vec3 *v) { return v->e[0]; }

/* append's lengths are in its signature. C cannot compute the type
 * "Vec(2 + 3)", so Vec5 is written by hand and static_assert proves its
 * length is 2 + 3. With Vec3 in its place the build stops:
 *   error: static assertion failed: "append(Vec2, Vec3) needs length 2 + 3"
 * and storing the result in the wrong length does not compile:
 *   struct Vec3 d; d = append23(a, b);
 *   error: incompatible types when assigning to type 'struct Vec3' from type 'struct Vec5' */
static_assert(sizeof(struct Vec5) == sizeof(struct Vec2) + sizeof(struct Vec3),
              "append(Vec2, Vec3) needs length 2 + 3");

static struct Vec5 append23(struct Vec2 a, struct Vec3 b) {
    struct Vec5 out;
    memcpy(out.e, a.e, sizeof a.e);
    memcpy(out.e + VLEN(a), b.e, sizeof b.e);
    return out;
}

/* A length known only at run time: C's variably modified types can write
 * one into a type (`long (*v)[n]`, `long a[static n]`), but nothing checks
 * at run time that the memory holds n elements: the type is a claim, not
 * a proof.
 * A run-time vector carries its length as a value, and head checks it
 * when it runs. */
struct LVec { size_t len; const long *data; };

static bool vec_head(struct LVec v, long *out) {
    if (v.len == 0) return false;
    *out = v.data[0];
    return true;
}

/* --- 2. Fin n: an index proven in range --- */
/* A Fin3 is made only by fin3(), which refuses anything outside 0..2, so
 * index3 needs no range test (and C adds none): k.i < 3 was proved when
 * k was built. Its bound is VEC3_LEN, computed from Vec3's own type. A Fin2 is a
 * different type, and so is a plain integer:
 *   index3(&b, k2);   (k2 a struct Fin2)
 *   error: incompatible type for argument 2 of 'index3' */
struct Fin2 { size_t i; };
struct Fin3 { size_t i; };

static bool fin2(long i, struct Fin2 *out) {
    if (i < 0 || (size_t)i >= VEC2_LEN) return false;
    out->i = (size_t)i;
    return true;
}

static bool fin3(long i, struct Fin3 *out) {
    if (i < 0 || (size_t)i >= VEC3_LEN) return false;
    out->i = (size_t)i;
    return true;
}

static long index2(const struct Vec2 *v, struct Fin2 k) { return v->e[k.i]; }
static long index3(const struct Vec3 *v, struct Fin3 k) { return v->e[k.i]; }

/* --- 3. Refinement at the boundary (parse, don't validate) --- */
/* The opaque-pointer pattern. In a library these declarations are the
 * whole of percent.h and the definition further down lives in percent.c,
 * so a caller in another file sees an incomplete type. percent() is then
 * the only way in, and discount() trusts what it is given.
 * test_refinement() sits above the definition to show that the API is
 * enough and that the type cannot be forged from here:
 *   &(struct Percent){150}   error: invalid use of undefined type 'struct Percent'
 *   p->v                     error: invalid use of undefined type 'const struct Percent'
 *   struct Percent q;        error: storage size of 'q' isn't known */
struct Percent;
static const struct Percent *percent(long x); /* nullptr when refused */
static long discount(long price, const struct Percent *p);
static int percent_checks; /* counts validations, so a check can see them */

static void test_refinement(void) {
    percent_checks = 0;
    check(percent(-1) == nullptr, "percent(-1) is refused");
    check(percent(101) == nullptr, "percent(101) is refused");
    const struct Percent *p0 = percent(0);
    const struct Percent *p100 = percent(100);
    const struct Percent *p25 = percent(25);
    check(p0 && p100 && p25, "percent accepts 0, 100 and 25");
    check(percent_checks == 5, "5 constructions, 5 validations");
    if (!(p0 && p100 && p25)) return;
    check(discount(200, p25) == 150, "discount(200, 25%) = 150");
    check(discount(200, p0) == 200, "discount(200, 0%) = 200");
    check(discount(200, p100) == 0, "discount(200, 100%) = 0");
    check(percent_checks == 5, "discount never re-validated: still 5 checks after 3 calls");
}

/* The percent.c half. Every line below this definition sees the field. */
struct Percent { long v; };

static struct Percent percent_pool[8];
static size_t percent_used;

static const struct Percent *percent(long x) {
    percent_checks++;
    if (x < 0 || x > 100) return nullptr;
    if (percent_used == sizeof percent_pool / sizeof percent_pool[0]) return nullptr;
    struct Percent *p = &percent_pool[percent_used++];
    p->v = x;
    return p;
}

static long discount(long price, const struct Percent *p) { return price - price * p->v / 100; }

/* --- 4. Σ type (dependent pair) --- */
/* Σ (n : Nat). Vec n: the TYPE of the second part depends on the VALUE of
 * the first. C's nearest form is a parameter whose bound is an earlier
 * parameter, `const long a[static n]` below; gcc checks it only when it
 * can see both, as in sum_n(3, two.e) with two a struct Vec2:
 *   error: 'sum_n' reading 24 bytes from a region of size 16 [-Werror=stringop-overread]
 * and not at all for a pointer whose target it cannot see. So sized()
 * checks the dependency once, at run time, and builds the pair only when
 * the data really holds n elements; sized_sum then trusts n. */
struct Sized { size_t n; const long *data; };

static bool sized(size_t n, struct LVec data, struct Sized *out) {
    if (data.len != n) return false;
    *out = (struct Sized){ .n = n, .data = data.data };
    return true;
}

static long sum_n(size_t n, const long a[static n]) {
    long total = 0;
    for (size_t i = 0; i < n; i++) total += a[i];
    return total;
}

static long sized_sum(struct Sized s) { return sum_n(s.n, s.data); }

/* --- 5. The escape hatch --- */
/* C has no private fields, and within this file the definition of Percent
 * is visible, so a compound literal builds a Percent that percent() never
 * saw, and a cast drops the const from a checked one so it can be
 * rewritten. `(struct Fin3){7}` compiles too, and index3 would read past
 * the vector. What keeps the refinement honest is the definition living in
 * one .c file (the incomplete type everywhere else) plus review of what
 * that file does with it. */

static void test_length_indexed(void) {
    struct Vec0 empty = {};
    struct Vec2 a = {{1, 2}};
    struct Vec3 b = {{3, 4, 5}};
    check(VLEN(empty) == 0, "Vec0's type says length 0");
    check(VLEN(a) == 2, "Vec2's type says length 2");
    check(VLEN(b) == 3, "Vec3's type says length 3");
    check(head2(&a) == 1, "head2([1, 2]) = 1");
    check(head3(&b) == 3, "head3([3, 4, 5]) = 3");

    struct Vec5 c = append23(a, b);
    check(VLEN(c) == 5, "append(Vec2, Vec3) has length 2 + 3 = 5");
    bool in_order = true;
    for (size_t i = 0; i < VLEN(c); i++) {
        if (c.e[i] != (long)i + 1) in_order = false;
    }
    check(in_order, "append(Vec2, Vec3) reads [1, 2, 3, 4, 5]");

    /* The run-time-length vector: the empty case is refused when it happens. */
    const long seven_data[] = {7};
    struct LVec none = {.len = 0, .data = nullptr};
    struct LVec seven = {.len = 1, .data = seven_data};
    long h0 = -1, h1 = -1;
    check(!vec_head(none, &h0), "runtime head of an empty vector is refused");
    check(vec_head(seven, &h1), "runtime head of [7] is allowed");
    check(h1 == 7, "runtime head of [7] = 7");
}

static void test_fin(void) {
    struct Vec2 a = {{1, 2}};
    struct Vec3 b = {{3, 4, 5}};
    struct Fin3 k;
    check(!fin3(-1, &k), "fin3(-1) is refused");
    check(!fin3(3, &k), "fin3(3) is refused: 3 is not < 3");

    int accepted = 0;
    bool reads_ok = true;
    for (long i = -1; i <= 3; i++) {
        if (fin3(i, &k)) {
            accepted++;
            if (index3(&b, k) != 3 + i) reads_ok = false;
        }
    }
    check(accepted == 3, "fin3 accepts exactly 0, 1, 2 out of -1..3");
    check(reads_ok, "index3 with each Fin3 reads [3, 4, 5] in order");

    struct Fin2 k2;
    check(!fin2(2, &k2), "fin2(2) is refused: 2 is not < 2");
    check(fin2(1, &k2) && index2(&a, k2) == 2, "index2([1, 2], fin2(1)) = 2");
}

static void test_sigma(void) {
    const long two_data[] = {1, 2};
    const long three_data[] = {1, 2, 3};
    struct LVec two = {.len = 2, .data = two_data};
    struct LVec three = {.len = 3, .data = three_data};
    struct Sized s;
    check(!sized(3, two, &s), "(3, [1, 2]) is refused: the length is 2");
    check(!sized(2, three, &s), "(2, [1, 2, 3]) is refused: the length is 3");
    bool built = sized(3, three, &s);
    check(built, "(3, [1, 2, 3]) is built");
    if (!built) return;
    check(s.n == 3, "the pair's n is 3");
    check(sized_sum(s) == 6, "sized_sum reads n = 3 elements: 1 + 2 + 3 = 6");
}

static void test_escape_hatch(void) {
    check(percent(150) == nullptr, "the API refuses 150");
    const struct Percent *forged = &(struct Percent){150}; /* skips percent() */
    check(forged->v == 150, "a compound literal makes a Percent of 150 anyway");
    check(discount(200, forged) == -100, "and discount trusts it: 200 - 300 = -100");

    struct Percent *p = (struct Percent *)percent(30); /* the cast drops const */
    check(p != nullptr, "percent(30) is accepted");
    if (p == nullptr) return;
    p->v = 250; /* rewrites a checked Percent in place */
    check(discount(100, p) == -150, "a write through the cast breaks a checked Percent too: -150");
}

int main(void) {
    test_length_indexed();
    test_fin();
    test_refinement();
    test_sigma();
    test_escape_hatch();
    if (failures) return 1;
    printf("All dependent type examples passed.\n");
    return 0;
}
