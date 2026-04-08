//! Error types for vidya.

use thiserror::Error;

/// Errors produced by vidya operations.
#[derive(Debug, Error)]
#[non_exhaustive]
pub enum VidyaError {
    /// Concept not found in the registry.
    #[error("concept not found: {0}")]
    ConceptNotFound(String),

    /// Language not supported for the given concept.
    #[error("language not available for concept '{concept}': {language}")]
    LanguageNotAvailable { concept: String, language: String },

    /// Content directory not found or unreadable.
    #[error("content directory error: {0}")]
    ContentDir(String),

    /// Example validation failed (compilation or runtime error).
    #[error("validation failed for {language}/{concept}: {message}")]
    ValidationFailed {
        language: String,
        concept: String,
        message: String,
    },

    /// Parse error reading content files.
    #[error("parse error: {0}")]
    Parse(String),

    /// I/O error.
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    /// JSON serialization/deserialization error.
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

/// Convenience alias for `std::result::Result<T, VidyaError>`.
pub type Result<T> = std::result::Result<T, VidyaError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn error_display() {
        let err = VidyaError::ConceptNotFound("strings".into());
        assert_eq!(err.to_string(), "concept not found: strings");
    }

    #[test]
    fn error_language_not_available() {
        let err = VidyaError::LanguageNotAvailable {
            concept: "concurrency".into(),
            language: "brainfuck".into(),
        };
        assert!(err.to_string().contains("brainfuck"));
        assert!(err.to_string().contains("concurrency"));
    }

    #[test]
    fn error_validation_failed() {
        let err = VidyaError::ValidationFailed {
            language: "rust".into(),
            concept: "strings".into(),
            message: "compilation error".into(),
        };
        assert!(err.to_string().contains("rust/strings"));
    }

    #[test]
    fn error_is_send_sync() {
        fn assert_send<T: Send>() {}
        fn assert_sync<T: Sync>() {}
        assert_send::<VidyaError>();
        assert_sync::<VidyaError>();
    }
}
