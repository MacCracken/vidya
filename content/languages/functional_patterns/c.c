// Vidya — Functional Patterns in C (C23)
//
// Pure functions and memoization, compose and pipe, closures and partial
// application, what a closure captures, a persistent cons list that shares
// structure instead of copying, folds as its recursion scheme, and why
// deep recursion here is a loop. Mirrors cyrius.cyr's checks, less the two
// that need a guaranteed tail call.
//
// C has no closures (GCC's nested functions and Clang's blocks are
// extensions). One is written out by hand: a struct of a code pointer and
// an env pointer, called as f.code(f.env, x), and the env decides what is
// captured, a copy of a value or the address of a variable. Envs and list
// nodes come from fixed static pools: no malloc, nothing freed.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef int64_t i64;

static void check(bool ok, const char *what) {
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        exit(1);
    }
}

static void die(const char *what) {
    fprintf(stderr, "FAIL: %s\n", what);
    exit(1);
}

/* A closure per arity: the code takes the env as its first argument. A
 * closure that captures nothing has a null env and allocates nothing. */
typedef struct { i64 (*code)(void *env); void *env; } Fn0;
typedef struct { i64 (*code)(void *env, i64 x); void *env; } Fn1;
typedef struct { i64 (*code)(void *env, i64 a, i64 b); void *env; } Fn2;
typedef struct { i64 (*code)(void *env, i64 a, i64 b, i64 c); void *env; } Fn3;

static i64 call0(Fn0 f) { return f.code(f.env); }
static i64 call1(Fn1 f, i64 x) { return f.code(f.env, x); }
static i64 call2(Fn2 f, i64 a, i64 b) { return f.code(f.env, a, b); }
static i64 call3(Fn3 f, i64 a, i64 b, i64 c) { return f.code(f.env, a, b, c); }

/* Every env shape, and a fixed pool of slots that holds any of them. A
 * closure that outlives the function building it needs its env somewhere
 * that outlives that frame too: here a static pool, in Go or Python the
 * heap. */
#define MEMO_CAP 8
typedef struct { Fn2 f; int n; i64 a[MEMO_CAP], b[MEMO_CAP], v[MEMO_CAP]; } MemoEnv;
typedef struct { Fn1 f, g; } PairEnv;
typedef struct { Fn3 f; i64 a, b; } PartialEnv;

typedef union { MemoEnv memo; PairEnv pair; PartialEnv partial; i64 cell; } EnvSlot;

#define ENV_SLOTS 32
static EnvSlot env_pool[ENV_SLOTS];
static int env_used = 0;

static EnvSlot *env_new(void) {
    if (env_used == ENV_SLOTS) die("env pool exhausted");
    return &env_pool[env_used++];
}

/* --- 1. Purity --- */
/* A pure function's result depends only on its arguments, and calling it
 * changes nothing. C cannot check that. [[gnu::const]] promises it to gcc,
 * which then may merge or drop calls, and gcc trusts the promise without
 * checking it: on a non-inlined impure_next, gcc 16 -O2 makes one call for
 * two, both return 1 and the counter ends at 1. (C23 spells the same
 * promise [[unsequenced]].)
 * Nor can C run a function at compile time: C23 constexpr is for objects,
 * and a call is never a constant expression. A constant expression can be,
 * so pure_add's body is a macro that static_assert checks and the function
 * wraps, which is the nearest C gets to cyrius's `const fn` + #assert. */
#define PURE_ADD(a, b) ((a) + (b))
static_assert(PURE_ADD(2, 3) == 5, "pure_add's body runs at compile time");

[[gnu::const]] static i64 pure_add(i64 a, i64 b) { return PURE_ADD(a, b); }

static i64 g_counter = 0;           /* hidden state impure_next reads and bumps */
static i64 impure_next(void) {
    g_counter += 1;
    return g_counter;
}

/* Memoization caches results by argument, so it is sound only for a pure
 * function. counted_add is pure_add plus a call counter, the test's probe
 * for whether the underlying function ran. The key is BOTH arguments; a
 * key of `a` alone would hand (2, 4) the result cached for (2, 3). */
static i64 g_add_calls = 0;
static i64 counted_add(void *env, i64 a, i64 b) {
    (void)env;
    g_add_calls += 1;
    return pure_add(a, b);
}

static i64 memo_code(void *env, i64 a, i64 b) {
    MemoEnv *m = env;
    for (int i = 0; i < m->n; i++) {
        if (m->a[i] == a && m->b[i] == b) return m->v[i];
    }
    i64 v = call2(m->f, a, b);
    if (m->n < MEMO_CAP) {
        m->a[m->n] = a;
        m->b[m->n] = b;
        m->v[m->n] = v;
        m->n += 1;
    }
    return v;
}

/* memoize2(f) returns a closure with f's call shape that owns its table. */
static Fn2 memoize2(Fn2 f) {
    MemoEnv *m = &env_new()->memo;
    m->f = f;
    m->n = 0;
    return (Fn2){ memo_code, m };
}

/* --- 2. Higher-order functions and composition --- */
/* compose(f, g)(x) = f(g(x))   (right to left, as in maths: f . g)
 * pipe(f, g)(x)    = g(f(x))   (left to right, reading order) */
static i64 add_three(void *env, i64 x) { (void)env; return x + 3; }
static i64 times_two(void *env, i64 x) { (void)env; return x * 2; }
static const Fn1 ADD_THREE = { add_three, nullptr };
static const Fn1 TIMES_TWO = { times_two, nullptr };

static i64 compose_code(void *env, i64 x) {
    PairEnv *e = env;
    return call1(e->f, call1(e->g, x));
}

static i64 pipe_code(void *env, i64 x) {
    PairEnv *e = env;
    return call1(e->g, call1(e->f, x));
}

static Fn1 compose(Fn1 f, Fn1 g) {
    PairEnv *e = &env_new()->pair;
    *e = (PairEnv){ f, g };
    return (Fn1){ compose_code, e };
}

static Fn1 pipe(Fn1 f, Fn1 g) {
    PairEnv *e = &env_new()->pair;
    *e = (PairEnv){ f, g };
    return (Fn1){ pipe_code, e };
}

/* --- 3. Closures and partial application --- */
/* make_adder(n) copies n into its env. A counter's private state is its
 * env too: C's env is the closure's own memory, so it can be written in
 * place (cyrius needs a separate heap cell, because its closures hold
 * copies). Each make_counter() takes a fresh slot, so counters never share. */
static i64 adder_code(void *env, i64 x) { return x + *(const i64 *)env; }

static Fn1 make_adder(i64 n) {
    i64 *cell = &env_new()->cell;
    *cell = n;
    return (Fn1){ adder_code, cell };
}

static i64 counter_code(void *env) {
    i64 *count = env;
    *count += 1;
    return *count;
}

static Fn0 make_counter(void) {
    i64 *cell = &env_new()->cell;
    *cell = 0;
    return (Fn0){ counter_code, cell };
}

/* partial(f, a, b) fixes the first two arguments of a 3-argument function
 * and returns a 1-argument one. The types are per arity, so another arity
 * needs its own helper. */
static i64 add3(void *env, i64 a, i64 b, i64 c) { (void)env; return a + b + c; }

static i64 partial_code(void *env, i64 c) {
    PartialEnv *e = env;
    return call3(e->f, e->a, e->b, c);
}

static Fn1 partial(Fn3 f, i64 a, i64 b) {
    PartialEnv *e = &env_new()->partial;
    *e = (PartialEnv){ f, a, b };
    return (Fn1){ partial_code, e };
}

/* --- 4. The capture gotcha (what a closure sees of a loop variable) --- */
/* Python's `[lambda: i for i in range(3)]` gives [2, 2, 2] and a JS `var`
 * loop [3, 3, 3]: those closures look the variable up when CALLED. In C the
 * env says which: both closures below run the same code, read_cell, and
 * differ only in what their env points at, a private copy made when the
 * closure was built (early binding) or the variable itself (late binding). */
static i64 read_cell(void *env) { return *(const i64 *)env; }

static Fn0 capture_value(i64 v) {
    i64 *cell = &env_new()->cell;
    *cell = v;
    return (Fn0){ read_cell, cell };
}

static Fn0 capture_address(i64 *var) { return (Fn0){ read_cell, var }; }

/* --- 5. Persistent (immutable) list with structural sharing --- */
/* A cons cell is {head, tail}; nullptr is the empty list. cons never copies
 * its tail, so prepending is O(1) and the old list is still a complete,
 * unchanged list. `const Node *` makes the compiler refuse a write through
 * a list, but a cast takes the const away again (see the gotcha). Nodes come
 * from a fixed pool and are never freed, so no version can free a node
 * another one shares (with malloc, that needs a refcount or an arena). */
typedef struct Node { i64 head; const struct Node *tail; } Node;

#define NODE_CAP 128
static Node node_pool[NODE_CAP];
static int g_cons_allocs = 0;       /* nodes allocated, so checks can count copying */

static const Node *cons(i64 h, const Node *t) {
    if (g_cons_allocs == NODE_CAP) die("node pool exhausted");
    Node *c = &node_pool[g_cons_allocs++];
    c->head = h;
    c->tail = t;
    return c;
}

static i64 head(const Node *xs) { return xs->head; }
static const Node *tail(const Node *xs) { return xs->tail; }

static const Node *list3(i64 a, i64 b, i64 c) { return cons(a, cons(b, cons(c, nullptr))); }

static i64 nth(const Node *xs, int i) {
    const Node *p = xs;
    for (int k = i; k > 0; k--) p = tail(p);
    return head(p);
}

/* Structural equality: same values in the same order (not the same nodes). */
static bool list_eq(const Node *a, const Node *b) {
    while (a != nullptr && b != nullptr) {
        if (a->head != b->head) return false;
        a = a->tail;
        b = b->tail;
    }
    return a == nullptr && b == nullptr;
}

/* Functional update: a new list with element i replaced. It copies the i
 * cells in front of i plus the replaced cell (i + 1 allocations) and shares
 * everything after it. The original list is not touched. */
static const Node *update_at(const Node *xs, int i, i64 v) {
    if (xs == nullptr) return nullptr;
    if (i == 0) return cons(v, tail(xs));
    return cons(head(xs), update_at(tail(xs), i - 1, v));
}

/* --- 6. Fold as the recursion scheme --- */
/* foldr(f, z, [a, b, c]) = f(a, f(b, f(c, z)))   (recursion: O(n) stack)
 * foldl(f, z, [a, b, c]) = f(f(f(z, a), b), c)   (a loop: O(1) stack)
 * C has no generics, so the accumulator is a union and each step uses the
 * member its fold was started with. The combiner's argument order is part
 * of its type, as in Haskell's foldl :: (b -> a -> b) and
 * foldr :: (a -> b -> b), so subtraction needs one step per fold. */
typedef union { i64 n; const Node *list; } Acc;
typedef struct { Acc (*code)(void *env, Acc acc, i64 x); void *env; } StepL;
typedef struct { Acc (*code)(void *env, i64 x, Acc acc); void *env; } StepR;

static Acc foldr(StepR f, Acc z, const Node *xs) {
    if (xs == nullptr) return z;
    return f.code(f.env, xs->head, foldr(f, z, xs->tail));
}

static Acc foldl(StepL f, Acc z, const Node *xs) {
    Acc acc = z;
    for (const Node *p = xs; p != nullptr; p = p->tail) acc = f.code(f.env, acc, p->head);
    return acc;
}

static Acc len_step(void *env, Acc acc, i64 x) { (void)env; (void)x; return (Acc){ .n = acc.n + 1 }; }
static Acc sum_step(void *env, Acc acc, i64 x) { (void)env; return (Acc){ .n = acc.n + x }; }
static Acc rev_step(void *env, Acc acc, i64 x) { (void)env; return (Acc){ .list = cons(x, acc.list) }; }
static Acc sub_l(void *env, Acc a, i64 b) { (void)env; return (Acc){ .n = a.n - b }; }
static Acc sub_r(void *env, i64 a, Acc b) { (void)env; return (Acc){ .n = a - b.n }; }

static Acc map_step(void *env, i64 x, Acc acc) {
    const Fn1 *g = env;
    return (Acc){ .list = cons(call1(*g, x), acc.list) };
}

static i64 list_length(const Node *xs) { return foldl((StepL){ len_step, nullptr }, (Acc){ .n = 0 }, xs).n; }
static i64 list_sum(const Node *xs) { return foldl((StepL){ sum_step, nullptr }, (Acc){ .n = 0 }, xs).n; }

static const Node *list_reverse(const Node *xs) {
    return foldl((StepL){ rev_step, nullptr }, (Acc){ .list = nullptr }, xs).list;
}

/* The map step's env is the address of the parameter g: a closure that
 * does not outlive the call can keep its env on the stack (Rust's default),
 * so this one takes no pool slot. */
static const Node *list_map(Fn1 g, const Node *xs) {
    return foldr((StepR){ map_step, &g }, (Acc){ .list = nullptr }, xs).list;
}

static i64 times_ten(void *env, i64 x) { (void)env; return x * 10; }

/* --- 7. Tail recursion and stack depth --- */
/* ISO C does not guarantee tail calls. gcc turns a self tail call into a
 * jump at -O2 (-foptimize-sibling-calls), but the gate compiles without -O,
 * and nothing promises it at any level. GCC 15+ ([[gnu::musttail]]) and
 * Clang ([[clang::musttail]]) take an attribute on a return that makes a
 * call that cannot become a jump a compile error: an extension, which gcc
 * before 15 rejects under -Werror. Naive recursion, `return n + sum(n - 1)`,
 * needs one frame per level to do the `+` after the call returns; the
 * accumulator loop runs in constant stack under any compiler. */
static i64 sum_to_loop(i64 n) {
    i64 acc = 0;
    for (i64 i = 1; i <= n; i++) acc += i;
    return acc;
}

/* === Tests === */

static void test_purity(void) {
    i64 r1 = pure_add(2, 3);
    i64 r2 = pure_add(2, 3);
    check(r1 == r2, "pure_add: same arguments, same result");
    check(r1 == 5, "pure_add(2, 3) = 5");

    g_counter = 0;
    i64 n1 = impure_next();
    i64 n2 = impure_next();
    check(n1 != n2, "impure_next: same call, different results (1, then 2)");
    check(g_counter == 2, "impure_next left a trace: hidden state bumped twice");
}

static void test_memoize(void) {
    g_add_calls = 0;
    Fn2 madd = memoize2((Fn2){ counted_add, nullptr });
    i64 m1 = call2(madd, 2, 3);
    i64 m2 = call2(madd, 2, 3);
    check(m1 == 5, "memo: first call computes 2 + 3 = 5");
    check(m2 == 5, "memo: second call returns the cached 5");
    check(g_add_calls == 1, "memo: second call is a cache hit (1 call, not 2)");
    check(call2(madd, 2, 4) == 6, "memo: (2, 4) is a miss, the key is both arguments");
    check(g_add_calls == 2, "memo: the miss ran the underlying fn once more");
}

static void test_composition(void) {
    Fn1 c = compose(ADD_THREE, TIMES_TWO);
    Fn1 p = pipe(ADD_THREE, TIMES_TWO);
    check(call1(c, 1) == 5, "compose(f, g)(1) = f(g(1)) = 2 + 3 = 5");
    check(call1(p, 1) == 8, "pipe(f, g)(1) = g(f(1)) = 4 * 2 = 8");
    check(call1(c, 1) != call1(p, 1), "order matters: compose != pipe at x = 1");

    /* The laws, over a range of x: compose applies g first, and pipe is
     * compose with its arguments swapped. */
    Fn1 cgf = compose(TIMES_TWO, ADD_THREE);
    bool ok_c = true;
    bool ok_p = true;
    for (i64 x = -2; x <= 2; x++) {
        if (call1(c, x) != add_three(nullptr, times_two(nullptr, x))) ok_c = false;
        if (call1(p, x) != call1(cgf, x)) ok_p = false;
    }
    check(ok_c, "compose(f, g)(x) == f(g(x)) for x in -2..2");
    check(ok_p, "pipe(f, g)(x) == compose(g, f)(x) for x in -2..2");
}

static void test_closures(void) {
    Fn1 add5 = make_adder(5);
    Fn1 add10 = make_adder(10);
    check(call1(add5, 1) == 6, "make_adder(5)(1) = 6");
    check(call1(add10, 1) == 11, "make_adder(10)(1) = 11: each adder keeps its own n");

    Fn0 c1 = make_counter();
    Fn0 c2 = make_counter();
    call0(c1);
    call0(c1);
    check(call0(c1) == 3, "counter 1 counted 1, 2, 3");
    check(call0(c2) == 1, "counter 2 starts at 1: its state is its own");
    check(call0(c1) == 4, "counter 1 carries on at 4, untouched by counter 2");

    Fn1 add_1_2 = partial((Fn3){ add3, nullptr }, 1, 2);
    check(call1(add_1_2, 3) == 6, "partial(add3, 1, 2)(3) = 1 + 2 + 3 = 6");
}

static void test_capture(void) {
    /* By value: each closure copies i as it was when the closure was built. */
    Fn0 fs[3];
    for (i64 i = 0; i < 3; i++) fs[i] = capture_value(i);
    check(call0(fs[0]) == 0, "by value: closure 0 returns 0");
    check(call0(fs[1]) == 1, "by value: closure 1 returns 1");
    check(call0(fs[2]) == 2, "by value: closure 2 returns 2");

    /* Early binding: a later assignment is not seen. */
    i64 base = 1;
    Fn0 g = capture_value(base);
    base = 99;
    check(call0(g) == 1, "by value: captured 1, the later base = 99 is not seen");

    /* Late binding: every closure's env is the address of the one j, read
     * when called, after the loop left it at 3: the JS `var` result. j is
     * declared outside the loop on purpose: &i of `for (i64 i = ...)` read
     * after the loop is a dead variable, undefined behaviour rather than 3.
     * The fix is to capture the value. */
    Fn0 refs[3];
    i64 j;
    for (j = 0; j < 3; j++) refs[j] = capture_address(&j);
    check(call0(refs[0]) == 3, "by address: closure 0 sees j's final 3");
    check(call0(refs[1]) == 3, "by address: closure 1 sees j's final 3");
    check(call0(refs[2]) == 3, "by address: closure 2 sees j's final 3");
}

static void test_persistent_list(void) {
    const Node *xs = list3(1, 2, 3);
    const Node *ys = cons(0, xs);
    check(tail(ys) == xs, "cons shares: tail(ys) IS xs, the same node");
    check(list_eq(ys, cons(0, list3(1, 2, 3))), "ys reads [0, 1, 2, 3]");
    check(list_eq(xs, list3(1, 2, 3)), "xs still reads [1, 2, 3] after the cons");

    int before = g_cons_allocs;
    const Node *zs = update_at(xs, 1, 20);
    check(g_cons_allocs - before == 2, "update at index 1 allocates i + 1 = 2 nodes, not 3");
    check(list_eq(zs, list3(1, 20, 3)), "zs reads [1, 20, 3]");
    check(tail(tail(zs)) == tail(tail(xs)), "the suffix after the updated cell is shared");
    check(tail(zs) != tail(xs), "the updated cell is new, not xs's");
    check(list_eq(xs, list3(1, 2, 3)), "xs still reads [1, 2, 3] after the update");

    /* The gotcha: write through a node two versions share and both change.
     * `const` stops `tail(vs)->head = 99`; the cast below compiles, and is
     * defined only because the pool's nodes are not themselves const.
     * Persistence is a rule the code keeps, not one C enforces. */
    const Node *vs = list3(1, 2, 3);
    const Node *ws = update_at(vs, 0, 7);           /* ws = [7, 2, 3], shares vs's [2, 3] */
    ((Node *)tail(vs))->head = 99;                  /* in-place write to the shared cell */
    check(nth(ws, 1) == 99, "a write through a shared node changes the other version too");
}

static void test_folds(void) {
    const Node *xs = list3(1, 2, 3);
    check(list_length(xs) == 3, "length via foldl = 3");
    check(list_length(nullptr) == 0, "length of the empty list = 0");
    check(list_sum(xs) == 6, "sum via foldl = 1 + 2 + 3 = 6");
    check(list_eq(list_reverse(xs), list3(3, 2, 1)), "reverse via foldl = [3, 2, 1]");
    check(list_eq(list_map((Fn1){ times_ten, nullptr }, xs), list3(10, 20, 30)),
          "map via foldr keeps order: [10, 20, 30]");
    check(list_eq(xs, list3(1, 2, 3)), "the folds left xs as [1, 2, 3]");

    /* Subtraction is not associative, so the fold's direction shows. */
    check(foldl((StepL){ sub_l, nullptr }, (Acc){ .n = 0 }, xs).n == -6,
          "foldl(-, 0, [1, 2, 3]) = ((0 - 1) - 2) - 3 = -6");
    check(foldr((StepR){ sub_r, nullptr }, (Acc){ .n = 0 }, xs).n == 2,
          "foldr(-, 0, [1, 2, 3]) = 1 - (2 - (3 - 0)) = 2");
}

static void test_tail_calls(void) {
    check(sum_to_loop(100000) == 5000050000, "accumulator loop: sum 1..100000 = 5000050000");
}

int main(void) {
    test_purity();
    test_memoize();
    test_composition();
    test_closures();
    test_capture();
    test_persistent_list();
    test_folds();
    test_tail_calls();
    printf("All functional pattern examples passed.\n");
    return 0;
}
