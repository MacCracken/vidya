// Vidya — Linking and Loading in TypeScript
//
// Simulates how separate compilation units become a running process.
// The linker resolves symbol references between object files, applies
// relocations to patch addresses, and the loader maps everything into
// memory with GOT/PLT for dynamic dispatch.
//
// Key concepts demonstrated:
//   1. Symbol tables: name → address mapping for functions and data
//   2. Relocations: patches applied after final addresses are known
//   3. GOT (Global Offset Table): indirection for position-independent data
//   4. PLT (Procedure Linkage Table): lazy-binding stubs for function calls
//   5. Static linking: merge object files, resolve all symbols at link time
//   6. Dynamic linking: leave some symbols for the loader to resolve
//
// TypeScript idioms: classes with Maps, discriminated unions for
// relocation types, generics for the object file abstraction.

// ── Symbol types ─────────────────────────────────────────────────────

type SymbolBinding = "local" | "global" | "weak";
type SymbolKind = "function" | "data" | "undefined";

interface Symbol {
    name: string;
    binding: SymbolBinding;
    symbolKind: SymbolKind;
    section: string;
    offset: number; // offset within section
    size: number;
}

// ── Relocations ──────────────────────────────────────────────────────
// When the assembler emits code, it doesn't know final addresses.
// It leaves placeholders and records what needs patching.

type RelocationType =
    | "R_X86_64_64"      // absolute 64-bit address
    | "R_X86_64_PC32"    // PC-relative 32-bit offset
    | "R_X86_64_GOT"     // GOT entry reference
    | "R_X86_64_PLT"     // PLT entry reference
    ;

interface Relocation {
    offset: number;        // where in the section to patch
    type: RelocationType;
    symbolName: string;    // which symbol this refers to
    addend: number;        // constant to add after resolution
}

// ── Object file ──────────────────────────────────────────────────────

interface Section {
    name: string;
    data: Uint8Array;
    size: number;
}

class ObjectFile {
    readonly name: string;
    readonly sections: Map<string, Section> = new Map();
    readonly symbols: Symbol[] = [];
    readonly relocations: Relocation[] = [];

    constructor(name: string) {
        this.name = name;
    }

    addSection(name: string, size: number): void {
        this.sections.set(name, {
            name,
            data: new Uint8Array(size),
            size,
        });
    }

    addSymbol(sym: Symbol): void {
        this.symbols.push(sym);
    }

    addRelocation(reloc: Relocation): void {
        this.relocations.push(reloc);
    }
}

// ── Static Linker ────────────────────────────────────────────────────
// Merges object files: concatenate sections, build global symbol table,
// apply relocations with final addresses.

interface LinkedSymbol {
    name: string;
    address: number;
    binding: SymbolBinding;
}

class StaticLinker {
    private globalSymbols: Map<string, LinkedSymbol> = new Map();
    private sectionBases: Map<string, number> = new Map();
    private outputData: Map<string, Uint8Array> = new Map();
    private errors: string[] = [];

    link(objects: ObjectFile[]): { symbols: Map<string, LinkedSymbol>; errors: string[] } {
        this.globalSymbols.clear();
        this.sectionBases.clear();
        this.errors = [];

        // Phase 1: assign section base addresses
        let currentAddress = 0x400000; // typical ELF text base
        const sectionSizes: Map<string, number> = new Map();

        for (const obj of objects) {
            for (const [secName, section] of obj.sections) {
                const existing = sectionSizes.get(secName) ?? 0;
                sectionSizes.set(secName, existing + section.size);
            }
        }

        for (const [secName, totalSize] of sectionSizes) {
            this.sectionBases.set(secName, currentAddress);
            this.outputData.set(secName, new Uint8Array(totalSize));
            currentAddress += totalSize;
            // Align to 4096 (page boundary)
            currentAddress = (currentAddress + 0xfff) & ~0xfff;
        }

        // Phase 2: collect symbols with final addresses
        const sectionOffsets: Map<string, number> = new Map(); // per-section cursor

        for (const obj of objects) {
            for (const sym of obj.symbols) {
                if (sym.symbolKind === "undefined") continue;

                const secBase = this.sectionBases.get(sym.section);
                if (secBase === undefined) {
                    this.errors.push(`unknown section ${sym.section} for symbol ${sym.name}`);
                    continue;
                }

                const secOff = sectionOffsets.get(`${obj.name}:${sym.section}`) ?? 0;
                const address = secBase + secOff + sym.offset;

                const existing = this.globalSymbols.get(sym.name);
                if (existing && existing.binding === "global" && sym.binding === "global") {
                    this.errors.push(`duplicate symbol: ${sym.name}`);
                    continue;
                }
                if (existing && sym.binding === "weak") continue;

                this.globalSymbols.set(sym.name, {
                    name: sym.name,
                    address,
                    binding: sym.binding,
                });
            }

            // Advance section offsets for this object file
            for (const [secName, section] of obj.sections) {
                const key = `${obj.name}:${secName}`;
                sectionOffsets.set(key, (sectionOffsets.get(key) ?? 0) + section.size);
            }
        }

        // Phase 3: check for undefined symbols
        for (const obj of objects) {
            for (const reloc of obj.relocations) {
                if (!this.globalSymbols.has(reloc.symbolName)) {
                    this.errors.push(`undefined reference to '${reloc.symbolName}'`);
                }
            }
        }

        // Phase 4: apply relocations
        for (const obj of objects) {
            for (const reloc of obj.relocations) {
                const sym = this.globalSymbols.get(reloc.symbolName);
                if (!sym) continue;

                const resolved = sym.address + reloc.addend;
                // In a real linker, we'd write resolved into the output section.
                // Here we just verify resolution succeeds.
            }
        }

        return { symbols: new Map(this.globalSymbols), errors: [...this.errors] };
    }
}

// ── GOT / PLT simulation ────────────────────────────────────────────
// In position-independent code, the GOT holds absolute addresses.
// The PLT provides lazy-binding stubs: first call goes through the
// dynamic linker, subsequent calls go directly.

interface GOTEntry {
    symbolName: string;
    resolvedAddress: number | null; // null = not yet resolved
}

interface PLTEntry {
    symbolName: string;
    gotIndex: number;
    resolved: boolean;
}

class DynamicLinker {
    private got: GOTEntry[] = [];
    private plt: PLTEntry[] = [];
    private gotMap: Map<string, number> = new Map();
    private knownSymbols: Map<string, number> = new Map();

    // Register a shared library's exported symbols
    registerLibrary(symbols: Map<string, number>): void {
        for (const [name, addr] of symbols) {
            this.knownSymbols.set(name, addr);
        }
    }

    // Create a GOT entry for a symbol
    allocGOT(symbolName: string): number {
        const existing = this.gotMap.get(symbolName);
        if (existing !== undefined) return existing;

        const index = this.got.length;
        this.got.push({ symbolName, resolvedAddress: null });
        this.gotMap.set(symbolName, index);
        return index;
    }

    // Create a PLT stub for a function
    allocPLT(symbolName: string): number {
        const gotIndex = this.allocGOT(symbolName);
        const pltIndex = this.plt.length;
        this.plt.push({ symbolName, gotIndex, resolved: false });
        return pltIndex;
    }

    // Simulate lazy binding: resolve on first call
    callPLT(pltIndex: number): number {
        const entry = this.plt[pltIndex];
        if (!entry.resolved) {
            // First call — resolve through dynamic linker
            const addr = this.knownSymbols.get(entry.symbolName);
            if (addr === undefined) {
                throw new Error(`unresolved dynamic symbol: ${entry.symbolName}`);
            }
            this.got[entry.gotIndex].resolvedAddress = addr;
            entry.resolved = true;
        }

        const gotEntry = this.got[entry.gotIndex];
        return gotEntry.resolvedAddress!;
    }

    // Direct GOT lookup (for data references)
    resolveGOT(symbolName: string): number {
        const index = this.gotMap.get(symbolName);
        if (index === undefined) throw new Error(`no GOT entry for: ${symbolName}`);

        const entry = this.got[index];
        if (entry.resolvedAddress === null) {
            const addr = this.knownSymbols.get(symbolName);
            if (addr === undefined) throw new Error(`unresolved: ${symbolName}`);
            entry.resolvedAddress = addr;
        }

        return entry.resolvedAddress;
    }

    getGOTSize(): number { return this.got.length; }
    getPLTSize(): number { return this.plt.length; }
}

// ── Tests ────────────────────────────────────────────────────────────

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

function testObjectFileCreation(): void {
    const obj = new ObjectFile("main.o");
    obj.addSection(".text", 64);
    obj.addSection(".data", 16);
    obj.addSymbol({
        name: "main", binding: "global", symbolKind: "function",
        section: ".text", offset: 0, size: 32,
    });
    obj.addSymbol({
        name: "printf", binding: "global", symbolKind: "undefined",
        section: "", offset: 0, size: 0,
    });
    obj.addRelocation({
        offset: 10, type: "R_X86_64_PLT", symbolName: "printf", addend: -4,
    });

    assert(obj.sections.size === 2, "two sections");
    assert(obj.symbols.length === 2, "two symbols");
    assert(obj.relocations.length === 1, "one relocation");
}

function testStaticLinking(): void {
    const main = new ObjectFile("main.o");
    main.addSection(".text", 32);
    main.addSymbol({
        name: "main", binding: "global", symbolKind: "function",
        section: ".text", offset: 0, size: 32,
    });
    main.addRelocation({
        offset: 16, type: "R_X86_64_PC32", symbolName: "helper", addend: -4,
    });

    const helper = new ObjectFile("helper.o");
    helper.addSection(".text", 16);
    helper.addSymbol({
        name: "helper", binding: "global", symbolKind: "function",
        section: ".text", offset: 0, size: 16,
    });

    const linker = new StaticLinker();
    const result = linker.link([main, helper]);

    assert(result.errors.length === 0, `no errors: ${result.errors.join(", ")}`);
    assert(result.symbols.has("main"), "main resolved");
    assert(result.symbols.has("helper"), "helper resolved");

    const mainSym = result.symbols.get("main")!;
    const helperSym = result.symbols.get("helper")!;
    assert(mainSym.address >= 0x400000, "main in expected range");
    assert(helperSym.address >= 0x400000, "helper in expected range");
}

function testUndefinedSymbolError(): void {
    const obj = new ObjectFile("broken.o");
    obj.addSection(".text", 16);
    obj.addRelocation({
        offset: 4, type: "R_X86_64_PC32", symbolName: "missing_func", addend: -4,
    });

    const linker = new StaticLinker();
    const result = linker.link([obj]);

    assert(result.errors.some(e => e.includes("undefined reference")),
        "should report undefined reference");
}

function testDuplicateSymbolError(): void {
    const a = new ObjectFile("a.o");
    a.addSection(".text", 16);
    a.addSymbol({
        name: "foo", binding: "global", symbolKind: "function",
        section: ".text", offset: 0, size: 16,
    });

    const b = new ObjectFile("b.o");
    b.addSection(".text", 16);
    b.addSymbol({
        name: "foo", binding: "global", symbolKind: "function",
        section: ".text", offset: 0, size: 16,
    });

    const linker = new StaticLinker();
    const result = linker.link([a, b]);

    assert(result.errors.some(e => e.includes("duplicate symbol")),
        "should report duplicate symbol");
}

function testWeakSymbols(): void {
    const strong = new ObjectFile("strong.o");
    strong.addSection(".text", 16);
    strong.addSymbol({
        name: "handler", binding: "global", symbolKind: "function",
        section: ".text", offset: 0, size: 16,
    });

    const weak = new ObjectFile("weak.o");
    weak.addSection(".text", 8);
    weak.addSymbol({
        name: "handler", binding: "weak", symbolKind: "function",
        section: ".text", offset: 0, size: 8,
    });

    const linker = new StaticLinker();
    const result = linker.link([strong, weak]);

    assert(result.errors.length === 0, "weak + strong should not conflict");
    assert(result.symbols.get("handler")!.binding === "global",
        "strong definition wins over weak");
}

function testGOTPLT(): void {
    const dl = new DynamicLinker();

    // Simulate libc exports
    const libc = new Map<string, number>();
    libc.set("printf", 0x7f0001000);
    libc.set("malloc", 0x7f0002000);
    libc.set("errno", 0x7f0003000);
    dl.registerLibrary(libc);

    // Allocate PLT entries for functions
    const printfPLT = dl.allocPLT("printf");
    const mallocPLT = dl.allocPLT("malloc");

    // Allocate GOT entry for data
    dl.allocGOT("errno");

    assert(dl.getGOTSize() === 3, "three GOT entries");
    assert(dl.getPLTSize() === 2, "two PLT entries");

    // First call through PLT — triggers lazy binding
    const addr1 = dl.callPLT(printfPLT);
    assert(addr1 === 0x7f0001000, "printf resolved correctly");

    // Second call — already resolved, no re-resolution
    const addr2 = dl.callPLT(printfPLT);
    assert(addr2 === 0x7f0001000, "printf still correct on second call");

    // malloc
    const mallocAddr = dl.callPLT(mallocPLT);
    assert(mallocAddr === 0x7f0002000, "malloc resolved correctly");

    // Direct GOT lookup for data
    const errnoAddr = dl.resolveGOT("errno");
    assert(errnoAddr === 0x7f0003000, "errno resolved via GOT");
}

function testUnresolvedDynamic(): void {
    const dl = new DynamicLinker();
    const pltIdx = dl.allocPLT("nonexistent");

    let caught = false;
    try {
        dl.callPLT(pltIdx);
    } catch (e) {
        caught = (e as Error).message.includes("unresolved dynamic symbol");
    }
    assert(caught, "should throw on unresolved dynamic symbol");
}

// ── Main ─────────────────────────────────────────────────────────────

function main(): void {
    testObjectFileCreation();
    testStaticLinking();
    testUndefinedSymbolError();
    testDuplicateSymbolError();
    testWeakSymbols();
    testGOTPLT();
    testUnresolvedDynamic();

    console.log("All linking and loading tests passed.");
}

main();
