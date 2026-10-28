// Module Systems — Rust Implementation
//
// Demonstrates Rust's module system concepts in a single file:
//   - Inline module definitions with visibility control
//   - pub, pub(crate), pub(super), and private (default)
//   - Re-exports with pub use to create a public facade
//   - Nested module hierarchies
//   - How visibility rules restrict access across module boundaries
//
// In real projects, each mod block would be a separate file.
// Here they're inline to make the example self-contained and runnable.

/// Top-level library module — this is the public facade.
/// Re-exports curate what downstream users can access.
mod network {
    // Re-export only what users need. Internal structure is hidden.
    pub use self::connection::Connection;
    pub use self::protocol::{Protocol, Request, Response};

    /// Private submodule — not accessible outside `network`.
    mod connection {
        /// Connection is public, but its fields have mixed visibility.
        pub struct Connection {
            pub address: String,
            pub port: u16,
            // Private: only code in this module can touch the raw fd.
            fd: Option<i32>,
            // pub(super): visible to parent module `network` but not outside.
            pub(super) retry_count: u32,
        }

        impl Connection {
            /// Constructor is pub — this is the only way to create a Connection
            /// since `fd` is private. This enforces the invariant that
            /// connections start with no file descriptor.
            pub fn new(address: &str, port: u16) -> Self {
                Connection {
                    address: address.to_string(),
                    port,
                    fd: None,
                    retry_count: 0,
                }
            }

            /// Public method — part of the API.
            pub fn connect(&mut self) -> Result<(), String> {
                // Simulate connection: assign a fake fd.
                self.fd = Some(42);
                self.retry_count += 1;
                Ok(())
            }

            /// Private helper — only callable within this module.
            #[allow(dead_code)]
            fn raw_fd(&self) -> Option<i32> {
                self.fd
            }

            /// pub(crate) — visible anywhere in this crate, but not to
            /// external crates if this were a library.
            pub(crate) fn diagnostic_info(&self) -> String {
                format!(
                    "{}:{} fd={:?} retries={}",
                    self.address, self.port, self.fd, self.retry_count
                )
            }
        }
    }

    mod protocol {
        /// Protocol enum — public, so users can specify which protocol.
        #[derive(Debug)]
        #[allow(dead_code)]
        pub enum Protocol {
            Http,
            Https,
            Tcp,
        }

        /// Request type — public with public fields.
        #[derive(Debug)]
        #[allow(dead_code)]
        pub struct Request {
            pub method: String,
            pub path: String,
            pub protocol: Protocol,
        }

        /// Response type — public struct, mixed field visibility.
        #[derive(Debug)]
        pub struct Response {
            pub status: u16,
            pub body: String,
            // Private: internal caching flag, not part of API.
            cached: bool,
        }

        impl Response {
            pub fn new(status: u16, body: &str) -> Self {
                Response {
                    status,
                    body: body.to_string(),
                    cached: false,
                }
            }

            pub fn mark_cached(&mut self) {
                self.cached = true;
            }

            pub fn is_cached(&self) -> bool {
                self.cached
            }
        }

        /// Private helper — only visible within `protocol`.
        /// Sibling module `connection` cannot call this.
        #[allow(dead_code)]
        fn default_timeout_ms() -> u64 {
            5000
        }
    }

    /// Module-level function: can access pub(super) items from children.
    pub fn inspect_connection(conn: &Connection) -> String {
        // We can access retry_count because it's pub(super) and we are the parent.
        format!(
            "Connection to {}:{} (retries: {})",
            conn.address, conn.port, conn.retry_count
        )
    }
}

/// Demonstrates a nested module hierarchy with pub(in path) visibility.
mod engine {
    pub mod renderer {
        pub mod shader {
            /// pub(in crate::engine) — visible to anything in `engine`
            /// but not outside it.
            pub(in crate::engine) fn compile_glsl(source: &str) -> String {
                format!("compiled({} bytes)", source.len())
            }

            /// Fully public.
            pub fn shader_version() -> &'static str {
                "GLSL 4.60"
            }
        }

        pub fn render_frame() -> String {
            // renderer can call compile_glsl because it's inside engine.
            let compiled = shader::compile_glsl("void main() {}");
            format!("frame rendered with {}", compiled)
        }
    }

    pub fn engine_status() -> String {
        // engine can also call compile_glsl — it's pub(in crate::engine).
        let compiled = renderer::shader::compile_glsl("vertex_shader");
        format!("engine OK, shader: {}", compiled)
    }
}

fn main() {
    // --- Visibility and construction ---
    // Connection::new is pub, so we can create one from main.
    let mut conn = network::Connection::new("127.0.0.1", 8080);

    // conn.address and conn.port are pub — direct access works.
    println!("Connecting to {}:{}", conn.address, conn.port);

    // conn.fd is private — this would not compile:
    //   conn.fd = Some(99);  // error: field `fd` is private

    // conn.retry_count is pub(super) — visible to `network` but not here:
    //   println!("{}", conn.retry_count);  // error: field `retry_count` is private

    // --- Public methods work fine ---
    conn.connect().expect("connection failed");

    // pub(crate) method — accessible because we're in the same crate.
    println!("Diagnostics: {}", conn.diagnostic_info());

    // --- Re-exports flatten the module path ---
    // Without re-export: network::protocol::Request (if protocol were pub)
    // With re-export: network::Request — cleaner API surface.
    let req = network::Request {
        method: "GET".to_string(),
        path: "/index.html".to_string(),
        protocol: network::Protocol::Http,
    };
    println!("Request: {:?}", req);

    let mut resp = network::Response::new(200, "<html>hello</html>");
    resp.mark_cached();
    println!(
        "Response: status={}, cached={}, body={}",
        resp.status,
        resp.is_cached(),
        resp.body
    );

    // resp.cached is private — must use is_cached():
    //   println!("{}", resp.cached);  // error: field `cached` is private

    // --- Parent module can see pub(super) fields ---
    println!("{}", network::inspect_connection(&conn));

    // --- Nested hierarchy with pub(in path) ---
    // shader_version is fully public.
    println!("Shader version: {}", engine::renderer::shader::shader_version());

    // render_frame calls compile_glsl internally (allowed, inside engine).
    println!("{}", engine::renderer::render_frame());

    // engine_status also uses compile_glsl (allowed, inside engine).
    println!("{}", engine::engine_status());

    // Direct call to compile_glsl from main would fail:
    //   engine::renderer::shader::compile_glsl("test");
    //   // error: function `compile_glsl` is private

    println!("\nModule system summary:");
    println!("  pub          — visible everywhere");
    println!("  pub(crate)   — visible within the crate");
    println!("  pub(super)   — visible to parent module");
    println!("  pub(in path) — visible to a specific ancestor");
    println!("  (default)    — private to the defining module");
}
