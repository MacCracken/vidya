// Vidya — Design Patterns in Rust
//
// Rust patterns lean on the type system: builders with typestate,
// strategy via closures/trait objects, RAII through Drop, state
// machines as enums, and newtypes for domain validation. No
// inheritance — composition and traits instead.

fn main() {
    test_builder_pattern();
    test_strategy_pattern();
    test_observer_pattern();
    test_state_machine();
    test_newtype_pattern();
    test_raii_cleanup();
    test_dependency_injection();
    test_factory_pattern();

    println!("All design patterns examples passed.");
}

// ── Builder pattern ───────────────────────────────────────────────────
// Readable construction for structs with many fields.
// Returns Result to enforce required fields at build time.

#[derive(Debug)]
struct Server {
    host: String,
    port: u16,
    max_connections: usize,
    timeout_ms: u64,
}

struct ServerBuilder {
    host: Option<String>,
    port: Option<u16>,
    max_connections: usize,
    timeout_ms: u64,
}

impl ServerBuilder {
    fn new() -> Self {
        Self {
            host: None,
            port: None,
            max_connections: 100,
            timeout_ms: 5000,
        }
    }

    fn host(mut self, host: &str) -> Self {
        self.host = Some(host.to_string());
        self
    }

    fn port(mut self, port: u16) -> Self {
        self.port = Some(port);
        self
    }

    fn max_connections(mut self, n: usize) -> Self {
        self.max_connections = n;
        self
    }

    fn timeout_ms(mut self, ms: u64) -> Self {
        self.timeout_ms = ms;
        self
    }

    fn build(self) -> Result<Server, &'static str> {
        Ok(Server {
            host: self.host.ok_or("host is required")?,
            port: self.port.ok_or("port is required")?,
            max_connections: self.max_connections,
            timeout_ms: self.timeout_ms,
        })
    }
}

fn test_builder_pattern() {
    let server = ServerBuilder::new()
        .host("localhost")
        .port(8080)
        .max_connections(200)
        .timeout_ms(3000)
        .build()
        .unwrap();

    assert_eq!(server.host, "localhost");
    assert_eq!(server.port, 8080);
    assert_eq!(server.max_connections, 200);
    assert_eq!(server.timeout_ms, 3000);

    // Missing required field → error
    let err = ServerBuilder::new().host("localhost").build();
    assert!(err.is_err());
}

// ── Strategy pattern ──────────────────────────────────────────────────
// In Rust: closures or trait objects, not class inheritance.

fn apply_discount(price: f64, strategy: &dyn Fn(f64) -> f64) -> f64 {
    strategy(price)
}

fn test_strategy_pattern() {
    let no_discount = |p: f64| p;
    let ten_percent = |p: f64| p * 0.9;
    let flat_five = |p: f64| (p - 5.0).max(0.0);

    assert_eq!(apply_discount(100.0, &no_discount), 100.0);
    assert_eq!(apply_discount(100.0, &ten_percent), 90.0);
    assert_eq!(apply_discount(100.0, &flat_five), 95.0);
    assert_eq!(apply_discount(3.0, &flat_five), 0.0); // can't go negative
}

// ── Observer pattern ──────────────────────────────────────────────────
// Callback-based event notification. Closures stored in a Vec.

struct EventEmitter {
    listeners: Vec<Box<dyn Fn(&str)>>,
}

impl EventEmitter {
    fn new() -> Self {
        Self {
            listeners: Vec::new(),
        }
    }

    fn on(&mut self, callback: impl Fn(&str) + 'static) {
        self.listeners.push(Box::new(callback));
    }

    fn emit(&self, event: &str) {
        for listener in &self.listeners {
            listener(event);
        }
    }
}

fn test_observer_pattern() {
    use std::cell::RefCell;
    use std::rc::Rc;

    let log = Rc::new(RefCell::new(Vec::new()));

    let mut emitter = EventEmitter::new();

    let log1 = Rc::clone(&log);
    emitter.on(move |e| log1.borrow_mut().push(format!("A:{e}")));

    let log2 = Rc::clone(&log);
    emitter.on(move |e| log2.borrow_mut().push(format!("B:{e}")));

    emitter.emit("click");
    emitter.emit("hover");

    let entries = log.borrow();
    assert_eq!(entries.len(), 4);
    assert_eq!(entries[0], "A:click");
    assert_eq!(entries[1], "B:click");
    assert_eq!(entries[2], "A:hover");
    assert_eq!(entries[3], "B:hover");
}

// ── State machine as enum ─────────────────────────────────────────────
// Each state is an enum variant. Invalid transitions are compile errors.

#[derive(Debug, PartialEq)]
enum DoorState {
    Locked,
    Closed,
    Open,
}

impl DoorState {
    fn unlock(self) -> Result<Self, &'static str> {
        match self {
            Self::Locked => Ok(Self::Closed),
            _ => Err("can only unlock a locked door"),
        }
    }

    fn open(self) -> Result<Self, &'static str> {
        match self {
            Self::Closed => Ok(Self::Open),
            _ => Err("can only open a closed door"),
        }
    }

    fn close(self) -> Result<Self, &'static str> {
        match self {
            Self::Open => Ok(Self::Closed),
            _ => Err("can only close an open door"),
        }
    }

    fn lock(self) -> Result<Self, &'static str> {
        match self {
            Self::Closed => Ok(Self::Locked),
            _ => Err("can only lock a closed door"),
        }
    }
}

fn test_state_machine() {
    let door = DoorState::Locked;
    let door = door.unlock().unwrap();
    assert_eq!(door, DoorState::Closed);
    let door = door.open().unwrap();
    assert_eq!(door, DoorState::Open);
    let door = door.close().unwrap();
    let door = door.lock().unwrap();
    assert_eq!(door, DoorState::Locked);

    // Invalid transition
    assert!(DoorState::Locked.open().is_err());
    assert!(DoorState::Open.lock().is_err());
}

// ── Newtype pattern ───────────────────────────────────────────────────
// Wrap primitive types to prevent mixing up arguments.

#[derive(Debug, Clone, Copy, PartialEq)]
struct Meters(f64);

#[derive(Debug, Clone, Copy, PartialEq)]
struct Seconds(f64);

#[derive(Debug, Clone, Copy, PartialEq)]
struct MetersPerSecond(f64);

fn speed(distance: Meters, time: Seconds) -> MetersPerSecond {
    MetersPerSecond(distance.0 / time.0)
}

fn test_newtype_pattern() {
    let d = Meters(100.0);
    let t = Seconds(9.58);
    let s = speed(d, t);
    assert!((s.0 - 10.438).abs() < 0.001);

    // This would be a compile error (types prevent mixup):
    // speed(Seconds(10.0), Meters(100.0));  // ERROR: expected Meters, got Seconds
}

// ── RAII cleanup ──────────────────────────────────────────────────────
// Acquire in constructor, release in Drop. Cleanup is automatic.

struct TempResource {
    name: String,
    log: std::rc::Rc<std::cell::RefCell<Vec<String>>>,
}

impl TempResource {
    fn new(name: &str, log: std::rc::Rc<std::cell::RefCell<Vec<String>>>) -> Self {
        log.borrow_mut().push(format!("acquire:{name}"));
        Self {
            name: name.to_string(),
            log,
        }
    }
}

impl Drop for TempResource {
    fn drop(&mut self) {
        self.log
            .borrow_mut()
            .push(format!("release:{}", self.name));
    }
}

fn test_raii_cleanup() {
    use std::cell::RefCell;
    use std::rc::Rc;

    let log = Rc::new(RefCell::new(Vec::new()));

    {
        let _r1 = TempResource::new("db", Rc::clone(&log));
        let _r2 = TempResource::new("file", Rc::clone(&log));
        // both alive here
        assert_eq!(log.borrow().len(), 2);
    } // both dropped here, in reverse order

    let entries = log.borrow();
    assert_eq!(entries.len(), 4);
    assert_eq!(entries[0], "acquire:db");
    assert_eq!(entries[1], "acquire:file");
    assert_eq!(entries[2], "release:file"); // reverse order
    assert_eq!(entries[3], "release:db");
}

// ── Dependency injection ──────────────────────────────────────────────
// Pass dependencies via constructor, not global state.

trait Logger {
    fn log(&self, msg: &str) -> String;
}

struct StdoutLogger;
impl Logger for StdoutLogger {
    fn log(&self, msg: &str) -> String {
        format!("[stdout] {msg}")
    }
}

struct TestLogger {
    entries: std::cell::RefCell<Vec<String>>,
}
impl TestLogger {
    fn new() -> Self {
        Self {
            entries: std::cell::RefCell::new(Vec::new()),
        }
    }
}
impl Logger for TestLogger {
    fn log(&self, msg: &str) -> String {
        let entry = format!("[test] {msg}");
        self.entries.borrow_mut().push(entry.clone());
        entry
    }
}

struct Service<'a> {
    logger: &'a dyn Logger,
}

impl<'a> Service<'a> {
    fn new(logger: &'a dyn Logger) -> Self {
        Self { logger }
    }

    fn process(&self, item: &str) -> String {
        self.logger.log(&format!("processing {item}"))
    }
}

fn test_dependency_injection() {
    // Production: real logger
    let stdout = StdoutLogger;
    let svc = Service::new(&stdout);
    assert_eq!(svc.process("order"), "[stdout] processing order");

    // Test: mock logger captures output
    let test_log = TestLogger::new();
    let svc = Service::new(&test_log);
    svc.process("order-1");
    svc.process("order-2");
    let entries = test_log.entries.borrow();
    assert_eq!(entries.len(), 2);
    assert_eq!(entries[0], "[test] processing order-1");
}

// ── Factory pattern ───────────────────────────────────────────────────
// Create objects based on runtime parameters.

#[derive(Debug, PartialEq)]
enum Shape {
    Circle { radius: f64 },
    Rectangle { width: f64, height: f64 },
    Triangle { base: f64, height: f64 },
}

impl Shape {
    fn area(&self) -> f64 {
        match self {
            Self::Circle { radius } => std::f64::consts::PI * radius * radius,
            Self::Rectangle { width, height } => width * height,
            Self::Triangle { base, height } => 0.5 * base * height,
        }
    }
}

fn shape_from_name(name: &str, params: &[f64]) -> Result<Shape, &'static str> {
    match name {
        "circle" if params.len() == 1 => Ok(Shape::Circle { radius: params[0] }),
        "rectangle" if params.len() == 2 => Ok(Shape::Rectangle {
            width: params[0],
            height: params[1],
        }),
        "triangle" if params.len() == 2 => Ok(Shape::Triangle {
            base: params[0],
            height: params[1],
        }),
        _ => Err("unknown shape or wrong params"),
    }
}

fn test_factory_pattern() {
    let c = shape_from_name("circle", &[5.0]).unwrap();
    assert!((c.area() - 78.539).abs() < 0.001);

    let r = shape_from_name("rectangle", &[3.0, 4.0]).unwrap();
    assert_eq!(r.area(), 12.0);

    let t = shape_from_name("triangle", &[6.0, 4.0]).unwrap();
    assert_eq!(t.area(), 12.0);

    assert!(shape_from_name("hexagon", &[1.0]).is_err());
}
