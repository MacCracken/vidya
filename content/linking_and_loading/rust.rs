// Linking and Loading — Rust Implementation
//
// Demonstrates the core concepts of a linker:
//   - Object files with symbol tables and relocations
//   - Symbol resolution across compilation units
//   - Relocation patching (absolute and PC-relative)
//   - Section merging (.text, .data)
//
// This is a simplified model of what ld does when combining object files
// into an executable.

use std::collections::HashMap;
use std::fmt;

// ── Object file representation ────────────────────────────────────────────

/// A section in an object file (like .text or .data).
#[derive(Debug, Clone)]
struct Section {
    name: String,
    data: Vec<u8>,
    /// Base address once placed in the final binary
    base_addr: Option<u64>,
}

/// A symbol definition or reference.
#[derive(Debug, Clone)]
struct Symbol {
    name: String,
    /// Which section this symbol is in (for definitions)
    section: Option<String>,
    /// Offset within the section (for definitions)
    offset: Option<u64>,
    /// Is this a definition or just a reference?
    is_defined: bool,
    /// Resolved virtual address (filled in by linker)
    resolved_addr: Option<u64>,
}

/// A relocation entry — "patch this location with that symbol's address".
#[derive(Debug, Clone)]
struct Relocation {
    /// Section containing the bytes to patch
    section: String,
    /// Offset within the section to patch
    offset: u64,
    /// Symbol whose address to use
    symbol: String,
    /// Relocation type
    reloc_type: RelocType,
    /// Addend (added to symbol value)
    addend: i64,
}

#[derive(Debug, Clone, Copy)]
enum RelocType {
    /// Absolute 64-bit address (R_X86_64_64)
    Abs64,
    /// Absolute 32-bit address (R_X86_64_32S) — for disp32 in SIB addressing
    Abs32,
    /// PC-relative 32-bit (R_X86_64_PC32) — for CALL/JMP
    Pc32,
}

impl fmt::Display for RelocType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RelocType::Abs64 => write!(f, "R_X86_64_64"),
            RelocType::Abs32 => write!(f, "R_X86_64_32S"),
            RelocType::Pc32 => write!(f, "R_X86_64_PC32"),
        }
    }
}

/// A simplified object file.
#[derive(Debug, Clone)]
struct ObjectFile {
    name: String,
    sections: Vec<Section>,
    symbols: Vec<Symbol>,
    relocations: Vec<Relocation>,
}

// ── Linker ────────────────────────────────────────────────────────────────

/// Global symbol table entry.
#[derive(Debug)]
struct GlobalSymbol {
    /// Which object defined this symbol
    defined_in: String,
    /// Section name
    section: String,
    /// Offset within section
    offset: u64,
    /// Resolved virtual address
    addr: Option<u64>,
}

struct Linker {
    objects: Vec<ObjectFile>,
    global_symbols: HashMap<String, GlobalSymbol>,
    /// Final binary output
    output: Vec<u8>,
    /// Section placement: (section_key, base_addr, size)
    placements: Vec<(String, String, u64, usize)>, // (obj_name, section_name, base_addr, size)
    base_addr: u64,
}

impl Linker {
    fn new(base_addr: u64) -> Self {
        Self {
            objects: Vec::new(),
            global_symbols: HashMap::new(),
            output: Vec::new(),
            placements: Vec::new(),
            base_addr,
        }
    }

    fn add_object(&mut self, obj: ObjectFile) {
        self.objects.push(obj);
    }

    /// Pass 1: Collect all symbol definitions into global symbol table.
    fn collect_symbols(&mut self) -> Result<(), String> {
        for obj in &self.objects {
            for sym in &obj.symbols {
                if sym.is_defined {
                    if self.global_symbols.contains_key(&sym.name) {
                        return Err(format!(
                            "duplicate symbol '{}' (defined in {} and {})",
                            sym.name,
                            self.global_symbols[&sym.name].defined_in,
                            obj.name
                        ));
                    }
                    self.global_symbols.insert(
                        sym.name.clone(),
                        GlobalSymbol {
                            defined_in: obj.name.clone(),
                            section: sym.section.clone().unwrap(),
                            offset: sym.offset.unwrap(),
                            addr: None,
                        },
                    );
                }
            }
        }

        // Check for undefined references
        for obj in &self.objects {
            for sym in &obj.symbols {
                if !sym.is_defined && !self.global_symbols.contains_key(&sym.name) {
                    return Err(format!(
                        "undefined reference to '{}' in {}",
                        sym.name, obj.name
                    ));
                }
            }
        }

        Ok(())
    }

    /// Place sections in memory and compute final addresses.
    fn layout_sections(&mut self) {
        let mut addr = self.base_addr;

        // Group by section name: all .text first, then .data
        for section_name in &[".text", ".data"] {
            for obj in &self.objects {
                for sec in &obj.sections {
                    if sec.name == *section_name {
                        self.placements.push((
                            obj.name.clone(),
                            sec.name.clone(),
                            addr,
                            sec.data.len(),
                        ));
                        addr += sec.data.len() as u64;
                    }
                }
            }
        }

        // Resolve symbol addresses
        for gsym in self.global_symbols.values_mut() {
            for (obj_name, sec_name, base, _) in &self.placements {
                if *obj_name == gsym.defined_in && *sec_name == gsym.section {
                    gsym.addr = Some(*base + gsym.offset);
                }
            }
        }
    }

    /// Pass 2: Apply relocations — patch code with resolved addresses.
    fn apply_relocations(&mut self) -> Result<Vec<u8>, String> {
        // Build the output by concatenating sections in layout order
        let mut output = Vec::new();
        let objects = self.objects.clone();

        for (obj_name, sec_name, _, _) in &self.placements {
            let obj = objects.iter().find(|o| o.name == *obj_name).unwrap();
            let sec = obj.sections.iter().find(|s| s.name == *sec_name).unwrap();
            output.extend_from_slice(&sec.data);
        }

        // Apply each relocation
        for obj in &objects {
            for reloc in &obj.relocations {
                // Find the section's base address
                let sec_base = self
                    .placements
                    .iter()
                    .find(|(on, sn, _, _)| *on == obj.name && *sn == reloc.section)
                    .map(|(_, _, base, _)| *base)
                    .ok_or_else(|| {
                        format!("relocation in unknown section '{}'", reloc.section)
                    })?;

                // Find the symbol's resolved address
                let sym_addr = self
                    .global_symbols
                    .get(&reloc.symbol)
                    .and_then(|s| s.addr)
                    .ok_or_else(|| format!("unresolved symbol '{}'", reloc.symbol))?;

                // Compute the patch offset in the output buffer
                let patch_file_offset = (sec_base - self.base_addr) as usize + reloc.offset as usize;

                match reloc.reloc_type {
                    RelocType::Abs64 => {
                        let value = (sym_addr as i64 + reloc.addend) as u64;
                        let bytes = value.to_le_bytes();
                        output[patch_file_offset..patch_file_offset + 8]
                            .copy_from_slice(&bytes);
                    }
                    RelocType::Abs32 => {
                        // 32-bit absolute (sign-extended) — for disp32 fields
                        let value = (sym_addr as i64 + reloc.addend) as i32;
                        let bytes = value.to_le_bytes();
                        output[patch_file_offset..patch_file_offset + 4]
                            .copy_from_slice(&bytes);
                    }
                    RelocType::Pc32 => {
                        // PC-relative: target - (patch_address + 4)
                        let patch_addr = sec_base + reloc.offset;
                        let value =
                            sym_addr as i64 + reloc.addend - (patch_addr as i64 + 4);
                        let bytes = (value as i32).to_le_bytes();
                        output[patch_file_offset..patch_file_offset + 4]
                            .copy_from_slice(&bytes);
                    }
                }
            }
        }

        Ok(output)
    }

    fn link(mut self) -> Result<Vec<u8>, String> {
        println!("  Pass 1: Collecting symbols...");
        self.collect_symbols()?;
        for (name, sym) in &self.global_symbols {
            println!(
                "    {} defined in {} ({}+0x{:X})",
                name, sym.defined_in, sym.section, sym.offset
            );
        }

        println!("  Layout: Placing sections...");
        self.layout_sections();
        for (obj, sec, base, size) in &self.placements {
            println!(
                "    {}:{} at 0x{:X} ({} bytes)",
                obj, sec, base, size
            );
        }

        println!("  Symbol addresses:");
        for (name, sym) in &self.global_symbols {
            println!("    {} = 0x{:X}", name, sym.addr.unwrap());
        }

        println!("  Pass 2: Applying relocations...");
        let output = self.apply_relocations()?;

        Ok(output)
    }
}

// ── Demo ──────────────────────────────────────────────────────────────────

fn make_demo_objects() -> Vec<ObjectFile> {
    // main.o: calls add_numbers (defined in math.o), references GLOBAL_BASE (in math.o)
    let main_obj = ObjectFile {
        name: "main.o".to_string(),
        sections: vec![Section {
            name: ".text".to_string(),
            data: vec![
                // mov rdi, 10
                0x48, 0xC7, 0xC7, 0x0A, 0x00, 0x00, 0x00,
                // mov rsi, 32
                0x48, 0xC7, 0xC6, 0x20, 0x00, 0x00, 0x00,
                // call add_numbers (rel32 placeholder = 0x00000000)
                0xE8, 0x00, 0x00, 0x00, 0x00,
                // mov [GLOBAL_BASE], rax (disp32 placeholder = 0x00000000)
                0x48, 0x89, 0x04, 0x25, 0x00, 0x00, 0x00, 0x00,
                // ret
                0xC3,
            ],
            base_addr: None,
        }],
        symbols: vec![
            Symbol {
                name: "main".to_string(),
                section: Some(".text".to_string()),
                offset: Some(0),
                is_defined: true,
                resolved_addr: None,
            },
            Symbol {
                name: "add_numbers".to_string(),
                section: None,
                offset: None,
                is_defined: false, // reference — defined elsewhere
                resolved_addr: None,
            },
            Symbol {
                name: "GLOBAL_BASE".to_string(),
                section: None,
                offset: None,
                is_defined: false,
                resolved_addr: None,
            },
        ],
        relocations: vec![
            Relocation {
                section: ".text".to_string(),
                offset: 15, // offset of the rel32 in the CALL instruction
                symbol: "add_numbers".to_string(),
                reloc_type: RelocType::Pc32,
                addend: 0,
            },
            Relocation {
                section: ".text".to_string(),
                offset: 23, // offset of the disp32 field in MOV [disp32], RAX
                symbol: "GLOBAL_BASE".to_string(),
                reloc_type: RelocType::Abs32,
                addend: 0,
            },
        ],
    };

    // math.o: defines add_numbers and GLOBAL_BASE
    let math_obj = ObjectFile {
        name: "math.o".to_string(),
        sections: vec![
            Section {
                name: ".text".to_string(),
                data: vec![
                    // add_numbers: lea rax, [rdi + rsi]
                    0x48, 0x8D, 0x04, 0x37,
                    // ret
                    0xC3,
                ],
                base_addr: None,
            },
            Section {
                name: ".data".to_string(),
                data: vec![0x00; 8], // GLOBAL_BASE: 8 bytes, zero-initialized
                base_addr: None,
            },
        ],
        symbols: vec![
            Symbol {
                name: "add_numbers".to_string(),
                section: Some(".text".to_string()),
                offset: Some(0),
                is_defined: true,
                resolved_addr: None,
            },
            Symbol {
                name: "GLOBAL_BASE".to_string(),
                section: Some(".data".to_string()),
                offset: Some(0),
                is_defined: true,
                resolved_addr: None,
            },
        ],
        relocations: vec![],
    };

    vec![main_obj, math_obj]
}

fn main() {
    println!("Linking and Loading — symbol resolution and relocation:\n");

    let objects = make_demo_objects();
    let base_addr = 0x400000u64; // typical Linux executable base

    let mut linker = Linker::new(base_addr);
    for obj in objects {
        linker.add_object(obj);
    }

    match linker.link() {
        Ok(output) => {
            println!("\n  Linked binary: {} bytes", output.len());
            println!("  First 32 bytes:");
            for (i, chunk) in output.chunks(16).take(2).enumerate() {
                let hex: Vec<String> = chunk.iter().map(|b| format!("{:02X}", b)).collect();
                println!("    0x{:04X}: {}", i * 16, hex.join(" "));
            }

            // Verify the CALL relocation was patched
            println!("\n  Relocation verification:");
            let call_offset = 15; // where the rel32 is
            let patched_rel32 = i32::from_le_bytes([
                output[call_offset],
                output[call_offset + 1],
                output[call_offset + 2],
                output[call_offset + 3],
            ]);
            let call_site = base_addr + call_offset as u64 + 4; // PC after the CALL
            let target = (call_site as i64 + patched_rel32 as i64) as u64;
            println!(
                "    CALL at 0x{:X}: rel32 = {} → target 0x{:X}",
                base_addr + 14,
                patched_rel32,
                target
            );
        }
        Err(e) => {
            println!("  Link error: {}", e);
        }
    }

    // Demonstrate link error: undefined symbol
    println!("\n  --- Demonstrating link error ---");
    let bad_obj = ObjectFile {
        name: "bad.o".to_string(),
        sections: vec![Section {
            name: ".text".to_string(),
            data: vec![0xE8, 0x00, 0x00, 0x00, 0x00],
            base_addr: None,
        }],
        symbols: vec![Symbol {
            name: "nonexistent_function".to_string(),
            section: None,
            offset: None,
            is_defined: false,
            resolved_addr: None,
        }],
        relocations: vec![],
    };
    let mut bad_linker = Linker::new(0x400000);
    bad_linker.add_object(bad_obj);
    match bad_linker.link() {
        Ok(_) => println!("  (unexpectedly succeeded)"),
        Err(e) => println!("  {}", e),
    }
}
