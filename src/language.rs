//! Supported programming languages and their metadata.
//!
//! Each language tracks its file extension, comment syntax, and how to
//! compile/run examples for validation.

use serde::{Deserialize, Serialize};

/// A programming language supported by vidya.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[non_exhaustive]
pub enum Language {
    /// Rust (`.rs`) — compiled, systems programming
    Rust,
    /// Python (`.py`) — interpreted, general purpose
    Python,
    /// C (`.c`) — compiled, systems programming
    C,
    /// Go (`.go`) — compiled, concurrent systems
    Go,
    /// TypeScript (`.ts`) — transpiled, web/server
    TypeScript,
    /// Shell (`.sh`) — interpreted, scripting/automation
    Shell,
    /// Zig (`.zig`) — compiled, systems programming
    Zig,
}

impl Language {
    /// File extension for this language (without dot).
    #[must_use]
    pub const fn extension(&self) -> &'static str {
        match self {
            Self::Rust => "rs",
            Self::Python => "py",
            Self::C => "c",
            Self::Go => "go",
            Self::TypeScript => "ts",
            Self::Shell => "sh",
            Self::Zig => "zig",
        }
    }

    /// Human-readable display name.
    #[must_use]
    pub const fn display_name(&self) -> &'static str {
        match self {
            Self::Rust => "Rust",
            Self::Python => "Python",
            Self::C => "C",
            Self::Go => "Go",
            Self::TypeScript => "TypeScript",
            Self::Shell => "Shell",
            Self::Zig => "Zig",
        }
    }

    /// Single-line comment prefix.
    #[must_use]
    pub const fn comment_prefix(&self) -> &'static str {
        match self {
            Self::Rust | Self::C | Self::Go | Self::TypeScript | Self::Zig => "//",
            Self::Python | Self::Shell => "#",
        }
    }

    /// All supported languages.
    #[must_use]
    pub const fn all() -> &'static [Language] {
        &[
            Self::Rust,
            Self::Python,
            Self::C,
            Self::Go,
            Self::TypeScript,
            Self::Shell,
            Self::Zig,
        ]
    }

    /// Parse from a string (case-insensitive, accepts extensions too).
    #[must_use]
    pub fn from_str_loose(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "rust" | "rs" => Some(Self::Rust),
            "python" | "py" => Some(Self::Python),
            "c" => Some(Self::C),
            "go" | "golang" => Some(Self::Go),
            "typescript" | "ts" => Some(Self::TypeScript),
            "shell" | "sh" | "bash" | "zsh" => Some(Self::Shell),
            "zig" => Some(Self::Zig),
            _ => None,
        }
    }
}

impl std::fmt::Display for Language {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.display_name())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn all_languages() {
        let all = Language::all();
        assert_eq!(all.len(), 7);
    }

    #[test]
    fn extensions() {
        assert_eq!(Language::Rust.extension(), "rs");
        assert_eq!(Language::Python.extension(), "py");
        assert_eq!(Language::C.extension(), "c");
        assert_eq!(Language::Go.extension(), "go");
        assert_eq!(Language::TypeScript.extension(), "ts");
        assert_eq!(Language::Shell.extension(), "sh");
        assert_eq!(Language::Zig.extension(), "zig");
    }

    #[test]
    fn from_str_loose_variants() {
        assert_eq!(Language::from_str_loose("rust"), Some(Language::Rust));
        assert_eq!(Language::from_str_loose("RS"), Some(Language::Rust));
        assert_eq!(Language::from_str_loose("golang"), Some(Language::Go));
        assert_eq!(Language::from_str_loose("bash"), Some(Language::Shell));
        assert_eq!(Language::from_str_loose("haskell"), None);
    }

    #[test]
    fn display() {
        assert_eq!(Language::Rust.to_string(), "Rust");
        assert_eq!(Language::TypeScript.to_string(), "TypeScript");
    }

    #[test]
    fn comment_prefix() {
        assert_eq!(Language::Rust.comment_prefix(), "//");
        assert_eq!(Language::Python.comment_prefix(), "#");
    }

    #[test]
    fn serde_roundtrip() {
        let lang = Language::Rust;
        let json = serde_json::to_string(&lang).unwrap();
        let decoded: Language = serde_json::from_str(&json).unwrap();
        assert_eq!(lang, decoded);
    }
}
