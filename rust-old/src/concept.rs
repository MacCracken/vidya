//! Core types for programming concepts.
//!
//! A [`Concept`] represents a programming topic (e.g. "Strings", "Concurrency")
//! with best practices, gotchas, performance notes, and implementations
//! across multiple languages.

use crate::language::Language;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// A programming topic category.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[non_exhaustive]
pub enum Topic {
    /// Data types and structures (strings, arrays, maps, etc.)
    DataTypes,
    /// Concurrency and parallelism (threads, async, channels, etc.)
    Concurrency,
    /// Error handling patterns (exceptions, Result types, etc.)
    ErrorHandling,
    /// Memory management (ownership, GC, allocation, etc.)
    MemoryManagement,
    /// I/O operations (files, network, streams, etc.)
    InputOutput,
    /// Testing patterns and strategies
    Testing,
    /// Algorithms and algorithmic thinking
    Algorithms,
    /// Design patterns and architecture
    Patterns,
    /// Type systems and generics
    TypeSystems,
    /// Performance optimization
    Performance,
    /// Security practices
    Security,
    /// Kernel and systems programming (interrupts, page tables, bootloaders, MMIO, ABIs)
    KernelTopics,
    /// Quantum computing algorithms and concepts (Grover's, Shor's, VQE, noise models)
    QuantumComputing,
    /// Compiler bootstrapping (self-hosting, multi-stage compilation, cross-compilation)
    CompilerBootstrapping,
    /// Binary formats and executable structure (ELF, PE, Mach-O, linking)
    BinaryFormats,
    /// Lexing and parsing (tokenizers, recursive descent, precedence climbing, parser combinators)
    LexingAndParsing,
    /// Intermediate representations (SSA, CFG, basic blocks, phi nodes)
    IntermediateRepresentations,
    /// Code generation (instruction selection, register allocation, calling conventions)
    CodeGeneration,
    /// Linking and loading (symbol resolution, relocations, dynamic linking, GOT/PLT)
    LinkingAndLoading,
    /// Optimization passes (dead code elimination, constant folding, inlining, loop unrolling)
    OptimizationPasses,
    /// Syscalls and ABI (Linux syscall interface, System V AMD64 ABI, calling conventions)
    SyscallsAndAbi,
    /// Virtual memory (page tables, TLB, mmap, memory-mapped I/O)
    VirtualMemory,
    /// Interrupt handling (IDT, exception handlers, IRQ routing, context switching)
    InterruptHandling,
    /// Process and scheduling (task structs, context switch mechanics, scheduler algorithms)
    ProcessAndScheduling,
    /// Filesystems (VFS layer, inode structures, block devices)
    Filesystems,
    /// Ownership and borrowing (move semantics, lifetime analysis, borrow checking algorithms)
    OwnershipAndBorrowing,
    /// Trait and typeclass systems (monomorphization vs vtables, coherence, associated types)
    TraitAndTypeclassSystems,
    /// Macro systems (hygiene, procedural vs declarative, compile-time evaluation)
    MacroSystems,
    /// Module systems (namespacing, visibility, separate compilation, incremental builds)
    ModuleSystems,
    /// Instruction encoding (x86_64 encoding rules, ModR/M, SIB, VEX/EVEX)
    InstructionEncoding,
    /// ELF and executable formats (sections, DWARF debug info, relocatable objects)
    ElfAndExecutableFormats,
    /// Allocators (bump, arena, slab, buddy allocation strategies)
    Allocators,
    /// Boot and startup (multiboot, UEFI handoff, early init, GDT/IDT setup)
    BootAndStartup,
}

impl std::fmt::Display for Topic {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::DataTypes => f.write_str("Data Types"),
            Self::Concurrency => f.write_str("Concurrency"),
            Self::ErrorHandling => f.write_str("Error Handling"),
            Self::MemoryManagement => f.write_str("Memory Management"),
            Self::InputOutput => f.write_str("I/O"),
            Self::Testing => f.write_str("Testing"),
            Self::Algorithms => f.write_str("Algorithms"),
            Self::Patterns => f.write_str("Design Patterns"),
            Self::TypeSystems => f.write_str("Type Systems"),
            Self::Performance => f.write_str("Performance"),
            Self::Security => f.write_str("Security"),
            Self::KernelTopics => f.write_str("Kernel Topics"),
            Self::QuantumComputing => f.write_str("Quantum Computing"),
            Self::CompilerBootstrapping => f.write_str("Compiler Bootstrapping"),
            Self::BinaryFormats => f.write_str("Binary Formats"),
            Self::LexingAndParsing => f.write_str("Lexing and Parsing"),
            Self::IntermediateRepresentations => f.write_str("Intermediate Representations"),
            Self::CodeGeneration => f.write_str("Code Generation"),
            Self::LinkingAndLoading => f.write_str("Linking and Loading"),
            Self::OptimizationPasses => f.write_str("Optimization Passes"),
            Self::SyscallsAndAbi => f.write_str("Syscalls and ABI"),
            Self::VirtualMemory => f.write_str("Virtual Memory"),
            Self::InterruptHandling => f.write_str("Interrupt Handling"),
            Self::ProcessAndScheduling => f.write_str("Process and Scheduling"),
            Self::Filesystems => f.write_str("Filesystems"),
            Self::OwnershipAndBorrowing => f.write_str("Ownership and Borrowing"),
            Self::TraitAndTypeclassSystems => f.write_str("Trait and Typeclass Systems"),
            Self::MacroSystems => f.write_str("Macro Systems"),
            Self::ModuleSystems => f.write_str("Module Systems"),
            Self::InstructionEncoding => f.write_str("Instruction Encoding"),
            Self::ElfAndExecutableFormats => f.write_str("ELF and Executable Formats"),
            Self::Allocators => f.write_str("Allocators"),
            Self::BootAndStartup => f.write_str("Boot and Startup"),
        }
    }
}

/// A programming concept with multi-language implementations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Concept {
    /// Unique identifier (lowercase, underscore-separated, e.g. "string_interpolation").
    pub id: String,
    /// Human-readable title (e.g. "String Interpolation").
    pub title: String,
    /// Topic category.
    pub topic: Topic,
    /// One-paragraph description of the concept.
    pub description: String,
    /// Best practices — the "do this" advice.
    pub best_practices: Vec<BestPractice>,
    /// Gotchas — common mistakes, surprising behavior, footguns.
    pub gotchas: Vec<Gotcha>,
    /// Performance notes — optimization insights, benchmark findings.
    pub performance_notes: Vec<PerformanceNote>,
    /// Tags for search (e.g. ["utf-8", "unicode", "formatting"]).
    pub tags: Vec<String>,
    /// Implementations keyed by language.
    pub examples: HashMap<Language, Example>,
}

impl Concept {
    /// Get the implementation for a specific language.
    #[must_use]
    pub fn example(&self, lang: Language) -> Option<&Example> {
        self.examples.get(&lang)
    }

    /// List all languages that have implementations for this concept.
    #[must_use]
    pub fn available_languages(&self) -> Vec<Language> {
        let mut langs: Vec<Language> = self.examples.keys().copied().collect();
        langs.sort_by_key(|l| l.display_name());
        langs
    }

    /// Check if a tag matches (case-insensitive).
    #[must_use]
    pub fn has_tag(&self, tag: &str) -> bool {
        let lower = tag.to_lowercase();
        self.tags.iter().any(|t| t.to_lowercase() == lower)
    }
}

/// A best practice for a concept — the "do this" advice.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BestPractice {
    /// Short title (e.g. "Use &str for function parameters").
    pub title: String,
    /// Explanation of why this is the right approach.
    pub explanation: String,
    /// Optional language this applies to (None = universal).
    pub language: Option<Language>,
}

/// A gotcha — common mistake, surprising behavior, or footgun.
///
/// These are the things developers get wrong. Documenting them explicitly
/// prevents AI models from learning the wrong pattern.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Gotcha {
    /// Short title (e.g. "String indexing panics on multi-byte characters").
    pub title: String,
    /// What goes wrong and why.
    pub explanation: String,
    /// The wrong way (what people do).
    pub bad_example: Option<String>,
    /// The right way (what they should do).
    pub good_example: Option<String>,
    /// Optional language this applies to (None = universal).
    pub language: Option<Language>,
}

/// A performance note — optimization insight or benchmark finding.
///
/// These capture real-world performance discoveries: when a different
/// approach is measurably faster, what the tradeoffs are, and evidence
/// (benchmark numbers or complexity analysis).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceNote {
    /// Short title (e.g. "Pre-allocate with `with_capacity` for known sizes").
    pub title: String,
    /// What the improvement is and when it applies.
    pub explanation: String,
    /// Benchmark numbers or complexity comparison (optional).
    pub evidence: Option<String>,
    /// Optional language this applies to (None = universal).
    pub language: Option<Language>,
}

/// A code example implementing a concept in a specific language.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Example {
    /// The programming language.
    pub language: Language,
    /// The source code.
    pub code: String,
    /// Inline explanation/comments about the approach.
    pub explanation: String,
    /// File path relative to content directory (e.g. "strings/rust.rs").
    pub source_path: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_concept() -> Concept {
        let mut examples = HashMap::new();
        examples.insert(
            Language::Rust,
            Example {
                language: Language::Rust,
                code: "let s = format!(\"hello {}\", name);".into(),
                explanation: "Rust uses the format! macro for string interpolation.".into(),
                source_path: Some("strings/rust.rs".into()),
            },
        );
        examples.insert(
            Language::Python,
            Example {
                language: Language::Python,
                code: "s = f\"hello {name}\"".into(),
                explanation: "Python uses f-strings for interpolation.".into(),
                source_path: Some("strings/python.py".into()),
            },
        );

        Concept {
            id: "string_interpolation".into(),
            title: "String Interpolation".into(),
            topic: Topic::DataTypes,
            description: "Embedding expressions inside string literals.".into(),
            best_practices: vec![BestPractice {
                title: "Prefer interpolation over concatenation".into(),
                explanation: "More readable and often more efficient.".into(),
                language: None,
            }],
            gotchas: vec![Gotcha {
                title: "Rust format! allocates a new String".into(),
                explanation: "Use write! to avoid allocation when writing to a buffer.".into(),
                bad_example: Some("let s = format!(\"x={}\", x);".into()),
                good_example: Some("write!(buf, \"x={}\", x)?;".into()),
                language: Some(Language::Rust),
            }],
            performance_notes: vec![PerformanceNote {
                title: "write! over format! on hot paths".into(),
                explanation: "format! allocates; write! appends to existing buffer.".into(),
                evidence: Some("~40% fewer allocations in benchmarks".into()),
                language: Some(Language::Rust),
            }],
            tags: vec![
                "strings".into(),
                "formatting".into(),
                "interpolation".into(),
            ],
            examples,
        }
    }

    #[test]
    fn concept_example_lookup() {
        let c = sample_concept();
        assert!(c.example(Language::Rust).is_some());
        assert!(c.example(Language::Python).is_some());
        assert!(c.example(Language::C).is_none());
    }

    #[test]
    fn concept_available_languages() {
        let c = sample_concept();
        let langs = c.available_languages();
        assert_eq!(langs.len(), 2);
    }

    #[test]
    fn concept_has_tag() {
        let c = sample_concept();
        assert!(c.has_tag("strings"));
        assert!(c.has_tag("STRINGS"));
        assert!(!c.has_tag("concurrency"));
    }

    #[test]
    fn concept_serde_roundtrip() {
        let c = sample_concept();
        let json = serde_json::to_string(&c).unwrap();
        let decoded: Concept = serde_json::from_str(&json).unwrap();
        assert_eq!(c.id, decoded.id);
        assert_eq!(c.examples.len(), decoded.examples.len());
    }

    #[test]
    fn topic_display() {
        assert_eq!(Topic::DataTypes.to_string(), "Data Types");
        assert_eq!(Topic::ErrorHandling.to_string(), "Error Handling");
    }

    #[test]
    fn topic_display_compiler_topics() {
        assert_eq!(Topic::LexingAndParsing.to_string(), "Lexing and Parsing");
        assert_eq!(
            Topic::IntermediateRepresentations.to_string(),
            "Intermediate Representations"
        );
        assert_eq!(Topic::CodeGeneration.to_string(), "Code Generation");
        assert_eq!(Topic::LinkingAndLoading.to_string(), "Linking and Loading");
        assert_eq!(Topic::OptimizationPasses.to_string(), "Optimization Passes");
    }

    #[test]
    fn topic_display_systems_topics() {
        assert_eq!(Topic::SyscallsAndAbi.to_string(), "Syscalls and ABI");
        assert_eq!(Topic::VirtualMemory.to_string(), "Virtual Memory");
        assert_eq!(Topic::InterruptHandling.to_string(), "Interrupt Handling");
        assert_eq!(
            Topic::ProcessAndScheduling.to_string(),
            "Process and Scheduling"
        );
        assert_eq!(Topic::Filesystems.to_string(), "Filesystems");
    }

    #[test]
    fn topic_display_language_design_topics() {
        assert_eq!(
            Topic::OwnershipAndBorrowing.to_string(),
            "Ownership and Borrowing"
        );
        assert_eq!(
            Topic::TraitAndTypeclassSystems.to_string(),
            "Trait and Typeclass Systems"
        );
        assert_eq!(Topic::MacroSystems.to_string(), "Macro Systems");
        assert_eq!(Topic::ModuleSystems.to_string(), "Module Systems");
    }

    #[test]
    fn topic_display_high_value_topics() {
        assert_eq!(
            Topic::InstructionEncoding.to_string(),
            "Instruction Encoding"
        );
        assert_eq!(
            Topic::ElfAndExecutableFormats.to_string(),
            "ELF and Executable Formats"
        );
        assert_eq!(Topic::Allocators.to_string(), "Allocators");
        assert_eq!(Topic::BootAndStartup.to_string(), "Boot and Startup");
    }

    #[test]
    fn topic_serde_roundtrip_all_variants() {
        let topics = [
            Topic::DataTypes,
            Topic::Concurrency,
            Topic::ErrorHandling,
            Topic::MemoryManagement,
            Topic::InputOutput,
            Topic::Testing,
            Topic::Algorithms,
            Topic::Patterns,
            Topic::TypeSystems,
            Topic::Performance,
            Topic::Security,
            Topic::KernelTopics,
            Topic::QuantumComputing,
            Topic::CompilerBootstrapping,
            Topic::BinaryFormats,
            Topic::LexingAndParsing,
            Topic::IntermediateRepresentations,
            Topic::CodeGeneration,
            Topic::LinkingAndLoading,
            Topic::OptimizationPasses,
            Topic::SyscallsAndAbi,
            Topic::VirtualMemory,
            Topic::InterruptHandling,
            Topic::ProcessAndScheduling,
            Topic::Filesystems,
            Topic::OwnershipAndBorrowing,
            Topic::TraitAndTypeclassSystems,
            Topic::MacroSystems,
            Topic::ModuleSystems,
            Topic::InstructionEncoding,
            Topic::ElfAndExecutableFormats,
            Topic::Allocators,
            Topic::BootAndStartup,
        ];

        for topic in &topics {
            let json = serde_json::to_string(topic).unwrap();
            let decoded: Topic = serde_json::from_str(&json).unwrap();
            assert_eq!(topic, &decoded, "serde roundtrip failed for {}", topic);
        }
    }

    #[test]
    fn topic_display_is_nonempty_for_all() {
        let topics = [
            Topic::DataTypes,
            Topic::LexingAndParsing,
            Topic::CodeGeneration,
            Topic::SyscallsAndAbi,
            Topic::Allocators,
            Topic::BootAndStartup,
            Topic::Filesystems,
            Topic::MacroSystems,
        ];
        for topic in &topics {
            let display = topic.to_string();
            assert!(!display.is_empty(), "{:?} has empty display", topic);
            // Display should not be the debug representation
            assert!(
                !display.contains("Topic::"),
                "{:?} display looks like Debug",
                topic
            );
        }
    }

    #[test]
    fn gotcha_fields() {
        let g = &sample_concept().gotchas[0];
        assert!(g.bad_example.is_some());
        assert!(g.good_example.is_some());
        assert_eq!(g.language, Some(Language::Rust));
    }

    #[test]
    fn performance_note_fields() {
        let p = &sample_concept().performance_notes[0];
        assert!(p.evidence.is_some());
        assert_eq!(p.language, Some(Language::Rust));
    }

    #[test]
    fn best_practice_universal() {
        let bp = &sample_concept().best_practices[0];
        assert!(bp.language.is_none()); // applies to all languages
    }
}
