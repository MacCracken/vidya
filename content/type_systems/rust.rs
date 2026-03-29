// Vidya — Type Systems in Rust
//
// Rust's type system prevents bugs at compile time through ownership,
// generics, traits, and zero-cost abstractions. Generics are monomorphized
// (specialized per type), traits define shared behavior, and newtypes
// add semantic safety with zero runtime cost.

use std::fmt;

fn main() {
    // ── Newtypes: semantic safety at zero cost ─────────────────────
    #[derive(Debug, Clone, Copy, PartialEq)]
    struct Meters(f64);

    #[derive(Debug, Clone, Copy, PartialEq)]
    struct Seconds(f64);

    // Can't accidentally mix Meters and Seconds
    fn speed(distance: Meters, time: Seconds) -> f64 {
        distance.0 / time.0
    }

    let d = Meters(100.0);
    let t = Seconds(9.58);
    // speed(t, d); // ← compile error! wrong types
    let v = speed(d, t);
    assert!(v > 10.0);

    // ── Enums: make illegal states unrepresentable ─────────────────
    #[derive(Debug)]
    enum ConnectionState {
        Disconnected,
        Connecting { attempt: u32 },
        Connected { peer: String },
    }

    // The type system ensures you can't access `peer` when disconnected
    fn describe(state: &ConnectionState) -> String {
        match state {
            ConnectionState::Disconnected => "not connected".into(),
            ConnectionState::Connecting { attempt } => format!("attempt #{attempt}"),
            ConnectionState::Connected { peer } => format!("connected to {peer}"),
        }
    }

    let state = ConnectionState::Connected { peer: "server".into() };
    assert_eq!(describe(&state), "connected to server");

    // ── Generics: code reuse without runtime cost ──────────────────
    fn largest<T: PartialOrd>(list: &[T]) -> &T {
        let mut max = &list[0];
        for item in &list[1..] {
            if item > max {
                max = item;
            }
        }
        max
    }

    assert_eq!(largest(&[1, 5, 3, 2, 4]), &5);
    assert_eq!(largest(&["hello", "world", "abc"]), &"world");

    // ── Traits: shared behavior ────────────────────────────────────
    trait Summarize {
        fn summary(&self) -> String;

        // Default implementation — can be overridden
        fn brief(&self) -> String {
            format!("{}...", &self.summary()[..20.min(self.summary().len())])
        }
    }

    struct Article {
        title: String,
        body: String,
    }

    impl Summarize for Article {
        fn summary(&self) -> String {
            format!("{}: {}", self.title, &self.body[..50.min(self.body.len())])
        }
    }

    let article = Article {
        title: "Rust Types".into(),
        body: "Rust's type system is one of its greatest strengths.".into(),
    };
    assert!(article.summary().starts_with("Rust Types:"));

    // ── impl Trait: simple generic arguments ───────────────────────
    fn print_summary(item: &impl Summarize) -> String {
        item.summary()
    }

    let s = print_summary(&article);
    assert!(!s.is_empty());

    // ── Trait bounds with where clauses ─────────────────────────────
    fn serialize_pair<A, B>(a: &A, b: &B) -> String
    where
        A: fmt::Display,
        B: fmt::Debug,
    {
        format!("{a} | {b:?}")
    }

    let result = serialize_pair(&42, &"hello");
    assert_eq!(result, "42 | \"hello\"");

    // ── Associated types ───────────────────────────────────────────
    trait Container {
        type Item;
        fn first(&self) -> Option<&Self::Item>;
    }

    struct Stack<T> {
        items: Vec<T>,
    }

    impl<T> Container for Stack<T> {
        type Item = T;
        fn first(&self) -> Option<&T> {
            self.items.first()
        }
    }

    let stack = Stack { items: vec![1, 2, 3] };
    assert_eq!(stack.first(), Some(&1));

    // ── From/Into for type conversions ──────────────────────────────
    impl From<f64> for Meters {
        fn from(val: f64) -> Self {
            Meters(val)
        }
    }

    let m: Meters = 42.0.into(); // uses From<f64>
    assert_eq!(m, Meters(42.0));

    // ── Trait objects: dynamic dispatch when needed ─────────────────
    let items: Vec<Box<dyn Summarize>> = vec![
        Box::new(Article {
            title: "One".into(),
            body: "First article content here.".into(),
        }),
        Box::new(Article {
            title: "Two".into(),
            body: "Second article content here.".into(),
        }),
    ];

    for item in &items {
        assert!(!item.summary().is_empty());
    }

    // ── Type aliases for complex types ─────────────────────────────
    type ParseResult<T> = Result<T, Box<dyn std::error::Error>>;

    fn parse_number(s: &str) -> ParseResult<i32> {
        Ok(s.trim().parse()?)
    }

    assert_eq!(parse_number("42").unwrap(), 42);

    // ── Phantom types: compile-time state machines ─────────────────
    use std::marker::PhantomData;

    struct Locked;
    struct Unlocked;

    struct Door<State> {
        _state: PhantomData<State>,
    }

    impl Door<Locked> {
        fn unlock(self) -> Door<Unlocked> {
            Door { _state: PhantomData }
        }
    }

    impl Door<Unlocked> {
        fn lock(self) -> Door<Locked> {
            Door { _state: PhantomData }
        }

        fn open(&self) -> &'static str {
            "door is open"
        }
    }

    let door: Door<Locked> = Door { _state: PhantomData };
    // door.open(); // ← compile error! can't open a locked door
    let door = door.unlock();
    assert_eq!(door.open(), "door is open");
    let _door = door.lock(); // back to locked

    println!("All type system examples passed.");
}
