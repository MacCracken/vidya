#![allow(dead_code)]
// Vidya — Memory Management in Rust
//
// Rust's ownership system eliminates use-after-free, double-free, and
// data races at compile time — without garbage collection. The key
// concepts: ownership, borrowing, lifetimes, and RAII (Drop).

use std::fmt::Write;

fn main() {
    // ── Ownership: each value has exactly one owner ────────────────
    let s1 = String::from("hello");
    let s2 = s1; // s1 is MOVED to s2 — s1 is no longer valid
    // println!("{s1}"); // ← compile error! s1 was moved
    assert_eq!(s2, "hello");

    // ── Borrowing: references don't take ownership ─────────────────
    let s = String::from("hello");
    let len = calculate_length(&s); // borrow s, don't move it
    assert_eq!(len, 5);
    assert_eq!(s, "hello"); // s is still valid — we only borrowed

    fn calculate_length(s: &str) -> usize {
        s.len()
    }

    // ── Mutable borrows: exclusive access ──────────────────────────
    let mut data = vec![1, 2, 3];
    add_element(&mut data); // exclusive mutable borrow
    assert_eq!(data, vec![1, 2, 3, 4]);

    fn add_element(v: &mut Vec<i32>) {
        v.push(4);
    }

    // ── Borrow rules enforced at compile time ──────────────────────
    // Rule 1: Many &T OR one &mut T — never both at the same time
    // Rule 2: References must not outlive the data they point to
    let r1 = &data;
    let r2 = &data; // multiple immutable borrows: OK
    assert_eq!(r1.len(), r2.len());
    // let r3 = &mut data; // ← compile error while r1, r2 alive

    // ── Stack vs Heap ──────────────────────────────────────────────
    let stack_array = [0u8; 64]; // 64 bytes on the stack — free allocation
    let heap_vec = vec![0u8; 64]; // 64 bytes on the heap — calls allocator
    assert_eq!(stack_array.len(), heap_vec.len());

    // ── Pre-allocation avoids reallocations ─────────────────────────
    let mut buf = Vec::with_capacity(100);
    let ptr_before = buf.as_ptr();
    for i in 0..100 {
        buf.push(i);
    }
    let ptr_after = buf.as_ptr();
    assert_eq!(ptr_before, ptr_after); // no reallocation — same memory

    // ── RAII: Drop runs automatically at end of scope ──────────────
    {
        let _resource = String::from("will be freed at end of block");
        // String::drop() runs here — memory freed automatically
    }

    // Custom Drop — a borrowed Cell<bool>, not a raw *mut bool: the lifetime
    // 'a makes the compiler prove the flag outlives the guard, with no unsafe.
    use std::cell::Cell;
    struct Guard<'a> {
        name: &'static str,
        dropped: &'a Cell<bool>,
    }
    impl Drop for Guard<'_> {
        fn drop(&mut self) {
            self.dropped.set(true);
        }
    }

    let was_dropped = Cell::new(false);
    {
        let _g = Guard { name: "test", dropped: &was_dropped };
    }
    assert!(was_dropped.get()); // Drop ran when _g went out of scope

    // ── Clone: explicit deep copy ──────────────────────────────────
    let original = vec![1, 2, 3];
    let copy = original.clone(); // explicit — Rust never DEEP-copies implicitly
    // (only `Copy` types — plain bits like i32 — are copied on assignment)
    assert_eq!(original, copy);
    // Both are independent — modifying one doesn't affect the other

    // ── Cow: borrow or own, decided at runtime ─────────────────────
    use std::borrow::Cow;

    fn process(input: &str) -> Cow<'_, str> {
        if input.contains("bad") {
            Cow::Owned(input.replace("bad", "good")) // allocates only when needed
        } else {
            Cow::Borrowed(input) // zero cost
        }
    }

    let clean = process("hello world");
    assert!(matches!(clean, Cow::Borrowed(_))); // no allocation

    let fixed = process("bad data");
    assert!(matches!(fixed, Cow::Owned(_))); // allocated replacement

    // ── Minimizing allocations in loops ─────────────────────────────
    let items = ["alpha", "beta", "gamma"];

    // If you need a Vec<String>, each element must own its heap buffer:
    // `format!` per item is one allocation each, and "reuse a buffer, then
    // push buf.clone()" allocates exactly as often (clone allocates).
    // Buffer reuse pays off when each formatted value is CONSUMED before
    // the next one is built — written out, hashed, compared:
    let mut string_buf = String::new();
    let mut total_len = 0;
    for item in &items {
        string_buf.clear(); // keeps the capacity: no allocation after the first item
        write!(string_buf, "{item}!").unwrap();
        total_len += string_buf.len(); // consume it here (e.g. write to a socket)
    }
    assert_eq!(total_len, "alpha!beta!gamma!".len());

    // ── Box: owned heap allocation ─────────────────────────────────
    let boxed: Box<[u8; 1024]> = Box::new([0u8; 1024]); // 1KB on heap
    assert_eq!(boxed.len(), 1024);
    // Freed automatically when boxed goes out of scope

    // ── Rc: shared ownership (single-threaded) ─────────────────────
    use std::rc::Rc;
    let shared = Rc::new(vec![1, 2, 3]);
    let also_shared = Rc::clone(&shared); // cheap reference count bump
    assert_eq!(Rc::strong_count(&shared), 2);
    assert_eq!(shared, also_shared); // same data

    println!("All memory management examples passed.");
}
