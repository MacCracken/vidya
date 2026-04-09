# Security Policy

## Scope

Vidya is a programming reference library. Its attack surface is:

- **Content loading**: TOML parsing of `concept.toml` files from the `content/` directory
- **File I/O**: Reading source files from `content/` subdirectories
- **Validation**: Executing code examples via shell commands (when `vidya validate` is run)

The `validate` command executes arbitrary code from content files. Only run it on trusted content.

## Reporting

Report security issues via GitHub Issues or email to the maintainer.

## Supported Versions

| Version | Supported |
|---------|-----------|
| 2.x     | Yes       |
| 1.x     | No (Rust crate, archived in rust-old/) |
| < 1.0   | No        |
