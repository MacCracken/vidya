use std::path::Path;
use vidya::Language;
use vidya::loader::load_all;
use vidya::validate::run_validation;

#[test]
fn validate_rust_strings() {
    let file_path = Path::new("content/strings/rust.rs");
    if !file_path.exists() {
        panic!("content/strings/rust.rs not found");
    }

    let result = run_validation("strings", Language::Rust, file_path);
    assert!(
        result.passed,
        "rust strings should validate: {:?}",
        result.error
    );
    assert!(result.duration_ms > 0);
}

/// Check if a language's toolchain is available on this system.
fn toolchain_available(lang: Language) -> bool {
    match lang {
        Language::Zig => which("zig"),
        Language::AsmAarch64 => which("aarch64-linux-gnu-as") && which("qemu-aarch64"),
        // Without the openqasm feature, OpenQASM falls back to Python/qiskit
        #[cfg(not(feature = "openqasm"))]
        Language::OpenQASM => std::process::Command::new("python3")
            .args(["-c", "import qiskit"])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .is_ok_and(|s| s.success()),
        Language::Cyrius => {
            let cyrius_home = std::env::var("CYRIUS_HOME")
                .unwrap_or_else(|_| format!("{}/Repos/cyrius", std::env::var("HOME").unwrap_or_default()));
            std::path::Path::new(&cyrius_home).join("build/cc2").exists()
        }
        _ => true,
    }
}

fn which(cmd: &str) -> bool {
    std::process::Command::new("which")
        .arg(cmd)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

#[test]
fn validate_all_loaded_content() {
    let content_dir = Path::new("content");
    let registry = load_all(content_dir).expect("should load content");
    let results = vidya::validate::validate_all(&registry, content_dir);

    let mut skipped = 0;
    for result in &results {
        if !toolchain_available(result.language) {
            skipped += 1;
            continue;
        }
        assert!(
            result.passed,
            "{}/{} failed: {:?}",
            result.concept_id, result.language, result.error
        );
    }

    if skipped > 0 {
        eprintln!(
            "validate_all: {} passed, {} skipped (missing toolchain)",
            results.len() - skipped,
            skipped
        );
    }
}
