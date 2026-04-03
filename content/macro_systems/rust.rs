// Macro Systems — Rust Implementation
//
// Demonstrates Rust's macro system from a language-design perspective:
//   - Declarative macros (macro_rules!) with pattern matching
//   - Repetition patterns ($(...)*) for variadic arguments
//   - Fragment specifiers (expr, ty, ident, tt, literal)
//   - Hygienic name binding (macro-introduced names don't leak)
//   - Recursive macro expansion with base cases
//   - Compile-time code generation through macro expansion
//
// This is NOT a usage tutorial — it shows the design concepts that
// make Rust's macro system work: hygiene, token trees, pattern
// matching, and controlled expansion.

// ── Declarative Macros: Pattern Matching on Syntax ───────────────────────

/// A macro that demonstrates basic pattern matching with multiple arms.
/// Each arm matches a different syntactic pattern — this is macro-by-example:
/// the input pattern determines which template to stamp out.
macro_rules! describe_type {
    // Match a signed integer type
    (signed $t:ty) => {
        concat!("signed integer type: ", stringify!($t))
    };
    // Match an unsigned integer type
    (unsigned $t:ty) => {
        concat!("unsigned integer type: ", stringify!($t))
    };
    // Match any single type (fallback arm)
    ($t:ty) => {
        concat!("type: ", stringify!($t))
    };
}

// ── Repetition Patterns: Variadic Macros ─────────────────────────────────

/// Demonstrates the $(...)* repetition operator. The macro accepts zero or
/// more key:value pairs and builds a Vec of formatted strings.
/// This is how vec![], println!(), and most standard macros handle
/// variable-length input.
macro_rules! make_pairs {
    // Match zero or more `key => value` pairs separated by commas
    ( $( $key:expr => $value:expr ),* $(,)? ) => {
        {
            let mut pairs = Vec::new();
            $(
                pairs.push(format!("{} => {}", $key, $value));
            )*
            pairs
        }
    };
}

/// Demonstrates nested repetition: $( $( ... )* )* handles a list of lists.
/// This pattern is used in real code for matrix literals, table definitions,
/// and multi-dimensional data.
macro_rules! nested_list {
    ( $( [ $( $item:expr ),* $(,)? ] ),* $(,)? ) => {
        vec![ $( vec![ $( $item ),* ] ),* ]
    };
}

// ── Fragment Specifiers: What Macros Can Match ───────────────────────────

/// Shows different fragment specifiers and what they capture.
/// Fragment specifiers are the type system of macro patterns — they
/// constrain what tokens can bind to a metavariable.
macro_rules! fragment_demo {
    // ident: matches an identifier (variable name, function name, etc.)
    (ident $name:ident) => {
        {
            let $name = 42;
            format!("bound identifier '{}' to {}", stringify!($name), $name)
        }
    };
    // expr: matches any Rust expression
    (expr $e:expr) => {
        format!("expression '{}' evaluates to {}", stringify!($e), $e)
    };
    // literal: matches a literal value only
    (literal $lit:literal) => {
        format!("literal value: {}", $lit)
    };
    // tt: matches a single token tree (any token or balanced group)
    // This is the most permissive specifier — the "any" type of macros.
    (tt $($tok:tt)*) => {
        format!("token trees: '{}'", stringify!($($tok)*))
    };
}

// ── Hygiene Demonstration ────────────────────────────────────────────────

/// This macro introduces a local variable `result` inside its expansion.
/// Due to hygiene, this `result` CANNOT collide with a `result` variable
/// at the call site — they have different syntax contexts.
macro_rules! hygienic_compute {
    ($x:expr, $y:expr) => {
        {
            // This 'result' lives in the macro's syntax context.
            // It is invisible to the caller's scope.
            let result = $x * 2 + $y;
            result
        }
    };
}

// ── Recursive Macros with Base Cases ─────────────────────────────────────

/// Counts the number of expression arguments at compile time using
/// recursive expansion. Each recursion peels off one argument.
/// Without the base case (the empty pattern), this would hit the
/// recursion limit.
macro_rules! count_exprs {
    // Base case: no arguments → 0
    () => { 0usize };
    // Single argument → 1
    ($single:expr) => { 1usize };
    // Multiple: count first as 1, recurse on the rest
    ($first:expr, $( $rest:expr ),+ ) => {
        1usize + count_exprs!( $( $rest ),+ )
    };
}

/// Recursive macro that generates a type-safe builder pattern.
/// Demonstrates how macros can generate struct definitions and impl blocks.
macro_rules! make_builder {
    // Entry point: struct name + fields
    ($name:ident { $( $field:ident : $ftype:ty ),* $(,)? }) => {
        // Generate the struct
        #[derive(Debug, Default)]
        struct $name {
            $( $field: Option<$ftype>, )*
        }

        // Generate builder methods — one per field
        impl $name {
            fn new() -> Self {
                Self::default()
            }

            $(
                fn $field(mut self, value: $ftype) -> Self {
                    self.$field = Some(value);
                    self
                }
            )*

            fn describe(&self) -> String {
                let mut parts = Vec::new();
                $(
                    match &self.$field {
                        Some(v) => parts.push(format!("{}: {:?}", stringify!($field), v)),
                        None => parts.push(format!("{}: <unset>", stringify!($field))),
                    }
                )*
                parts.join(", ")
            }
        }
    };
}

// ── Expansion Order and Composability ────────────────────────────────────

/// Demonstrates that macros can invoke other macros. Expansion proceeds
/// outside-in: the outer macro expands first, producing code that
/// contains inner macro invocations, which are then expanded.
macro_rules! outer {
    ($($vals:expr),*) => {
        format!("outer produced {} items: {:?}",
            count_exprs!($($vals),*),
            make_pairs!($($vals => stringify!($vals)),*)
        )
    };
}

// ── Token Tree Munching: Parsing Custom Syntax ───────────────────────────

/// Token tree munching: consume tokens one pattern at a time, accumulating
/// results. This is the fundamental technique for parsing custom DSLs
/// in declarative macros. Each arm matches a prefix pattern and recurses
/// on the remaining tokens.
macro_rules! simple_math {
    // Base case: just a number
    (= $result:expr) => { $result };
    // Addition: peel off `expr + `, compute, recurse
    ($a:literal + $($rest:tt)*) => {
        simple_math!(= $a + simple_math!($($rest)*))
    };
    // Single literal (another base case)
    ($a:literal) => { $a };
}

fn main() {
    println!("Macro Systems — Rust Demonstration");
    println!("===================================\n");

    // ── Pattern matching ──────────────────────────────────────────────
    println!("1. Pattern Matching in Declarative Macros:");
    println!("   {}", describe_type!(signed i32));
    println!("   {}", describe_type!(unsigned u64));
    println!("   {}", describe_type!(String));
    println!();

    // ── Repetition patterns ───────────────────────────────────────────
    println!("2. Repetition Patterns (variadic macros):");
    let pairs = make_pairs! {
        "name" => "vidya",
        "type" => "library",
        "lang" => "rust",
    };
    for p in &pairs {
        println!("   {}", p);
    }
    println!();

    println!("3. Nested Repetition:");
    let matrix = nested_list![
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
    ];
    for (i, row) in matrix.iter().enumerate() {
        println!("   row {}: {:?}", i, row);
    }
    println!();

    // ── Fragment specifiers ───────────────────────────────────────────
    println!("4. Fragment Specifiers:");
    println!("   {}", fragment_demo!(ident my_var));
    println!("   {}", fragment_demo!(expr 2 + 2));
    println!("   {}", fragment_demo!(literal 3.14));
    println!("   {}", fragment_demo!(tt { anything [goes] here }));
    println!();

    // ── Hygiene ───────────────────────────────────────────────────────
    println!("5. Hygiene (no variable capture):");
    let result = 999; // This 'result' must survive the macro expansion
    let computed = hygienic_compute!(10, 5);
    println!("   Caller's 'result' variable: {}", result);
    println!("   Macro's internal computation: {}", computed);
    assert_eq!(result, 999, "hygiene: caller's 'result' must be untouched");
    assert_eq!(computed, 25, "10 * 2 + 5 = 25");
    println!("   Hygiene verified: no variable capture occurred");
    println!();

    // ── Recursive macros ──────────────────────────────────────────────
    println!("6. Recursive Macro Expansion:");
    println!("   count_exprs!()           = {}", count_exprs!());
    println!("   count_exprs!(a)          = {}", count_exprs!("a"));
    println!("   count_exprs!(a, b, c)    = {}", count_exprs!("a", "b", "c"));
    println!("   count_exprs!(1,2,3,4,5)  = {}", count_exprs!(1, 2, 3, 4, 5));
    println!();

    // ── Code generation (builder pattern) ─────────────────────────────
    println!("7. Macro-Generated Code (builder pattern):");
    make_builder!(Config {
        host: String,
        port: u16,
        verbose: bool,
    });

    let cfg = Config::new()
        .host("localhost".to_string())
        .port(8080);
    println!("   {}", cfg.describe());
    let cfg_full = cfg.verbose(true);
    println!("   {}", cfg_full.describe());
    println!();

    // ── Composability: macros invoking macros ─────────────────────────
    println!("8. Macro Composability (outer invokes inner):");
    println!("   {}", outer!(10, 20, 30));
    println!();

    // ── Token tree munching ───────────────────────────────────────────
    println!("9. Token Tree Munching (custom syntax parsing):");
    let math_result = simple_math!(1 + 2 + 3);
    println!("   simple_math!(1 + 2 + 3) = {}", math_result);
    assert_eq!(math_result, 6);
    println!();

    // ── Stringify and concat: compile-time string manipulation ────────
    println!("10. Compile-Time Intrinsics (stringify!, concat!):");
    println!("    stringify!(2 + 2)       = \"{}\"", stringify!(2 + 2));
    println!("    concat!(\"a\", \"b\", \"c\") = \"{}\"", concat!("a", "b", "c"));
    println!("    These operate on tokens, not values — they run during expansion.");
    println!();

    println!("Key design concepts demonstrated:");
    println!("  - Pattern matching on token trees (not text substitution)");
    println!("  - Hygienic name binding (macro variables don't leak)");
    println!("  - Repetition operators for variadic input");
    println!("  - Fragment specifiers as the type system for macro patterns");
    println!("  - Recursive expansion with mandatory base cases");
    println!("  - Compile-time code generation (struct + impl from a macro)");
    println!("  - Token tree munching for parsing custom syntax");
}
