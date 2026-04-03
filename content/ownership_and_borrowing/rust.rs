// Ownership and Borrowing — Rust Implementation
//
// Demonstrates ownership and borrowing from a language-design perspective:
//   1. Move semantics — affine type behavior, values used at most once
//   2. Borrowing rules — shared (&T) vs exclusive (&mut T)
//   3. Lifetime annotations — region-based constraints
//   4. Reborrowing — implicit re-lending of mutable references
//   5. A simple borrow checker simulation — tracks loans and detects conflicts
//
// This is not a Rust tutorial. It shows how the ownership model works
// internally, including a miniature borrow checker that demonstrates
// the dataflow analysis a real compiler performs.

use std::collections::HashMap;
use std::fmt;

// ── Move Semantics ───────────────────────────────────────────────────────

/// Demonstrates that moves are affine: the source is consumed.
fn demonstrate_move_semantics() {
    println!("=== Move Semantics (Affine Types) ===\n");

    // String is non-Copy: assignment moves ownership.
    let s1 = String::from("owned");
    let s2 = s1; // s1 is now uninitialized (compile-time concept)
    // Using s1 here would be a compile error: "value used after move"
    println!("  s2 after move: {s2:?}");

    // Integers are Copy: assignment duplicates the value.
    let x: i32 = 42;
    let y = x; // x is still valid — bitwise copy
    println!("  x after copy: {x}, y: {y}");

    // Move into a function consumes the argument.
    fn consume(s: String) -> usize {
        s.len()
    }
    let s3 = String::from("consumed");
    let len = consume(s3);
    // s3 is dead here — the function took ownership.
    println!("  consumed string length: {len}");

    // Conditional move: requires a drop flag at runtime.
    let s4 = String::from("maybe moved");
    let condition = len > 3;
    let s5;
    if condition {
        s5 = s4; // s4 is moved — drop flag set
    } else {
        s5 = String::from("fallback");
        // s4 is still live here — drop flag unset, s4 will be dropped at scope end
    }
    println!("  conditional result: {s5}");
    println!();
}

// ── Borrowing Rules ──────────────────────────────────────────────────────

/// Demonstrates the two borrowing rules:
///   1. Any number of &T (shared borrows), OR
///   2. Exactly one &mut T (exclusive borrow)
///   Never both simultaneously.
fn demonstrate_borrowing() {
    println!("=== Borrowing Rules ===\n");

    let mut data = vec![1, 2, 3, 4, 5];

    // Multiple shared borrows coexist.
    let r1 = &data;
    let r2 = &data;
    println!("  shared borrows: {r1:?} and {r2:?}");
    // r1 and r2 are dead after this point (NLL).

    // Exclusive borrow — no other borrows can be live.
    let r3 = &mut data;
    r3.push(6);
    println!("  after exclusive borrow push: {r3:?}");
    // r3 is dead here (NLL), so we can use data again.

    // Reborrowing: passing &mut to a function doesn't consume it.
    fn add_element(v: &mut Vec<i32>, val: i32) {
        v.push(val);
    }
    let r4 = &mut data;
    add_element(r4, 7); // implicit reborrow: &mut *r4
    add_element(r4, 8); // r4 is still usable — the reborrow ended
    println!("  after reborrows: {r4:?}");
    println!();
}

// ── Lifetime Annotations ─────────────────────────────────────────────────

/// Returns a reference to the longer of two string slices.
/// The lifetime 'a is a region: both inputs and the output share it.
/// The compiler constrains 'a to the intersection of the callers' lifetimes.
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() >= y.len() { x } else { y }
}

/// A struct that borrows data — the lifetime annotation is a region constraint.
/// `Excerpt<'a>` is valid only while the borrowed data lives.
struct Excerpt<'a> {
    text: &'a str,
    start: usize,
    end: usize,
}

impl<'a> Excerpt<'a> {
    fn new(source: &'a str, start: usize, end: usize) -> Self {
        Self {
            text: &source[start..end],
            start,
            end,
        }
    }

    /// Lifetime elision: &self → output gets lifetime of self.
    fn content(&self) -> &str {
        self.text
    }
}

impl fmt::Display for Excerpt<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{}..{}]: {:?}", self.start, self.end, self.text)
    }
}

fn demonstrate_lifetimes() {
    println!("=== Lifetime Annotations (Region Constraints) ===\n");

    let string1 = String::from("long string");
    let result;
    {
        let string2 = String::from("short");
        // 'a is constrained to the shorter of string1 and string2's lifetimes.
        // Under NLL, that means 'a ends when `result` is last used.
        result = longest(string1.as_str(), string2.as_str());
        println!("  longest: {result:?}");
    }
    // result cannot be used here — string2 is dropped, and 'a was
    // constrained to string2's lifetime.

    let source = String::from("The quick brown fox jumps over the lazy dog");
    let excerpt = Excerpt::new(&source, 4, 19);
    println!("  excerpt: {excerpt}");
    println!("  content: {:?}", excerpt.content());
    println!();
}

// ── Borrow Checker Simulation ────────────────────────────────────────────
//
// A miniature borrow checker that demonstrates the core algorithm:
//   - Track active loans (borrows) at each program point
//   - Check that no two conflicting loans are active simultaneously
//   - A conflict occurs when two loans alias and at least one is mutable

/// Represents a borrow kind — shared or mutable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BorrowKind {
    Shared,
    Mutable,
}

impl fmt::Display for BorrowKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BorrowKind::Shared => write!(f, "&"),
            BorrowKind::Mutable => write!(f, "&mut"),
        }
    }
}

/// A loan: someone borrowed a place (variable) with a given kind.
#[derive(Debug, Clone)]
struct Loan {
    id: usize,
    place: String,   // the variable being borrowed
    kind: BorrowKind,
    origin: String,   // source location / description
}

impl fmt::Display for Loan {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "L{}: {} {} ({})", self.id, self.kind, self.place, self.origin)
    }
}

/// A conflict detected by the checker.
#[derive(Debug)]
struct Conflict {
    existing: Loan,
    new_loan: Loan,
    reason: String,
}

impl fmt::Display for Conflict {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "CONFLICT: {} clashes with {} — {}",
            self.new_loan, self.existing, self.reason
        )
    }
}

/// Miniature borrow checker — tracks active loans and detects conflicts.
///
/// Real borrow checkers operate on a CFG (control flow graph) and compute
/// loan liveness via dataflow. This simplified version operates on a
/// linear sequence of actions.
struct MiniChecker {
    loans: HashMap<usize, Loan>,
    next_id: usize,
    conflicts: Vec<Conflict>,
}

impl MiniChecker {
    fn new() -> Self {
        Self {
            loans: HashMap::new(),
            next_id: 0,
            conflicts: Vec::new(),
        }
    }

    /// Create a new borrow. Checks for conflicts with active loans.
    fn borrow(&mut self, place: &str, kind: BorrowKind, origin: &str) -> usize {
        let id = self.next_id;
        self.next_id += 1;

        let new_loan = Loan {
            id,
            place: place.to_string(),
            kind,
            origin: origin.to_string(),
        };

        // Check for conflicts: iterate all active loans on the same place.
        for existing in self.loans.values() {
            if existing.place != place {
                continue; // different places don't conflict
            }

            let conflicts = match (existing.kind, kind) {
                (BorrowKind::Shared, BorrowKind::Shared) => false,   // many readers OK
                (BorrowKind::Shared, BorrowKind::Mutable) => true,   // reader + writer
                (BorrowKind::Mutable, BorrowKind::Shared) => true,   // writer + reader
                (BorrowKind::Mutable, BorrowKind::Mutable) => true,  // two writers
            };

            if conflicts {
                let reason = match (existing.kind, kind) {
                    (BorrowKind::Mutable, BorrowKind::Mutable) => {
                        "cannot have two mutable borrows of the same place".to_string()
                    }
                    _ => {
                        format!(
                            "cannot have {} and {} borrows of the same place simultaneously",
                            existing.kind, kind
                        )
                    }
                };

                self.conflicts.push(Conflict {
                    existing: existing.clone(),
                    new_loan: new_loan.clone(),
                    reason,
                });
            }
        }

        self.loans.insert(id, new_loan);
        id
    }

    /// End a borrow — the loan is no longer active (NLL: borrow dies at last use).
    fn release(&mut self, id: usize) {
        self.loans.remove(&id);
    }

    fn active_loans(&self) -> Vec<&Loan> {
        let mut loans: Vec<_> = self.loans.values().collect();
        loans.sort_by_key(|l| l.id);
        loans
    }

    fn has_conflicts(&self) -> bool {
        !self.conflicts.is_empty()
    }
}

fn demonstrate_borrow_checker_simulation() {
    println!("=== Borrow Checker Simulation ===\n");

    // Scenario 1: Valid — multiple shared borrows
    {
        println!("  --- Scenario 1: Multiple shared borrows (should pass) ---");
        let mut checker = MiniChecker::new();

        let l1 = checker.borrow("data", BorrowKind::Shared, "line 10");
        let l2 = checker.borrow("data", BorrowKind::Shared, "line 11");
        println!("    Active: {:?}", checker.active_loans().iter().map(|l| l.to_string()).collect::<Vec<_>>());
        println!("    Conflicts: {}", checker.has_conflicts());

        checker.release(l1);
        checker.release(l2);
        println!();
    }

    // Scenario 2: Conflict — shared + mutable borrow simultaneously
    {
        println!("  --- Scenario 2: Shared + mutable borrow (should fail) ---");
        let mut checker = MiniChecker::new();

        let l1 = checker.borrow("vec", BorrowKind::Shared, "line 20: let r = &vec");
        let _l2 = checker.borrow("vec", BorrowKind::Mutable, "line 21: vec.push(x)");

        for conflict in &checker.conflicts {
            println!("    {conflict}");
        }

        // With NLL: if the shared borrow is dead before the mutable one starts, no conflict.
        checker.release(l1);
        println!("    After releasing shared borrow: {} active loans", checker.loans.len());
        println!();
    }

    // Scenario 3: NLL-style — release before conflicting borrow
    {
        println!("  --- Scenario 3: NLL-style sequential borrows (should pass) ---");
        let mut checker = MiniChecker::new();

        let l1 = checker.borrow("data", BorrowKind::Shared, "line 30: let r = &data");
        println!("    Borrow created: {}", checker.loans[&l1]);

        // NLL: the shared borrow dies at its last use.
        checker.release(l1);
        println!("    Shared borrow released (last use passed)");

        let l2 = checker.borrow("data", BorrowKind::Mutable, "line 32: data.push(x)");
        println!("    Mutable borrow created: {}", checker.loans[&l2]);
        println!("    Conflicts: {}", checker.has_conflicts());

        checker.release(l2);
        println!();
    }

    // Scenario 4: Two mutable borrows of different places — no conflict
    {
        println!("  --- Scenario 4: Disjoint mutable borrows (should pass) ---");
        let mut checker = MiniChecker::new();

        let _l1 = checker.borrow("field_a", BorrowKind::Mutable, "line 40");
        let _l2 = checker.borrow("field_b", BorrowKind::Mutable, "line 41");

        println!("    Active: {:?}", checker.active_loans().iter().map(|l| l.to_string()).collect::<Vec<_>>());
        println!("    Conflicts: {} (different places don't alias)", checker.has_conflicts());
        println!();
    }

    // Summary
    println!("  The real borrow checker does this on a CFG with dataflow analysis.");
    println!("  Each 'release' corresponds to the last use point of a borrow (NLL).");
    println!("  Polonius extends this with origin tracking for even more precision.");
    println!();
}

// ── Drop Order ───────────────────────────────────────────────────────────

/// Demonstrates Rust's deterministic drop order.
struct DropTracer {
    name: &'static str,
}

impl Drop for DropTracer {
    fn drop(&mut self) {
        println!("    dropping: {}", self.name);
    }
}

fn demonstrate_drop_order() {
    println!("=== Deterministic Drop Order ===\n");
    println!("  Locals drop in reverse declaration order:");

    let _a = DropTracer { name: "first declared (dropped last)" };
    let _b = DropTracer { name: "second declared (dropped second)" };
    let _c = DropTracer { name: "third declared (dropped first)" };

    // _c drops first, then _b, then _a — reverse order.
    // This matters when destructors have dependencies.
    println!("  (drops happen at end of scope)\n");
}

fn main() {
    demonstrate_move_semantics();
    demonstrate_borrowing();
    demonstrate_lifetimes();
    demonstrate_borrow_checker_simulation();
    demonstrate_drop_order();
}
