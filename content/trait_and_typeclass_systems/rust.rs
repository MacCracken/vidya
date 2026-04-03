// Vidya — Trait and Typeclass Systems in Rust
//
// Demonstrates the language-level mechanics of Rust's trait system:
// monomorphization (static dispatch) vs vtable (dynamic dispatch),
// object safety constraints, associated types, blanket impls, and
// the performance difference between dispatch strategies.
//
// This is a compiler-implementer's perspective: what happens at the
// machine level when you write `impl Trait` vs `dyn Trait`.

use std::fmt;
use std::time::Instant;

fn main() {
    // ── Static dispatch: monomorphization ──────────────────────────
    // The compiler generates a separate copy of `sum_values` for each
    // concrete type. Each copy is fully specialized and inlinable.

    trait Value {
        fn amount(&self) -> f64;
    }

    #[derive(Clone, Copy)]
    struct Dollars(f64);
    impl Value for Dollars {
        fn amount(&self) -> f64 {
            self.0
        }
    }

    #[derive(Clone, Copy)]
    struct Euros(f64);
    impl Value for Euros {
        fn amount(&self) -> f64 {
            self.0 * 1.08 // convert to dollars
        }
    }

    // Static dispatch — compiler monomorphizes this for each T
    fn sum_values_static<T: Value>(items: &[T]) -> f64 {
        let mut total = 0.0;
        for item in items {
            total += item.amount();
        }
        total
    }

    let dollars: Vec<Dollars> = (0..1000).map(|i| Dollars(i as f64)).collect();
    let euros: Vec<Euros> = (0..1000).map(|i| Euros(i as f64)).collect();

    let sum_d = sum_values_static(&dollars);
    let sum_e = sum_values_static(&euros);
    assert!((sum_d - 499_500.0).abs() < 0.01);
    assert!((sum_e - 499_500.0 * 1.08).abs() < 1.0);

    // ── Dynamic dispatch: vtable indirection ──────────────────────
    // A dyn Trait pointer is a fat pointer: (data_ptr, vtable_ptr).
    // Each method call loads the function pointer from the vtable
    // and does an indirect call — no inlining possible.

    fn sum_values_dynamic(items: &[Box<dyn Value>]) -> f64 {
        let mut total = 0.0;
        for item in items {
            total += item.amount(); // vtable lookup on each call
        }
        total
    }

    let mixed: Vec<Box<dyn Value>> = vec![
        Box::new(Dollars(100.0)),
        Box::new(Euros(100.0)),
        Box::new(Dollars(50.0)),
    ];
    let sum_mixed = sum_values_dynamic(&mixed);
    assert!((sum_mixed - (100.0 + 108.0 + 50.0)).abs() < 0.01);

    // ── Performance comparison ─────────────────────────────────────
    // Monomorphized dispatch allows the compiler to inline amount()
    // and potentially vectorize the loop. Vtable dispatch cannot.

    let boxed_dollars: Vec<Box<dyn Value>> =
        (0..10_000).map(|i| Box::new(Dollars(i as f64)) as Box<dyn Value>).collect();
    let plain_dollars: Vec<Dollars> = (0..10_000).map(|i| Dollars(i as f64)).collect();

    const ITERS: u32 = 1000;

    // Warm up
    for _ in 0..100 {
        std::hint::black_box(sum_values_static(std::hint::black_box(&plain_dollars)));
        std::hint::black_box(sum_values_dynamic(std::hint::black_box(&boxed_dollars)));
    }

    let start = Instant::now();
    for _ in 0..ITERS {
        std::hint::black_box(sum_values_static(std::hint::black_box(&plain_dollars)));
    }
    let static_time = start.elapsed();

    let start = Instant::now();
    for _ in 0..ITERS {
        std::hint::black_box(sum_values_dynamic(std::hint::black_box(&boxed_dollars)));
    }
    let dynamic_time = start.elapsed();

    println!(
        "Static dispatch:  {:?} ({} iterations over 10K items)",
        static_time, ITERS
    );
    println!(
        "Dynamic dispatch: {:?} ({} iterations over 10K items)",
        dynamic_time, ITERS
    );
    println!(
        "Ratio: {:.1}x",
        dynamic_time.as_nanos() as f64 / static_time.as_nanos().max(1) as f64
    );

    // ── Object safety ──────────────────────────────────────────────
    // A trait is object-safe only if all methods can go through a vtable.
    //
    // NOT object-safe (cannot be used as dyn):
    //   - Methods returning Self (vtable doesn't know concrete size)
    //   - Generic methods (infinite vtable entries)
    //   - Trait requires Sized
    //
    // Object-safe:
    //   - Methods taking &self, &mut self, or Box<Self>
    //   - No generic parameters on methods
    //   - Self only behind a pointer (Box<Self>, &Self)

    trait ObjectSafe {
        fn describe(&self) -> String;
        fn boxed_clone(&self) -> Box<dyn ObjectSafe>; // Self behind pointer: OK
    }

    // NOT object-safe — commented out to show the pattern:
    // trait NotObjectSafe {
    //     fn clone_self(&self) -> Self;       // returns Self by value
    //     fn convert<U>(&self) -> U;          // generic method
    // }

    struct Widget {
        name: String,
    }

    impl ObjectSafe for Widget {
        fn describe(&self) -> String {
            format!("Widget({})", self.name)
        }
        fn boxed_clone(&self) -> Box<dyn ObjectSafe> {
            Box::new(Widget {
                name: self.name.clone(),
            })
        }
    }

    let w: Box<dyn ObjectSafe> = Box::new(Widget {
        name: "gear".into(),
    });
    let w2 = w.boxed_clone();
    assert_eq!(w.describe(), "Widget(gear)");
    assert_eq!(w2.describe(), "Widget(gear)");

    // ── Associated types vs type parameters ────────────────────────
    // Associated type: one implementation per type (the implementor chooses)
    // Type parameter: multiple implementations possible (the caller chooses)

    // Associated type — Vec<i32> implements Iterator exactly once
    trait Source {
        type Item;
        fn next_item(&mut self) -> Option<Self::Item>;
    }

    struct Counter {
        n: u32,
        max: u32,
    }

    impl Source for Counter {
        type Item = u32; // the implementor fixes the type
        fn next_item(&mut self) -> Option<u32> {
            if self.n < self.max {
                self.n += 1;
                Some(self.n)
            } else {
                None
            }
        }
    }

    let mut c = Counter { n: 0, max: 3 };
    assert_eq!(c.next_item(), Some(1));
    assert_eq!(c.next_item(), Some(2));
    assert_eq!(c.next_item(), Some(3));
    assert_eq!(c.next_item(), None);

    // Type parameter — same type can convert to multiple targets
    trait ConvertTo<T> {
        fn convert(&self) -> T;
    }

    impl ConvertTo<f64> for Dollars {
        fn convert(&self) -> f64 {
            self.0
        }
    }

    impl ConvertTo<String> for Dollars {
        fn convert(&self) -> String {
            format!("${:.2}", self.0)
        }
    }

    let d = Dollars(42.50);
    let as_float: f64 = d.convert();
    let as_string: String = d.convert();
    assert!((as_float - 42.50).abs() < 0.01);
    assert_eq!(as_string, "$42.50");

    // ── Blanket impls ──────────────────────────────────────────────
    // A blanket impl covers all types satisfying a bound.
    // impl<T: Display> ToString for T — any Display type gets ToString.

    trait Describe {
        fn describe_self(&self) -> String;
    }

    // Blanket impl: anything that implements fmt::Display gets Describe
    impl<T: fmt::Display> Describe for T {
        fn describe_self(&self) -> String {
            format!("Value: {}", self)
        }
    }

    assert_eq!(42.describe_self(), "Value: 42");
    assert_eq!("hello".describe_self(), "Value: hello");

    // ── Supertraits ────────────────────────────────────────────────
    // trait Error: Display + Debug means the vtable for dyn Error
    // includes methods from Display and Debug.

    trait Reportable: fmt::Display + fmt::Debug {
        fn code(&self) -> u32;
    }

    #[derive(Debug)]
    struct AppError {
        msg: String,
        code: u32,
    }

    impl fmt::Display for AppError {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            write!(f, "E{}: {}", self.code, self.msg)
        }
    }

    impl Reportable for AppError {
        fn code(&self) -> u32 {
            self.code
        }
    }

    // dyn Reportable can call Display, Debug, and Reportable methods
    fn log_error(err: &dyn Reportable) -> String {
        format!("ERROR [{}] {} (debug: {:?})", err.code(), err, err)
    }

    let err = AppError {
        msg: "not found".into(),
        code: 404,
    };
    let logged = log_error(&err);
    assert!(logged.contains("404"));
    assert!(logged.contains("E404: not found"));
    assert!(logged.contains("debug:"));

    // ── Type erasure at API boundaries ─────────────────────────────
    // Use dyn Trait at boundaries (handler registration, plugin systems)
    // where the concrete type varies and call frequency is low.

    trait Handler {
        fn handle(&self, input: &str) -> String;
    }

    struct EchoHandler;
    impl Handler for EchoHandler {
        fn handle(&self, input: &str) -> String {
            format!("echo: {input}")
        }
    }

    struct UpperHandler;
    impl Handler for UpperHandler {
        fn handle(&self, input: &str) -> String {
            input.to_uppercase()
        }
    }

    // Registry uses type erasure — handlers registered once, called per request
    let handlers: Vec<Box<dyn Handler>> = vec![
        Box::new(EchoHandler),
        Box::new(UpperHandler),
    ];

    assert_eq!(handlers[0].handle("test"), "echo: test");
    assert_eq!(handlers[1].handle("test"), "TEST");

    println!("All trait and typeclass system examples passed.");
}
