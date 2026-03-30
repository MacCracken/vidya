use openqasm::{GenericError, Parser, SourceCache};
use std::path::Path;

fn validate_qasm(path: &str) -> Result<usize, String> {
    let source = std::fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut cache = SourceCache::new();
    let mut parser = Parser::new(&mut cache);
    parser.parse_source(source, Some(Path::new("content")));
    match parser.done().to_errors() {
        Ok(prog) => Ok(prog.decls.len()),
        Err(errors) => Err(format!("{} parse errors", errors.errors.len())),
    }
}

fn main() {
    let mut qasm_files: Vec<String> = std::fs::read_dir("content")
        .unwrap()
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let p = e.path().join("openqasm.qasm");
            if p.exists() {
                Some(p.to_string_lossy().to_string())
            } else {
                None
            }
        })
        .collect();
    qasm_files.sort();

    let mut pass = 0;
    let mut fail = 0;
    for path in &qasm_files {
        match validate_qasm(path) {
            Ok(n) => {
                println!("  ✓ {path} ({n} decls)");
                pass += 1;
            }
            Err(e) => {
                println!("  ✗ {path}: {e}");
                fail += 1;
            }
        }
    }
    println!("\n{pass} passed, {fail} failed");
    if fail > 0 {
        std::process::exit(1);
    }
}
