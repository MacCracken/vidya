// Vidya — Tracing & Structured Logging in Rust
//
// Structured logging replaces printf-debugging with machine-parseable
// records. This covers log levels, level filtering, structured entries,
// span-based timing, and packed error codes — all with zero external
// dependencies using only std.

use std::fmt;
use std::time::Instant;

// ── Log levels ────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum LogLevel {
    Error = 0,
    Warn  = 1,
    Info  = 2,
    Debug = 3,
    Trace = 4,
}

impl fmt::Display for LogLevel {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            LogLevel::Error => write!(f, "ERROR"),
            LogLevel::Warn  => write!(f, "WARN"),
            LogLevel::Info  => write!(f, "INFO"),
            LogLevel::Debug => write!(f, "DEBUG"),
            LogLevel::Trace => write!(f, "TRACE"),
        }
    }
}

// ── Structured log entry ──────────────────────────────────────────────

#[derive(Debug)]
struct LogEntry {
    level: LogLevel,
    target: &'static str,
    message: String,
    elapsed_ns: u64,
}

impl fmt::Display for LogEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "[{} +{}ns] {}: {}",
            self.level, self.elapsed_ns, self.target, self.message
        )
    }
}

// ── Logger with level filtering ───────────────────────────────────────

struct Logger {
    max_level: LogLevel,
    start: Instant,
    entries: Vec<LogEntry>,
}

impl Logger {
    fn new(max_level: LogLevel) -> Self {
        Self {
            max_level,
            start: Instant::now(),
            entries: Vec::new(),
        }
    }

    fn log(&mut self, level: LogLevel, target: &'static str, message: String) {
        // Filter: only record if level <= max_level (lower ordinal = higher severity)
        if level > self.max_level {
            return;
        }
        let elapsed_ns = self.start.elapsed().as_nanos() as u64;
        let entry = LogEntry { level, target, message, elapsed_ns };
        println!("{entry}");
        self.entries.push(entry);
    }

    fn entry_count(&self) -> usize {
        self.entries.len()
    }
}

// ── Span: enter/exit with elapsed timing ──────────────────────────────

struct Span {
    name: &'static str,
    start: Instant,
}

impl Span {
    fn enter(name: &'static str) -> Self {
        println!("[SPAN] --> {name}");
        Self { name, start: Instant::now() }
    }

    fn exit(self) -> u64 {
        let elapsed = self.start.elapsed().as_nanos() as u64;
        println!("[SPAN] <-- {} ({}ns)", self.name, elapsed);
        elapsed
    }
}

// ── Packed error codes ────────────────────────────────────────────────
// Layout: [63..32] = category, [31..0] = code
// Allows a single u64 to carry both a category tag and a specific error.

const CATEGORY_SHIFT: u32 = 32;
const CODE_MASK: u64 = 0xFFFF_FFFF;

fn pack_error(category: u32, code: u32) -> u64 {
    ((category as u64) << CATEGORY_SHIFT) | (code as u64)
}

fn unpack_category(packed: u64) -> u32 {
    (packed >> CATEGORY_SHIFT) as u32
}

fn unpack_code(packed: u64) -> u32 {
    (packed & CODE_MASK) as u32
}

// Category constants
const CAT_IO: u32     = 1;
const CAT_PARSE: u32  = 2;
const CAT_AUTH: u32    = 3;

fn main() {
    // ── Level filtering ───────────────────────────────────────────────
    let mut logger = Logger::new(LogLevel::Info);

    logger.log(LogLevel::Error, "db", "connection refused".into());
    logger.log(LogLevel::Warn,  "db", "retry attempt 2".into());
    logger.log(LogLevel::Info,  "db", "connected".into());
    logger.log(LogLevel::Debug, "db", "query plan cached".into());   // filtered
    logger.log(LogLevel::Trace, "db", "raw packet dump".into());     // filtered

    // Only Error, Warn, Info should be recorded (3 entries)
    assert_eq!(logger.entry_count(), 3);
    assert_eq!(logger.entries[0].level, LogLevel::Error);
    assert_eq!(logger.entries[1].level, LogLevel::Warn);
    assert_eq!(logger.entries[2].level, LogLevel::Info);

    // ── Level ordering ────────────────────────────────────────────────
    assert!(LogLevel::Error < LogLevel::Warn);
    assert!(LogLevel::Warn < LogLevel::Info);
    assert!(LogLevel::Info < LogLevel::Debug);
    assert!(LogLevel::Debug < LogLevel::Trace);

    // ── Structured entry formatting ───────────────────────────────────
    let entry = &logger.entries[0];
    assert_eq!(entry.target, "db");
    assert!(entry.message.contains("connection refused"));
    let formatted = format!("{entry}");
    assert!(formatted.contains("ERROR"));
    assert!(formatted.contains("db"));

    // ── Span timing ──────────────────────────────────────────────────
    let span = Span::enter("compute");
    // Do some work so elapsed > 0 is plausible
    let mut sum: u64 = 0;
    for i in 0..1000 {
        sum += i;
    }
    assert_eq!(sum, 499_500);
    let elapsed = span.exit();
    // Elapsed is non-negative (always true for u64, but documents intent)
    println!("compute span elapsed: {elapsed}ns");

    // Nested spans
    let outer = Span::enter("request");
    let inner = Span::enter("parse_body");
    let inner_ns = inner.exit();
    let outer_ns = outer.exit();
    // Outer span must be >= inner span
    assert!(outer_ns >= inner_ns);

    // ── Packed error codes ────────────────────────────────────────────
    let err = pack_error(CAT_IO, 42);
    assert_eq!(unpack_category(err), CAT_IO);
    assert_eq!(unpack_code(err), 42);

    let err2 = pack_error(CAT_PARSE, 7);
    assert_eq!(unpack_category(err2), CAT_PARSE);
    assert_eq!(unpack_code(err2), 7);

    let err3 = pack_error(CAT_AUTH, 0xDEAD);
    assert_eq!(unpack_category(err3), CAT_AUTH);
    assert_eq!(unpack_code(err3), 0xDEAD);

    // Different categories produce different packed values
    assert_ne!(pack_error(CAT_IO, 1), pack_error(CAT_PARSE, 1));

    // Same category + same code = same packed value (deterministic)
    assert_eq!(pack_error(CAT_IO, 99), pack_error(CAT_IO, 99));

    // Max code fits in 32 bits
    let max_err = pack_error(0xFFFF_FFFF, 0xFFFF_FFFF);
    assert_eq!(unpack_category(max_err), 0xFFFF_FFFF);
    assert_eq!(unpack_code(max_err), 0xFFFF_FFFF);

    // ── Logger at Trace level captures everything ─────────────────────
    let mut verbose = Logger::new(LogLevel::Trace);
    verbose.log(LogLevel::Error, "app", "fatal".into());
    verbose.log(LogLevel::Trace, "app", "heartbeat".into());
    assert_eq!(verbose.entry_count(), 2);

    // ── Logger at Error level filters aggressively ────────────────────
    let mut strict = Logger::new(LogLevel::Error);
    strict.log(LogLevel::Error, "app", "crash".into());
    strict.log(LogLevel::Warn,  "app", "degraded".into());  // filtered
    strict.log(LogLevel::Info,  "app", "started".into());    // filtered
    assert_eq!(strict.entry_count(), 1);

    println!("All tracing examples passed.");
}
