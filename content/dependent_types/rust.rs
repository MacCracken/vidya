// Vidya — Dependent Types — Rust port.
//
// A dependent type depends on a VALUE: Vect n a is a vector whose length n
// is part of its type, Fin n an index proven < n, and a Σ pair (n, v) ties
// v's length to n. Agda, Idris, Lean, Rocq and F* check these even for
// values computed at run time; none of vidya's 11 languages can.
//
// Rust sits with Zig, C and Cyrius (compile-time values in types): const
// generics put a number in a type ([i64; N], Fin<N>) that an inline
// `const { assert!(..) }` checks per instance. Stable Rust cannot compute
// N + M in a type, so append takes its length from the caller and proves
// it. A run-time value gets a checked constructor behind a private field.

use fin::Fin;
use refined::{Percent, discount, percent_checks};
use sigma::{SizedVec, sized_sum};

// --- 1. Length-indexed vector ---
// [i64; N] is Rust's built-in length-indexed vector: the length is a
// const generic parameter, part of the type, known to the compiler. Idris
// spells it Vect n a, hence the name. A [i64; 2] where a [i64; 3] is
// expected does not compile:
//   let b: Vect<3> = a;
//   error[E0308]: mismatched types (expected an array with a size of 3, found one with a size of 2)
type Vect<const N: usize> = [i64; N];

// The length, read from the TYPE of the argument, for any vector type.
fn vlen<const N: usize>(_: &Vect<N>) -> usize {
    N
}

// head exists for every N, but its const block is evaluated for each N it
// is instantiated at, so the empty instance does not compile:
//   head(&[0i64; 0]);
//   error[E0080]: evaluation panicked: head of an empty vector
fn head<const N: usize>(v: &Vect<N>) -> i64 {
    const { assert!(N > 0, "head of an empty vector") };
    v[0]
}

// append's honest return type is [i64; N + M], and stable Rust refuses it:
//   fn append<const N: usize, const M: usize>(a: &Vect<N>, b: &Vect<M>) -> Vect<{ N + M }>
//   error: generic parameters may not be used in const operations
//   help: const parameters may only be used as standalone arguments here, i.e. `N`
// (that needs the unstable generic_const_exprs feature). The stable form
// takes the length K from the caller's annotation and proves K == N + M
// at compile time, so appending into the wrong length does not compile:
//   let d: Vect<4> = append(&a, &b);
//   error[E0080]: evaluation panicked: append: K must be N + M
fn append<const N: usize, const M: usize, const K: usize>(a: &Vect<N>, b: &Vect<M>) -> Vect<K> {
    const { assert!(K == N + M, "append: K must be N + M") };
    let mut out = [0; K];
    out[..N].copy_from_slice(a);
    out[N..].copy_from_slice(b);
    out
}

// A length known only at run time cannot be in a type. A slice carries
// its length as a value, so head checks it at run time and says so in its
// return type.
fn vec_head(v: &[i64]) -> Option<i64> {
    if v.is_empty() { None } else { Some(v[0]) }
}

// --- 2. Fin n: an index proven in range ---
// A Fin<N> holds an index proven < N. Its field is private to this
// module, and privacy is per module: inside `fin` a literal `Fin(7)`
// would compile, so the type lives in a module of its own and new() is
// the only way in from outside. There:
//   let k = Fin::<3>(7);
//   error[E0423]: cannot initialize a tuple struct which contains private fields
// index takes a [i64; N] and a Fin<N> with the SAME N, so the bound of
// the index is the vector's length by unification, not a second literal.
// A Fin<2> on a [i64; 3] does not compile:
//   fin::index(&b, k2);   // k2: Fin<2>
//   error[E0308]: mismatched types (expected `3`, found `2`)
mod fin {
    #[derive(Clone, Copy)]
    pub struct Fin<const N: usize>(usize);

    impl<const N: usize> Fin<N> {
        pub fn new(i: i64) -> Option<Fin<N>> {
            if i < 0 || i as usize >= N { None } else { Some(Fin(i as usize)) }
        }
    }

    // No check in the source: k.0 < N was proved when k was built. rustc
    // still emits one (measured, rustc 1.99.1 -C opt-level=3: a plain Fin<N>
    // keeps `cmpq $7 / ja` and the call to panic_bounds_check on a [i64; 8],
    // because the optimizer sees a usize loaded from a struct, not new()'s
    // i < N). It went away when the accessor stated the invariant with
    // core::hint::assert_unchecked (unsafe, sound only because new() is the
    // only way in), and for a constant index. It can never fire for a Fin
    // built by new().
    pub fn index<const N: usize>(v: &[i64; N], k: Fin<N>) -> i64 {
        v[k.0]
    }
}

// --- 3. Refinement at the boundary (parse, don't validate) ---
// Percent::new() is the one place the range is checked. Everything
// downstream takes a Percent and trusts it: discount never looks at the
// range. CHECKS counts validations, so a check can see that. The field is
// private to `refined`; outside it a Percent cannot be written down,
// read raw, or changed.
mod refined {
    use std::sync::atomic::{AtomicUsize, Ordering};

    static CHECKS: AtomicUsize = AtomicUsize::new(0);

    pub fn percent_checks() -> usize {
        CHECKS.load(Ordering::Relaxed)
    }

    // repr(transparent): laid out exactly as one i64 (section 5 relies on it).
    #[repr(transparent)]
    #[derive(Clone, Copy)]
    pub struct Percent(i64);

    impl Percent {
        pub fn new(x: i64) -> Option<Percent> {
            CHECKS.fetch_add(1, Ordering::Relaxed);
            if (0..=100).contains(&x) { Some(Percent(x)) } else { None }
        }
        pub fn get(self) -> i64 {
            self.0
        }
    }

    pub fn discount(price: i64, p: Percent) -> i64 {
        price - price * p.0 / 100
    }
}

// --- 4. Σ type (dependent pair) ---
// Σ (n : Nat). Vect n: the TYPE of the second part depends on the VALUE
// of the first. For a run-time n Rust cannot say that, so `data` is a
// Vec of any length and new() checks the dependency once: it builds a
// pair only when data really holds n elements. sized_sum then takes its
// loop bound from n alone. (Not named Sized: that would shadow Rust's
// marker trait.) Indexing still checks each i itself; the constructor's
// proof is why it never fails here.
mod sigma {
    pub struct SizedVec {
        n: usize,
        data: Vec<i64>,
    }

    impl SizedVec {
        pub fn new(n: usize, data: Vec<i64>) -> Option<SizedVec> {
            if data.len() != n { None } else { Some(SizedVec { n, data }) }
        }
        pub fn n(&self) -> usize {
            self.n
        }
    }

    pub fn sized_sum(s: &SizedVec) -> i64 {
        let mut total = 0;
        for i in 0..s.n {
            total += s.data[i];
        }
        total
    }
}

// --- 5. The escape hatch ---
// Outside `refined` the private field closes the safe doors: `Percent(150)`
// is E0423 as for Fin above, and a rewrite of a checked one is refused:
//   p.0 = 250;
//   error[E0616]: field `0` of struct `Percent` is private
// The hatch is `unsafe`: transmute reinterprets an i64 as a Percent (the
// sizes match), skipping new(). A crate that says #![forbid(unsafe_code)]
// cannot write it at all:
//   error: usage of an `unsafe` block
// What the language does not protect: code inside `refined` itself, where
// privacy does not apply, and any unsafe block in the crate. Review keeps
// those honest; `unsafe` is at least easy to grep for.

fn main() {
    // --- 1. length-indexed vector ---
    let empty: Vect<0> = [];
    let a: Vect<2> = [1, 2];
    let b: Vect<3> = [3, 4, 5];
    assert_eq!(vlen(&empty), 0, "[i64; 0]'s type says length 0");
    assert_eq!(vlen(&a), 2, "[i64; 2]'s type says length 2");
    assert_eq!(vlen(&b), 3, "[i64; 3]'s type says length 3");
    assert_eq!(head(&a), 1, "head([1, 2]) = 1");
    assert_eq!(head(&b), 3, "head([3, 4, 5]) = 3");

    let c: Vect<5> = append(&a, &b);
    assert_eq!(vlen(&c), vlen(&a) + vlen(&b), "append(a, b)'s type has length 2 + 3 = 5");
    assert_eq!(c, [1, 2, 3, 4, 5], "append([1, 2], [3, 4, 5]) reads [1, 2, 3, 4, 5]");

    // The run-time-length vector: the empty case is refused when it happens.
    let none: Vec<i64> = Vec::new();
    let seven: Vec<i64> = vec![7];
    assert_eq!(vec_head(&none), None, "run-time head of an empty Vec is refused");
    assert_eq!(vec_head(&seven), Some(7), "run-time head of [7] is allowed and = 7");

    // --- 2. Fin n ---
    assert!(Fin::<3>::new(-1).is_none(), "Fin<3>::new(-1) is refused");
    assert!(Fin::<3>::new(3).is_none(), "Fin<3>::new(3) is refused: 3 is not < 3");
    let mut accepted = 0;
    for i in -1..=3 {
        // Fin's N is inferred from b: index(&b, k) needs a Fin<3>.
        if let Some(k) = Fin::new(i) {
            accepted += 1;
            assert_eq!(fin::index(&b, k), 3 + i, "index([3, 4, 5], Fin<3>(i)) = 3 + i");
        }
    }
    assert_eq!(accepted, 3, "Fin<3>::new accepts exactly 0, 1, 2 out of -1..=3");
    assert!(Fin::<2>::new(2).is_none(), "Fin<2>::new(2) is refused: 2 is not < 2");
    assert_eq!(Fin::new(1).map(|k| fin::index(&a, k)), Some(2), "index([1, 2], Fin<2>(1)) = 2");

    // --- 3. refinement at the boundary ---
    let before = percent_checks();
    assert!(Percent::new(-1).is_none(), "percent(-1) is refused");
    assert!(Percent::new(101).is_none(), "percent(101) is refused");
    let (p0, p100, p25) = (Percent::new(0), Percent::new(100), Percent::new(25));
    assert_eq!(percent_checks() - before, 5, "5 constructions, 5 validations");
    match (p0, p100, p25) {
        (Some(p0), Some(p100), Some(p25)) => {
            assert_eq!(discount(200, p25), 150, "discount(200, 25%) = 150");
            assert_eq!(discount(200, p0), 200, "discount(200, 0%) = 200");
            assert_eq!(discount(200, p100), 0, "discount(200, 100%) = 0");
        }
        _ => panic!("percent refused one of 0, 100, 25"),
    }
    assert_eq!(percent_checks() - before, 5, "discount never re-validated: still 5 checks after 3 calls");

    // --- 4. Σ type ---
    assert!(SizedVec::new(3, vec![1, 2]).is_none(), "(3, [1, 2]) is refused: the length is 2");
    assert!(SizedVec::new(2, vec![1, 2, 3]).is_none(), "(2, [1, 2, 3]) is refused: the length is 3");
    match SizedVec::new(3, vec![1, 2, 3]) {
        Some(s) => {
            assert_eq!(s.n(), 3, "the pair's n is 3");
            assert_eq!(sized_sum(&s), 6, "sized_sum reads n = 3 elements: 1 + 2 + 3 = 6");
        }
        None => panic!("(3, [1, 2, 3]) was refused"),
    }
    // Where n can be a compile-time constant, the pair collapses into a
    // [i64; N]: TryFrom checks the run-time length once and hands back the
    // length-indexed type.
    let three: Vec<i64> = vec![1, 2, 3];
    assert!(<[i64; 3]>::try_from(&three[..2]).is_err(), "a slice of 2 is not a [i64; 3]");
    assert_eq!(<[i64; 3]>::try_from(&three[..]).ok(), Some([1, 2, 3]), "a slice of 3 becomes a [i64; 3]");

    // --- 5. the escape hatch ---
    assert!(Percent::new(150).is_none(), "the API refuses 150");
    // SAFETY: none. This is the bypass the section is about: Percent is
    // repr(transparent) over i64, so the bits fit, but 150 breaks its
    // invariant and everything downstream trusts it.
    let forged: Percent = unsafe { std::mem::transmute::<i64, Percent>(150) };
    assert_eq!(forged.get(), 150, "transmute makes a Percent of 150 anyway");
    assert_eq!(discount(200, forged), -100, "and discount trusts it: 200 - 300 = -100");

    println!("All dependent type examples passed.");
}
