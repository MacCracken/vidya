// Vidya — Linking and Loading in Zig
//
// Symbol tables, relocation patching, and GOT/PLT concepts.
// A linker's job: resolve symbols across object files, apply
// relocations to patch addresses, and set up indirection tables
// for dynamic linking. Zig's hash maps and structs model these
// data structures naturally.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    try testSymbolTable();
    try testRelocationPatching();
    try testMultiObjectLinking();
    try testGotPlt();
    try testSectionMerging();

    std.debug.print("All linking and loading examples passed.\n", .{});
}

// ── Symbol ───────────────────────────────────────────────────────────
// A symbol is a name → address mapping. Symbols can be defined
// (have an address) or undefined (need resolution from another object).
const SymbolBinding = enum { local, global, weak };

const Symbol = struct {
    name: []const u8,
    value: u64, // address or offset within section
    size: u64,
    section: []const u8, // e.g., ".text", ".data"
    binding: SymbolBinding,
    defined: bool,
};

// ── Symbol Table ─────────────────────────────────────────────────────
const SymbolTable = struct {
    entries: std.StringHashMap(Symbol),
    alloc: Allocator,

    fn init(alloc: Allocator) SymbolTable {
        return .{
            .entries = std.StringHashMap(Symbol).init(alloc),
            .alloc = alloc,
        };
    }

    fn deinit(self: *SymbolTable) void {
        self.entries.deinit();
    }

    fn define(self: *SymbolTable, name: []const u8, value: u64, size: u64, section: []const u8, binding: SymbolBinding) !void {
        try self.entries.put(name, .{
            .name = name,
            .value = value,
            .size = size,
            .section = section,
            .binding = binding,
            .defined = true,
        });
    }

    fn declareUndefined(self: *SymbolTable, name: []const u8) !void {
        // Only add if not already defined
        if (self.entries.get(name) == null) {
            try self.entries.put(name, .{
                .name = name,
                .value = 0,
                .size = 0,
                .section = "",
                .binding = .global,
                .defined = false,
            });
        }
    }

    fn resolve(self: *const SymbolTable, name: []const u8) ?Symbol {
        const sym = self.entries.get(name) orelse return null;
        return if (sym.defined) sym else null;
    }
};

// ── Relocation ───────────────────────────────────────────────────────
// A relocation says: "at offset X in section Y, patch in the address
// of symbol Z." The relocation type determines how the patch is applied.
const RelocType = enum {
    abs64, // absolute 64-bit address
    rel32, // PC-relative 32-bit offset
    got32, // GOT entry offset
    plt32, // PLT entry offset
};

const Relocation = struct {
    offset: u64, // where in the section to patch
    symbol: []const u8, // what symbol to resolve
    rtype: RelocType,
    addend: i64, // added to the resolved address
};

// ── Object File ──────────────────────────────────────────────────────
// Simulated object file: a code buffer + symbol table + relocations.
const ObjectFile = struct {
    name: []const u8,
    code: [256]u8,
    code_len: usize,
    symbols: SymbolTable,
    relocs: [16]Relocation,
    reloc_count: usize,
    base_address: u64, // assigned by linker

    fn init(name: []const u8, alloc: Allocator) ObjectFile {
        return .{
            .name = name,
            .code = [_]u8{0} ** 256,
            .code_len = 0,
            .symbols = SymbolTable.init(alloc),
            .relocs = undefined,
            .reloc_count = 0,
            .base_address = 0,
        };
    }

    fn deinit(self: *ObjectFile) void {
        self.symbols.deinit();
    }

    fn addReloc(self: *ObjectFile, reloc: Relocation) void {
        self.relocs[self.reloc_count] = reloc;
        self.reloc_count += 1;
    }
};

// ── Relocation Patching ──────────────────────────────────────────────
// Apply relocations: look up each symbol, compute the patch value,
// write it into the code buffer at the relocation offset.
fn applyRelocations(obj: *ObjectFile, global_syms: *const SymbolTable) !void {
    for (0..obj.reloc_count) |i| {
        const rel = obj.relocs[i];

        // Resolve symbol — check object-local first, then global
        const sym = obj.symbols.resolve(rel.symbol) orelse
            global_syms.resolve(rel.symbol) orelse
            return error.UndefinedSymbol;

        const target_addr: i64 = @intCast(sym.value);
        const patch_offset = rel.offset;

        switch (rel.rtype) {
            .abs64 => {
                // Write absolute 64-bit address (little-endian)
                const val: u64 = @bitCast(target_addr + rel.addend);
                inline for (0..8) |b| {
                    obj.code[patch_offset + b] = @truncate(val >> @intCast(b * 8));
                }
            },
            .rel32 => {
                // PC-relative: target - (patch_site + 4) + addend
                const site: i64 = @intCast(obj.base_address + patch_offset + 4);
                const disp: i32 = @intCast(target_addr - site + rel.addend);
                const d: u32 = @bitCast(disp);
                inline for (0..4) |b| {
                    obj.code[patch_offset + b] = @truncate(d >> @intCast(b * 8));
                }
            },
            .got32, .plt32 => {
                // Simplified: treat like rel32 for demonstration
                const site: i64 = @intCast(obj.base_address + patch_offset + 4);
                const disp: i32 = @intCast(target_addr - site + rel.addend);
                const d: u32 = @bitCast(disp);
                inline for (0..4) |b| {
                    obj.code[patch_offset + b] = @truncate(d >> @intCast(b * 8));
                }
            },
        }
    }
}

// ── GOT / PLT ────────────────────────────────────────────────────────
// Global Offset Table: array of pointers, one per imported symbol.
// The dynamic linker fills these at load time.
// Procedure Linkage Table: stubs that jump through the GOT.
const GotEntry = struct {
    symbol: []const u8,
    address: u64, // filled by dynamic linker
    resolved: bool,
};

const PltEntry = struct {
    symbol: []const u8,
    got_index: usize, // which GOT slot to jump through
};

const GotPlt = struct {
    got: [16]GotEntry,
    got_len: usize,
    plt: [16]PltEntry,
    plt_len: usize,

    fn init() GotPlt {
        return .{
            .got = undefined,
            .got_len = 0,
            .plt = undefined,
            .plt_len = 0,
        };
    }

    fn addImport(self: *GotPlt, symbol: []const u8) usize {
        // Add GOT entry
        const got_idx = self.got_len;
        self.got[got_idx] = .{
            .symbol = symbol,
            .address = 0, // unresolved
            .resolved = false,
        };
        self.got_len += 1;

        // Add PLT stub pointing to this GOT entry
        self.plt[self.plt_len] = .{
            .symbol = symbol,
            .got_index = got_idx,
        };
        self.plt_len += 1;

        return got_idx;
    }

    /// Simulate dynamic linker resolving a symbol.
    fn resolve(self: *GotPlt, symbol: []const u8, address: u64) bool {
        for (0..self.got_len) |i| {
            if (mem.eql(u8, self.got[i].symbol, symbol)) {
                self.got[i].address = address;
                self.got[i].resolved = true;
                return true;
            }
        }
        return false;
    }

    fn lookup(self: *const GotPlt, symbol: []const u8) ?u64 {
        for (0..self.got_len) |i| {
            if (mem.eql(u8, self.got[i].symbol, symbol) and self.got[i].resolved) {
                return self.got[i].address;
            }
        }
        return null;
    }
};

// ── Tests ────────────────────────────────────────────────────────────
fn testSymbolTable() !void {
    var st = SymbolTable.init(std.heap.page_allocator);
    defer st.deinit();

    try st.define("main", 0x401000, 64, ".text", .global);
    try st.define("data_buf", 0x601000, 256, ".data", .local);
    try st.declareUndefined("printf");

    // Defined symbols resolve
    const main_sym = st.resolve("main").?;
    try expect(main_sym.value == 0x401000);
    try expect(main_sym.binding == .global);
    try expect(mem.eql(u8, main_sym.section, ".text"));

    const data_sym = st.resolve("data_buf").?;
    try expect(data_sym.value == 0x601000);
    try expect(data_sym.binding == .local);

    // Undefined symbol does not resolve
    try expect(st.resolve("printf") == null);

    // Nonexistent symbol returns null
    try expect(st.resolve("nonexistent") == null);
}

fn testRelocationPatching() !void {
    var obj = ObjectFile.init("test.o", std.heap.page_allocator);
    defer obj.deinit();

    // Simulate code: [E8, 00, 00, 00, 00] = CALL rel32 (placeholder)
    obj.code[0] = 0xE8;
    obj.code_len = 5;
    obj.base_address = 0x1000;

    // Define the target function at address 0x2000
    try obj.symbols.define("target_fn", 0x2000, 16, ".text", .global);

    // Add relocation: at offset 1, patch in rel32 to target_fn
    obj.addReloc(.{
        .offset = 1,
        .symbol = "target_fn",
        .rtype = .rel32,
        .addend = 0,
    });

    var empty = SymbolTable.init(std.heap.page_allocator);
    defer empty.deinit();
    try applyRelocations(&obj, &empty);

    // Expected displacement: 0x2000 - (0x1000 + 1 + 4) = 0xFFB = 4091
    // Little-endian: FB 0F 00 00
    try expect(obj.code[1] == 0xFB);
    try expect(obj.code[2] == 0x0F);
    try expect(obj.code[3] == 0x00);
    try expect(obj.code[4] == 0x00);
}

fn testMultiObjectLinking() !void {
    // Two object files: main.o references helper() defined in util.o
    var main_obj = ObjectFile.init("main.o", std.heap.page_allocator);
    defer main_obj.deinit();

    var util_obj = ObjectFile.init("util.o", std.heap.page_allocator);
    defer util_obj.deinit();

    // util.o defines helper at offset 0, loaded at base 0x2000
    util_obj.base_address = 0x2000;
    try util_obj.symbols.define("helper", 0x2000, 32, ".text", .global);

    // main.o calls helper — CALL rel32 at offset 0
    main_obj.base_address = 0x1000;
    main_obj.code[0] = 0xE8; // CALL
    main_obj.code_len = 5;
    try main_obj.symbols.declareUndefined("helper");
    main_obj.addReloc(.{
        .offset = 1,
        .symbol = "helper",
        .rtype = .rel32,
        .addend = 0,
    });

    // Link: resolve main.o's relocations using util.o's symbols
    try applyRelocations(&main_obj, &util_obj.symbols);

    // Verify the call target resolves correctly
    // displacement = 0x2000 - (0x1000 + 5) = 0x0FFB
    try expect(main_obj.code[1] == 0xFB);
    try expect(main_obj.code[2] == 0x0F);
}

fn testGotPlt() !void {
    var gp = GotPlt.init();

    // Import two shared library symbols
    const puts_idx = gp.addImport("puts");
    const malloc_idx = gp.addImport("malloc");

    try expect(puts_idx == 0);
    try expect(malloc_idx == 1);
    try expect(gp.got_len == 2);
    try expect(gp.plt_len == 2);

    // Before resolution: lookup returns null
    try expect(gp.lookup("puts") == null);

    // Dynamic linker resolves puts to 0x7FFF_0000_1000
    try expect(gp.resolve("puts", 0x7FFF_0000_1000));
    try expect(gp.lookup("puts").? == 0x7FFF_0000_1000);

    // malloc still unresolved
    try expect(gp.lookup("malloc") == null);

    // Resolve malloc
    try expect(gp.resolve("malloc", 0x7FFF_0000_2000));
    try expect(gp.lookup("malloc").? == 0x7FFF_0000_2000);

    // PLT entries point to correct GOT slots
    try expect(gp.plt[0].got_index == 0);
    try expect(mem.eql(u8, gp.plt[0].symbol, "puts"));
    try expect(gp.plt[1].got_index == 1);
    try expect(mem.eql(u8, gp.plt[1].symbol, "malloc"));
}

fn testSectionMerging() !void {
    // Linker merges .text sections from multiple objects.
    // Object A: .text = 64 bytes at base 0x1000
    // Object B: .text = 48 bytes at base 0x1040 (immediately after A)

    const Section = struct {
        name: []const u8,
        base: u64,
        size: u64,
    };

    const sections = [_]Section{
        .{ .name = ".text", .base = 0x1000, .size = 64 },
        .{ .name = ".text", .base = 0x1040, .size = 48 },
    };

    // Total merged .text size
    var total_text: u64 = 0;
    for (sections) |s| {
        if (mem.eql(u8, s.name, ".text")) total_text += s.size;
    }
    try expect(total_text == 112);

    // Verify contiguous layout
    try expect(sections[1].base == sections[0].base + sections[0].size);
}
