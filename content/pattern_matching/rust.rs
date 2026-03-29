// Vidya — Pattern Matching in Rust
//
// Rust's match is exhaustive, zero-cost, and deeply integrated with
// the type system. It destructures enums, tuples, structs, and
// references — replacing if/else chains with compiler-verified logic.

fn main() {
    // ── Basic match on enums ───────────────────────────────────────
    #[derive(Debug)]
    enum Direction {
        North,
        South,
        East,
        West,
    }

    let dir = Direction::North;
    let label = match dir {
        Direction::North => "up",
        Direction::South => "down",
        Direction::East => "right",
        Direction::West => "left",
    };
    assert_eq!(label, "up");

    // ── Destructuring enum variants with data ──────────────────────
    #[derive(Debug)]
    enum Shape {
        Circle(f64),
        Rectangle(f64, f64),
        Triangle { base: f64, height: f64 },
    }

    fn area(shape: &Shape) -> f64 {
        match shape {
            Shape::Circle(r) => std::f64::consts::PI * r * r,
            Shape::Rectangle(w, h) => w * h,
            Shape::Triangle { base, height } => 0.5 * base * height,
        }
    }

    assert!((area(&Shape::Circle(1.0)) - std::f64::consts::PI).abs() < 1e-10);
    assert_eq!(area(&Shape::Rectangle(3.0, 4.0)), 12.0);
    assert_eq!(area(&Shape::Triangle { base: 6.0, height: 4.0 }), 12.0);

    // ── Pattern guards: match + conditions ─────────────────────────
    fn classify(n: i32) -> &'static str {
        match n {
            n if n < 0 => "negative",
            0 => "zero",
            1..=10 => "small",
            _ => "large",
        }
    }

    assert_eq!(classify(-5), "negative");
    assert_eq!(classify(0), "zero");
    assert_eq!(classify(7), "small");
    assert_eq!(classify(100), "large");

    // ── if let: single-variant matching ────────────────────────────
    let maybe: Option<i32> = Some(42);

    if let Some(value) = maybe {
        assert_eq!(value, 42);
    }

    // let-else: bind or diverge
    let Some(value) = maybe else {
        panic!("expected Some");
    };
    assert_eq!(value, 42);

    // ── Tuple destructuring ────────────────────────────────────────
    let point = (3, 4);
    let (x, y) = point;
    assert_eq!(x, 3);
    assert_eq!(y, 4);

    let distance = match point {
        (0, 0) => 0.0,
        (x, y) => ((x * x + y * y) as f64).sqrt(),
    };
    assert!((distance - 5.0).abs() < 1e-10);

    // ── Struct destructuring ───────────────────────────────────────
    struct Config {
        host: String,
        port: u16,
        debug: bool,
    }

    let config = Config {
        host: "localhost".into(),
        port: 8080,
        debug: true,
    };

    let Config { host, port, debug } = &config;
    assert_eq!(host, "localhost");
    assert_eq!(*port, 8080);
    assert!(*debug);

    // Partial destructuring with ..
    let Config { port, .. } = &config;
    assert_eq!(*port, 8080);

    // ── Nested pattern matching ────────────────────────────────────
    let data: Option<Result<i32, &str>> = Some(Ok(42));

    match data {
        Some(Ok(n)) if n > 0 => assert_eq!(n, 42),
        Some(Ok(_)) => panic!("expected positive"),
        Some(Err(e)) => panic!("unexpected error: {e}"),
        None => panic!("expected Some"),
    }

    // ── Or-patterns: multiple variants, one arm ────────────────────
    let ch = 'a';
    let is_vowel = matches!(ch, 'a' | 'e' | 'i' | 'o' | 'u');
    assert!(is_vowel);

    // ── Matching references ────────────────────────────────────────
    let values = vec![1, 2, 3];
    let first = values.iter().find(|&&x| x == 1);
    match first {
        Some(&val) => assert_eq!(val, 1), // dereference in pattern
        None => panic!("expected to find 1"),
    }

    // ── Binding with @ ─────────────────────────────────────────────
    let msg = match 42 {
        n @ 1..=50 => format!("{n} is small"),
        n @ 51..=100 => format!("{n} is medium"),
        n => format!("{n} is large"),
    };
    assert_eq!(msg, "42 is small");

    println!("All pattern matching examples passed.");
}
