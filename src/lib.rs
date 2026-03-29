//! Vidya — programming reference library and queryable corpus
//!
//! **Vidya** (Sanskrit: विद्या — knowledge, learning) provides a curated,
//! tested, multi-language programming reference. Every concept includes
//! best practices, instructional documentation, and reference implementations
//! in multiple languages — all verified by CI.
//!
//! # Architecture
//!
//! Vidya has two layers:
//!
//! 1. **Content directory** (`content/`) — Markdown docs and source files.
//!    No compilation needed. Humans can read it directly. AI models can
//!    train on it. The files ARE the corpus.
//!
//! 2. **Rust crate** (this) — Queryable interface over the content.
//!    Types, search, comparison, and validation. `cargo doc` generates
//!    a browsable programming reference. MCP tools make it queryable
//!    by agents.
//!
//! # Modules
//!
//! - [`concept`] — Core types: `Concept`, `Topic`, `Example`, `BestPractice`
//! - [`language`] — Supported languages and their metadata
//! - [`registry`] — In-memory concept registry, loaded from content directory
//! - [`loader`] — Content directory loader (TOML → Registry)
//! - [`search`] — Full-text and tag-based search across concepts
//! - [`compare`] — Side-by-side cross-language comparison
//! - [`validate`] — Compile/run verification of examples
//! - [`error`] — Error types
//!
//! # Example
//!
//! ```rust
//! use vidya::{Language, Registry};
//!
//! let registry = Registry::new();
//! // Look up string handling in Rust
//! if let Some(concept) = registry.get("strings") {
//!     println!("{}", concept.description);
//!     if let Some(example) = concept.example(Language::Rust) {
//!         println!("{}", example.code);
//!     }
//! }
//! ```

pub mod compare;
pub mod concept;
pub mod error;
pub mod language;
pub mod loader;
pub mod registry;
pub mod search;
pub mod validate;

#[cfg(feature = "logging")]
pub mod logging;

// ── Core types ─────────────────────────────────────────────────────────────
pub use concept::{BestPractice, Concept, Example, Gotcha, PerformanceNote, Topic};
pub use error::{Result, VidyaError};
pub use language::Language;
pub use registry::Registry;

// ── Operations ─────────────────────────────────────────────────────────────
pub use compare::Comparison;
pub use search::{SearchQuery, SearchResult};
pub use validate::ValidationResult;
