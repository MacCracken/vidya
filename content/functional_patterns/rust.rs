// Vidya — Functional Patterns — Rust port.
//
// Pure functions and memoization, compose and pipe, closures and partial
// application, what a closure captures, a persistent cons list that
// shares structure through Rc instead of copying, folds as its recursion
// scheme, and why the accumulator loop is the safe form of recursion.
//
// Closures are values: each is an anonymous struct of its captures,
// passed as `impl Fn` (static dispatch, no allocation) or boxed as
// `Box<dyn Fn>` when different closures share one type. A closure borrows
// what its body only reads unless it is `move`, and the borrow checker
// refuses one that would watch a variable change under it. A `const fn`
// reaches no mutable global state.

use std::cell::Cell;
use std::collections::HashMap;
use std::rc::Rc;

thread_local! {
    static COUNTER: Cell<i64> = const { Cell::new(0) };       // impure_next's hidden state
    static ADD_CALLS: Cell<i64> = const { Cell::new(0) };     // counted_add's call probe
    static CONS_ALLOCS: Cell<usize> = const { Cell::new(0) }; // nodes cons has allocated
}

// --- 1. Purity ---
// A pure fn's result depends only on its arguments, and calling it
// changes nothing. A `const fn` may call only const fns and reach no
// mutable global state, and the const assertion runs it at compile time.
// (It may still write through a `&mut` argument, so const means "no
// hidden state", not "no writes".) Written as a `const fn`, impure_next
// is refused at its definition:
// error[E0015]: cannot call non-const method `LocalKey::<Cell<i64>>::get`
// in constant functions.
const fn pure_add(a: i64, b: i64) -> i64 {
    a + b
}
const _: () = assert!(pure_add(2, 3) == 5, "pure_add runs at compile time");

fn impure_next() -> i64 {
    COUNTER.set(COUNTER.get() + 1);
    COUNTER.get()
}

// counted_add is pure_add plus a call counter, so a check can see whether
// the underlying fn ran (the counter is the test's probe; the value is
// still pure_add's).
fn counted_add(a: i64, b: i64) -> i64 {
    ADD_CALLS.set(ADD_CALLS.get() + 1);
    pure_add(a, b)
}

// Memoization: sound only for a pure fn, since a cached result must be
// what a fresh call would return. The key is BOTH arguments; a key of `a`
// alone would hand (2, 4) the result cached for (2, 3). The closure owns
// its table and changes it when called, so it is FnMut, not Fn: the type
// says the memoized fn has state (a RefCell inside would hide that).
fn memoize2(f: impl Fn(i64, i64) -> i64) -> impl FnMut(i64, i64) -> i64 {
    let mut table: HashMap<(i64, i64), i64> = HashMap::new();
    move |a, b| *table.entry((a, b)).or_insert_with(|| f(a, b))
}

// --- 2. Higher-order functions and composition ---
// compose(f, g)(x) = f(g(x))   (right to left, as in maths: f . g)
// pipe(f, g)(x)    = g(f(x))   (left to right, reading order)
// Generic over the types in between, and returned unboxed.
fn add_three(x: i64) -> i64 {
    x + 3
}

fn times_two(x: i64) -> i64 {
    x * 2
}

fn compose<A, B, C>(f: impl Fn(B) -> C, g: impl Fn(A) -> B) -> impl Fn(A) -> C {
    move |x| f(g(x))
}

fn pipe<A, B, C>(f: impl Fn(A) -> B, g: impl Fn(B) -> C) -> impl Fn(A) -> C {
    move |x| g(f(x))
}

// --- 3. Closures and partial application ---
// make_adder(n) returns a fn that remembers n: the `move` closure copied
// it into itself, so the closure is an 8-byte struct holding n (no heap).
fn make_adder(n: i64) -> impl Fn(i64) -> i64 {
    move |x| x + n
}

// The counter's state is a field of the closure, owned outright: `move`
// moved n in, and calling the closure mutates it, hence FnMut. Each
// make_counter() call builds a new closure with its own n.
fn make_counter() -> impl FnMut() -> i64 {
    let mut n = 0;
    move || {
        n += 1;
        n
    }
}

fn add3(a: i64, b: i64, c: i64) -> i64 {
    a + b + c
}

// partial(f, a, b) fixes the first two arguments of a 3-argument fn.
fn partial(f: impl Fn(i64, i64, i64) -> i64, a: i64, b: i64) -> impl Fn(i64) -> i64 {
    move |c| f(a, b, c)
}

// --- 4. The capture gotcha: see test_capture ---
// A `move` closure copies a Copy value when it is BUILT (early binding),
// so closures made in a loop keep the value each iteration had. Without
// `move`, `|| j` borrows j, and the loop's next `j += 1` is refused:
// error[E0506]: cannot assign to `j` because it is borrowed. That line
// cannot be in this file. Late binding needs a shared cell on purpose.

// --- 5. Persistent (immutable) list with structural sharing ---
// A cons cell is a head and an Rc to the tail; None is the empty list.
// Rc::clone bumps a reference count and copies nothing, so cons(0,
// xs.clone()) shares all of xs. Rc gives a &mut to its node only while
// the count is 1 (Rc::get_mut), so a node another version holds cannot
// be written: the in-place write that corrupts the Cyrius version cannot
// be written here without a RefCell inside the node or `unsafe`.
// Rc::make_mut is the sanctioned write: it clones the node first when
// anyone else still holds it. (Dropping a very long list recurses once
// per node; such lists want a hand-written Drop loop.)
#[derive(Clone)]
struct Node {
    head: i64,
    tail: List,
}

type List = Option<Rc<Node>>;

fn cons(head: i64, tail: List) -> List {
    CONS_ALLOCS.set(CONS_ALLOCS.get() + 1);
    Some(Rc::new(Node { head, tail }))
}

fn tail(xs: &List) -> &List {
    match xs {
        Some(n) => &n.tail,
        None => &None,
    }
}

// Node identity: the same allocation, not merely equal contents.
fn same_node(a: &List, b: &List) -> bool {
    match (a, b) {
        (Some(x), Some(y)) => Rc::ptr_eq(x, y),
        (None, None) => true,
        _ => false,
    }
}

fn list_of(values: &[i64]) -> List {
    values.iter().rev().fold(None, |acc, &v| cons(v, acc))
}

fn nth(xs: &List, i: usize) -> Option<i64> {
    let mut p = xs;
    for _ in 0..i {
        p = tail(p);
    }
    p.as_ref().map(|n| n.head)
}

// Structural equality: same values in the same order (not the same nodes).
fn list_eq(a: &List, b: &List) -> bool {
    let (mut p, mut q) = (a, b);
    while let (Some(x), Some(y)) = (p, q) {
        if x.head != y.head {
            return false;
        }
        p = &x.tail;
        q = &y.tail;
    }
    p.is_none() && q.is_none()
}

// Functional update: a new list with element i replaced. It copies the i
// cells in front of i plus the replaced cell (i + 1 allocations) and
// shares everything after it (one Rc::clone). The original is untouched.
fn update_at(xs: &List, i: usize, v: i64) -> List {
    match xs {
        None => None,
        Some(n) if i == 0 => cons(v, n.tail.clone()),
        Some(n) => cons(n.head, update_at(&n.tail, i - 1, v)),
    }
}

// --- 6. Fold as the recursion scheme ---
// foldr(f, z, [a, b, c]) = f(a, f(b, f(c, z)))   (recursion: O(n) stack)
// foldl(f, z, [a, b, c]) = f(f(f(z, a), b), c)   (a loop: O(1) stack)
// Iterator::fold is Rust's own foldl; list_of above uses it.
fn foldr<A, F: Fn(i64, A) -> A>(f: &F, z: A, xs: &List) -> A {
    match xs {
        None => z,
        Some(n) => f(n.head, foldr(f, z, &n.tail)),
    }
}

fn foldl<A>(f: impl Fn(A, i64) -> A, z: A, xs: &List) -> A {
    let mut acc = z;
    let mut p = xs;
    while let Some(n) = p {
        acc = f(acc, n.head);
        p = &n.tail;
    }
    acc
}

fn list_length(xs: &List) -> usize {
    foldl(|acc, _| acc + 1, 0, xs)
}

fn list_sum(xs: &List) -> i64 {
    foldl(|acc, x| acc + x, 0, xs)
}

fn list_reverse(xs: &List) -> List {
    foldl(|acc, x| cons(x, acc), None, xs)
}

fn list_map(g: impl Fn(i64) -> i64, xs: &List) -> List {
    foldr(&|x, acc| cons(g(x), acc), None, xs)
}

// --- 7. Tail recursion and stack depth ---
// Rust does not guarantee tail calls. Explicit tail calls (`become`,
// RFC 3407) are unstable: on rustc 1.99 stable, error[E0658]: `become`
// expression is experimental. LLVM may turn a tail call into a jump in
// an optimized build, but nothing promises it, and the gate's debug
// build keeps every frame. Naive recursion, n + sum(n - 1), needs one
// frame per level: measured here at about 48 B a frame in a debug build,
// so about 174,000 levels fit the 8 MiB main-thread stack (100,000 would
// pass), a spawned thread's default 2 MiB holds a quarter of that, and
// overflowing aborts the process ("has overflowed its stack"), not a
// panic anyone can catch. The accumulator loop needs no reasoning.
fn sum_to_loop(n: i64) -> i64 {
    let mut acc = 0;
    let mut i = 1;
    while i <= n {
        acc += i;
        i += 1;
    }
    acc
}

// === Tests ===

fn test_purity() {
    let r1 = pure_add(2, 3);
    let r2 = pure_add(2, 3);
    assert_eq!(r1, r2, "pure_add: same arguments, same result");
    assert_eq!(r1, 5, "pure_add(2, 3) = 5");

    COUNTER.set(0);
    let n1 = impure_next();
    let n2 = impure_next();
    assert_ne!(n1, n2, "impure_next: same call, different results (1, then 2)");
    assert_eq!(COUNTER.get(), 2, "impure_next left a trace: hidden state bumped twice");
}

fn test_memoize() {
    ADD_CALLS.set(0);
    let mut madd = memoize2(counted_add);
    let m1 = madd(2, 3);
    let m2 = madd(2, 3);
    assert_eq!(m1, 5, "memo: first call computes 2 + 3 = 5");
    assert_eq!(m2, 5, "memo: second call returns the cached 5");
    assert_eq!(ADD_CALLS.get(), 1, "memo: second call is a cache hit (1 call, not 2)");
    assert_eq!(madd(2, 4), 6, "memo: (2, 4) is a miss, the key is both arguments");
    assert_eq!(ADD_CALLS.get(), 2, "memo: the miss ran the underlying fn once more");
}

fn test_composition() {
    let c = compose(add_three, times_two);
    let p = pipe(add_three, times_two);
    assert_eq!(c(1), 5, "compose(f, g)(1) = f(g(1)) = 2 + 3 = 5");
    assert_eq!(p(1), 8, "pipe(f, g)(1) = g(f(1)) = 4 * 2 = 8");
    assert_ne!(c(1), p(1), "order matters: compose != pipe at x = 1");

    // The laws, over a range of x: compose applies g first, and pipe is
    // compose with its arguments swapped.
    let cgf = compose(times_two, add_three);
    assert!((-2..=2).all(|x| c(x) == add_three(times_two(x))), "compose(f, g)(x) == f(g(x)) for x in -2..2");
    assert!((-2..=2).all(|x| p(x) == cgf(x)), "pipe(f, g)(x) == compose(g, f)(x) for x in -2..2");
}

fn test_closures() {
    let add5 = make_adder(5);
    let add10 = make_adder(10);
    assert_eq!(add5(1), 6, "make_adder(5)(1) = 6");
    assert_eq!(add10(1), 11, "make_adder(10)(1) = 11: each adder keeps its own n");
    // A closure is a struct of its captures. Layout is unspecified, but
    // rustc stores make_adder's closure as its one i64, and a fn item
    // (add_three) as nothing at all: neither touches the heap.
    assert_eq!(std::mem::size_of_val(&add5), 8, "make_adder's closure is its captured i64");
    assert_eq!(std::mem::size_of_val(&add_three), 0, "a fn item captures nothing: 0 bytes");

    let mut c1 = make_counter();
    let mut c2 = make_counter();
    c1();
    c1();
    assert_eq!(c1(), 3, "counter 1 counted 1, 2, 3");
    assert_eq!(c2(), 1, "counter 2 starts at 1: its state is its own");
    assert_eq!(c1(), 4, "counter 1 carries on at 4, untouched by counter 2");

    let add_1_2 = partial(add3, 1, 2);
    assert_eq!(add_1_2(3), 6, "partial(add3, 1, 2)(3) = 1 + 2 + 3 = 6");
}

fn test_capture() {
    // By value: one variable j, but each `move` closure copied the value
    // j had when it was built. Different closures, one boxed type.
    let mut fs: Vec<Box<dyn Fn() -> i64>> = Vec::new();
    let mut j = 0;
    while j < 3 {
        fs.push(Box::new(move || j));
        j += 1;
    }
    let got: Vec<i64> = fs.iter().map(|f| f()).collect();
    assert_eq!(got, [0, 1, 2], "move closures copied j: [0, 1, 2]");

    // Early binding: a later assignment is not seen.
    let mut base = 1;
    let g = move || base;
    base = 99;
    assert_eq!((g(), base), (1, 99), "move copied 1; the later base = 99 is not seen");

    // Late binding on purpose: closures that BORROW one Cell read it when
    // called, after the loop left it at 3: the JS `var` result, [3, 3, 3].
    // The borrow checker allows it because a Cell is written through a
    // shared reference; the fix is the `move` copy above.
    let k = Cell::new(0);
    let mut refs: Vec<Box<dyn Fn() -> i64 + '_>> = Vec::new();
    while k.get() < 3 {
        refs.push(Box::new(|| k.get()));
        k.set(k.get() + 1);
    }
    let got: Vec<i64> = refs.iter().map(|r| r()).collect();
    assert_eq!(got, [3, 3, 3], "closures borrowing one Cell all see its final 3");

    let cell = Cell::new(1);
    let h = || cell.get();
    cell.set(99);
    assert_eq!(h(), 99, "a borrowing closure sees the later cell.set(99)");
}

fn test_persistent_list() {
    let xs = list_of(&[1, 2, 3]);
    let ys = cons(0, xs.clone()); // Rc::clone: a count bump, not a copy
    assert!(same_node(tail(&ys), &xs), "cons shares: tail(ys) IS xs, the same node");
    assert!(list_eq(&ys, &list_of(&[0, 1, 2, 3])), "ys reads [0, 1, 2, 3]");
    assert!(list_eq(&xs, &list_of(&[1, 2, 3])), "xs still reads [1, 2, 3] after the cons");

    let before = CONS_ALLOCS.get();
    let zs = update_at(&xs, 1, 20);
    assert_eq!(CONS_ALLOCS.get() - before, 2, "update at index 1 allocates i + 1 = 2 nodes, not 3");
    assert!(list_eq(&zs, &list_of(&[1, 20, 3])), "zs reads [1, 20, 3]");
    assert!(same_node(tail(tail(&zs)), tail(tail(&xs))), "the suffix after the updated cell is shared");
    assert!(!same_node(tail(&zs), tail(&xs)), "the updated cell is new, not xs's");
    assert!(list_eq(&xs, &list_of(&[1, 2, 3])), "xs still reads [1, 2, 3] after the update");

    // The gotcha cannot happen through Rc: there is no &mut to a shared
    // node. Asking for one with Rc::make_mut clones the node instead.
    let vs = list_of(&[1, 2, 3]);
    let ws = update_at(&vs, 0, 7); // ws = [7, 2, 3], shares vs's [2, 3]
    assert!(same_node(tail(&ws), tail(&vs)), "ws shares vs's [2, 3] node");
    let mut handle = tail(&vs).clone(); // a third owner of the [2, 3] node
    let shared = handle.as_mut().expect("vs has a tail");
    assert_eq!(Rc::strong_count(shared), 3, "the [2, 3] node has 3 owners: vs, ws, handle");
    Rc::make_mut(shared).head = 99; // shared, so make_mut copies it first
    assert_eq!(nth(&ws, 1), Some(2), "ws still reads 2: make_mut wrote a clone");
    assert_eq!(nth(&vs, 1), Some(2), "vs still reads 2 as well");
    assert_eq!(nth(&handle, 0), Some(99), "the write landed in the clone");
    assert!(!same_node(&handle, tail(&vs)), "the clone is a new node");
    assert!(same_node(tail(&handle), tail(tail(&vs))), "the clone still shares the [3] after it");
}

fn test_folds() {
    let xs = list_of(&[1, 2, 3]);
    assert_eq!(list_length(&xs), 3, "length via foldl = 3");
    assert_eq!(list_length(&None), 0, "length of the empty list = 0");
    assert_eq!(list_sum(&xs), 6, "sum via foldl = 1 + 2 + 3 = 6");
    assert!(list_eq(&list_reverse(&xs), &list_of(&[3, 2, 1])), "reverse via foldl = [3, 2, 1]");
    assert!(list_eq(&list_map(|x| x * 10, &xs), &list_of(&[10, 20, 30])), "map via foldr keeps order: [10, 20, 30]");
    assert!(list_eq(&xs, &list_of(&[1, 2, 3])), "the folds left xs as [1, 2, 3]");

    // Subtraction is not associative, so the fold's direction shows.
    assert_eq!(foldl(|a, b| a - b, 0, &xs), -6, "foldl(-, 0, [1, 2, 3]) = ((0 - 1) - 2) - 3 = -6");
    assert_eq!(foldr(&|a, b| a - b, 0, &xs), 2, "foldr(-, 0, [1, 2, 3]) = 1 - (2 - (3 - 0)) = 2");
}

fn test_tail_calls() {
    assert_eq!(sum_to_loop(100_000), 5_000_050_000, "accumulator loop: sum 1..100000 = 5000050000");
}

fn main() {
    test_purity();
    test_memoize();
    test_composition();
    test_closures();
    test_capture();
    test_persistent_list();
    test_folds();
    test_tail_calls();
    println!("All functional pattern examples passed.");
}
