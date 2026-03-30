// Vidya — Kernel Topics in TypeScript
//
// TypeScript works well for kernel tooling and simulation: parsing
// binary formats, modeling hardware registers, and visualizing
// page table walks. BigInt handles 64-bit values that regular
// numbers can't represent precisely.

function main(): void {
    testPageTableEntry();
    testVirtualAddressDecompose();
    testMmioRegister();
    testInterruptDescriptorTable();
    testAbiCallingConvention();
    testGdtEntry();
    testElfParsing();

    console.log("All kernel topics examples passed.");
}

// ── Page Table Entry ──────────────────────────────────────────────────
const PTE_PRESENT    = 1n << 0n;
const PTE_WRITABLE   = 1n << 1n;
const PTE_USER       = 1n << 2n;
const PTE_HUGE_PAGE  = 1n << 7n;
const PTE_NO_EXECUTE = 1n << 63n;
const PTE_ADDR_MASK  = 0x000F_FFFF_FFFF_F000n;

class PageTableEntry {
    constructor(public readonly raw: bigint) {}

    static new(physAddr: bigint, flags: bigint): PageTableEntry {
        if ((physAddr & ~PTE_ADDR_MASK) !== 0n) throw new Error("not 4KB aligned");
        return new PageTableEntry((physAddr & PTE_ADDR_MASK) | flags);
    }

    get present(): boolean    { return (this.raw & PTE_PRESENT) !== 0n; }
    get writable(): boolean   { return (this.raw & PTE_WRITABLE) !== 0n; }
    get user(): boolean       { return (this.raw & PTE_USER) !== 0n; }
    get noExecute(): boolean  { return (this.raw & PTE_NO_EXECUTE) !== 0n; }
    get physAddr(): bigint    { return this.raw & PTE_ADDR_MASK; }
}

function testPageTableEntry(): void {
    const code = PageTableEntry.new(0x1000n, PTE_PRESENT);
    assert(code.present, "code present");
    assert(!code.writable, "code not writable");
    assert(code.physAddr === 0x1000n, "code addr");

    const data = PageTableEntry.new(0x200000n, PTE_PRESENT | PTE_WRITABLE | PTE_USER | PTE_NO_EXECUTE);
    assert(data.writable && data.user && data.noExecute, "data flags");

    const unmapped = new PageTableEntry(0n);
    assert(!unmapped.present, "unmapped");
}

// ── Virtual Address Decomposition ─────────────────────────────────────
interface VAddrParts {
    pml4: number; pdpt: number; pd: number; pt: number; offset: number;
}

function decomposeVAddr(vaddr: bigint): VAddrParts {
    return {
        pml4:   Number((vaddr >> 39n) & 0x1FFn),
        pdpt:   Number((vaddr >> 30n) & 0x1FFn),
        pd:     Number((vaddr >> 21n) & 0x1FFn),
        pt:     Number((vaddr >> 12n) & 0x1FFn),
        offset: Number(vaddr & 0xFFFn),
    };
}

function testVirtualAddressDecompose(): void {
    const parts = decomposeVAddr(0x0000_7FFF_FFFF_F000n);
    assert(parts.pml4 === 0xFF, "pml4");
    assert(parts.pdpt === 0x1FF, "pdpt");
    assert(parts.pt === 0x1FF, "pt");
    assert(parts.offset === 0, "offset");

    const kernel = decomposeVAddr(0xFFFF_8000_0000_0000n);
    assert(kernel.pml4 === 256, "kernel pml4");
}

// ── MMIO Register ─────────────────────────────────────────────────────
class MmioRegister {
    private value: number = 0;
    constructor(public readonly name: string) {}

    read(): number { return this.value; }
    write(val: number): void { this.value = val >>> 0; } // force uint32
    setBits(mask: number): void { this.write(this.read() | mask); }
    clearBits(mask: number): void { this.write(this.read() & ~mask); }
    bit(n: number): boolean { return (this.read() & (1 << n)) !== 0; }
}

function testMmioRegister(): void {
    const ctrl = new MmioRegister("UART_CTRL");
    ctrl.setBits(0b11);
    assert(ctrl.read() === 0b11, "TX+RX");
    assert(ctrl.bit(0) && ctrl.bit(1), "bits set");

    ctrl.clearBits(0b10);
    assert(ctrl.read() === 0b01, "TX only");
}

// ── Interrupt Descriptor Table ────────────────────────────────────────
interface IdtEntry {
    vector: number;
    name: string;
    handler: (vector: number) => string;
    ist: number;
}

class IDT {
    private entries = new Map<number, IdtEntry>();

    register(vector: number, name: string, ist: number, handler: (v: number) => string): void {
        this.entries.set(vector, { vector, name, handler, ist });
    }

    dispatch(vector: number): string | null {
        const entry = this.entries.get(vector);
        return entry ? entry.handler(entry.vector) : null;
    }

    getEntry(vector: number): IdtEntry | undefined {
        return this.entries.get(vector);
    }
}

function testInterruptDescriptorTable(): void {
    const idt = new IDT();
    idt.register(0, "Divide Error", 0, () => "handled: #DE");
    idt.register(8, "Double Fault", 1, () => "handled: #DF");
    idt.register(14, "Page Fault", 0, () => "handled: #PF");
    idt.register(32, "Timer", 0, () => "handled: timer");

    assert(idt.dispatch(0) === "handled: #DE", "dispatch #DE");
    assert(idt.dispatch(14) === "handled: #PF", "dispatch #PF");
    assert(idt.dispatch(255) === null, "unregistered");
    assert(idt.getEntry(8)!.ist > 0, "double fault IST");
}

// ── ABI / Calling Convention ──────────────────────────────────────────
function testAbiCallingConvention(): void {
    const sysvRegs = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"];
    assert(sysvRegs[0] === "rdi", "sysv arg0");
    assert(sysvRegs[5] === "r9", "sysv arg5");
    assert(sysvRegs.length === 6, "sysv count");

    const syscallRegs = ["rax", "rdi", "rsi", "rdx", "r10", "r8", "r9"];
    assert(syscallRegs[0] === "rax", "syscall number");
    assert(syscallRegs[4] === "r10", "r10 not rcx");
}

// ── GDT Entry ─────────────────────────────────────────────────────────
function gdtPresent(raw: bigint): boolean  { return ((raw >> 47n) & 1n) === 1n; }
function gdtDPL(raw: bigint): number       { return Number((raw >> 45n) & 0x3n); }
function gdtLongMode(raw: bigint): boolean { return ((raw >> 53n) & 1n) === 1n; }

function testGdtEntry(): void {
    assert(!gdtPresent(0n), "null not present");

    const kernelCode = 0x00AF_9A00_0000_FFFFn;
    assert(gdtPresent(kernelCode), "code present");
    assert(gdtDPL(kernelCode) === 0, "code ring 0");
    assert(gdtLongMode(kernelCode), "code long mode");

    const kernelData = 0x00CF_9200_0000_FFFFn;
    assert(gdtPresent(kernelData), "data present");
}

// ── ELF Header Parsing ────────────────────────────────────────────────
function parseElfIdent(data: Uint8Array): { elfClass: string; endian: string; version: number } | null {
    if (data.length < 16) return null;
    if (data[0] !== 0x7F || data[1] !== 0x45 || data[2] !== 0x4C || data[3] !== 0x46) return null;

    const classes: Record<number, string> = { 1: "ELF32", 2: "ELF64" };
    const endians: Record<number, string> = { 1: "little", 2: "big" };

    return {
        elfClass: classes[data[4]] ?? "unknown",
        endian: endians[data[5]] ?? "unknown",
        version: data[6],
    };
}

function testElfParsing(): void {
    const header = new Uint8Array([0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0, ...new Array(8).fill(0)]);
    const info = parseElfIdent(header)!;
    assert(info.elfClass === "ELF64", "elf64");
    assert(info.endian === "little", "little endian");
    assert(info.version === 1, "version 1");

    assert(parseElfIdent(new Uint8Array([1, 2, 3])) === null, "not elf");
}

// ── Helpers ───────────────────────────────────────────────────────────
function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
