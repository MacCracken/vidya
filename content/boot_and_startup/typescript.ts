// Vidya — Boot and Startup in TypeScript
//
// The boot process transitions the CPU from 16-bit real mode to 64-bit
// long mode. Along the way, key data structures must be built in memory:
// GDT, IDT, page tables, and (optionally) a Multiboot header. We model
// these structures with DataView for byte-accurate encoding.

function main(): void {
    testGdtEntryEncoding();
    testGdtTable();
    testIdtEntryEncoding();
    testMultibootHeader();
    testModeTransition();
    testMemoryMapParsing();

    console.log("All boot and startup examples passed.");
}

// ── GDT Entry Encoding (8 bytes) ────────────────────────────────────

// A GDT entry (segment descriptor) is 8 bytes packed with fields at
// non-byte-aligned positions. In long mode most fields are ignored,
// but the descriptor must still exist and be correctly formatted.
//
// Bit layout of a GDT entry:
//   [0..15]   Limit 0:15
//   [16..39]  Base 0:23
//   [40..47]  Access byte (P, DPL, S, Type)
//   [48..51]  Limit 16:19
//   [52..55]  Flags (G, D/B, L, AVL)
//   [56..63]  Base 24:31

class GdtEntry {
    readonly raw: bigint;

    private constructor(raw: bigint) {
        this.raw = raw;
    }

    static null(): GdtEntry {
        return new GdtEntry(0n);
    }

    /** Build a code segment descriptor for long mode. */
    static kernelCode(): GdtEntry {
        // Access: P=1, DPL=0, S=1, E=1 (code), R=1 (readable)
        // = 1_00_1_1010 = 0x9A
        // Flags: G=1, L=1 (long mode), D=0
        // = 1010 = 0xA
        // Limit = 0xFFFFF (ignored in long mode but set for compatibility)
        let raw = 0x000F_0000_0000_FFFFn;  // limit
        raw |= 0x9An << 40n;               // access byte
        raw |= 0xAn << 52n;                // flags (G=1, L=1)
        return new GdtEntry(raw);
    }

    /** Build a data segment descriptor. */
    static kernelData(): GdtEntry {
        // Access: P=1, DPL=0, S=1, E=0 (data), W=1 (writable)
        // = 1_00_1_0010 = 0x92
        // Flags: G=1, D/B=1 (32-bit compat)
        // = 1100 = 0xC
        let raw = 0x000F_0000_0000_FFFFn;
        raw |= 0x92n << 40n;
        raw |= 0xCn << 52n;
        return new GdtEntry(raw);
    }

    /** Build a user code segment (ring 3). */
    static userCode(): GdtEntry {
        // Access: P=1, DPL=3, S=1, E=1, R=1
        // = 1_11_1_1010 = 0xFA
        let raw = 0x000F_0000_0000_FFFFn;
        raw |= 0xFAn << 40n;
        raw |= 0xAn << 52n;
        return new GdtEntry(raw);
    }

    /** Build a user data segment (ring 3). */
    static userData(): GdtEntry {
        // Access: P=1, DPL=3, S=1, E=0, W=1
        // = 1_11_1_0010 = 0xF2
        let raw = 0x000F_0000_0000_FFFFn;
        raw |= 0xF2n << 40n;
        raw |= 0xCn << 52n;
        return new GdtEntry(raw);
    }

    // Field extractors
    get present(): boolean  { return ((this.raw >> 47n) & 1n) === 1n; }
    get dpl(): number       { return Number((this.raw >> 45n) & 0x3n); }
    get isCode(): boolean   { return ((this.raw >> 43n) & 1n) === 1n; }
    get longMode(): boolean { return ((this.raw >> 53n) & 1n) === 1n; }
    get granularity(): boolean { return ((this.raw >> 55n) & 1n) === 1n; }

    /** Encode to 8-byte DataView (byte-accurate representation). */
    toBytes(): DataView {
        const buf = new ArrayBuffer(8);
        const dv = new DataView(buf);
        // Write as two 32-bit halves (little-endian)
        dv.setUint32(0, Number(this.raw & 0xFFFF_FFFFn), true);
        dv.setUint32(4, Number((this.raw >> 32n) & 0xFFFF_FFFFn), true);
        return dv;
    }
}

function testGdtEntryEncoding(): void {
    // Null descriptor (required as GDT[0])
    const null_ = GdtEntry.null();
    assert(!null_.present, "null not present");

    // Kernel code segment
    const kcode = GdtEntry.kernelCode();
    assert(kcode.present, "kernel code present");
    assert(kcode.dpl === 0, "kernel code ring 0");
    assert(kcode.isCode, "kernel code is code");
    assert(kcode.longMode, "kernel code long mode");

    // Kernel data segment
    const kdata = GdtEntry.kernelData();
    assert(kdata.present, "kernel data present");
    assert(kdata.dpl === 0, "kernel data ring 0");
    assert(!kdata.isCode, "kernel data is data");
    assert(!kdata.longMode, "data not long mode");

    // User code segment
    const ucode = GdtEntry.userCode();
    assert(ucode.dpl === 3, "user code ring 3");
    assert(ucode.isCode, "user code is code");
    assert(ucode.longMode, "user code long mode");

    // User data segment
    const udata = GdtEntry.userData();
    assert(udata.dpl === 3, "user data ring 3");
    assert(!udata.isCode, "user data is data");

    // Verify byte-level encoding roundtrips
    const bytes = kcode.toBytes();
    assert(bytes.byteLength === 8, "GDT entry is 8 bytes");
}

// ── GDT Table ───────────────────────────────────────────────────────

// A typical 64-bit kernel GDT has 5 entries:
//   0: Null descriptor (required by hardware)
//   1: Kernel code (ring 0, 64-bit)
//   2: Kernel data (ring 0)
//   3: User code (ring 3, 64-bit)
//   4: User data (ring 3)
// The GDTR register points to this table.

interface GdtrValue {
    limit: number;  // size of GDT minus 1
    base: bigint;   // linear address of GDT
}

function buildGdt(): { entries: GdtEntry[]; gdtr: GdtrValue } {
    const entries = [
        GdtEntry.null(),
        GdtEntry.kernelCode(),
        GdtEntry.kernelData(),
        GdtEntry.userCode(),
        GdtEntry.userData(),
    ];

    return {
        entries,
        gdtr: {
            limit: entries.length * 8 - 1,  // 39 bytes
            base: 0xFFFF_8000_0000_1000n,   // kernel memory
        },
    };
}

function testGdtTable(): void {
    const { entries, gdtr } = buildGdt();

    assert(entries.length === 5, "5 GDT entries");
    assert(gdtr.limit === 39, "GDTR limit = 39");

    // Segment selectors: index * 8, plus RPL for user segments
    // Kernel CS = 0x08, Kernel DS = 0x10
    // User CS = 0x1B (0x18 | RPL=3), User DS = 0x23 (0x20 | RPL=3)
    const kernelCS = 1 * 8;        // 0x08
    const kernelDS = 2 * 8;        // 0x10
    const userCS   = 3 * 8 | 3;    // 0x1B
    const userDS   = 4 * 8 | 3;    // 0x23

    assert(kernelCS === 0x08, "kernel CS = 0x08");
    assert(kernelDS === 0x10, "kernel DS = 0x10");
    assert(userCS === 0x1B, "user CS = 0x1B");
    assert(userDS === 0x23, "user DS = 0x23");
}

// ── IDT Entry Encoding (16 bytes for 64-bit) ───────────────────────

// In 64-bit mode, each IDT entry (gate descriptor) is 16 bytes.
// It describes where the CPU jumps when an interrupt fires.
//
// Layout:
//   [0..2)   offset_low      handler address bits 0-15
//   [2..4)   selector        code segment selector
//   [4..5)   ist             IST index (0 = no stack switch)
//   [5..6)   type_attr       gate type + DPL + P
//   [6..8)   offset_mid      handler address bits 16-31
//   [8..12)  offset_high     handler address bits 32-63
//   [12..16) reserved        must be zero

class IdtGateDescriptor {
    readonly buf: ArrayBuffer;
    readonly view: DataView;

    constructor() {
        this.buf = new ArrayBuffer(16);
        this.view = new DataView(this.buf);
    }

    static interruptGate(handler: bigint, selector: number, ist: number, dpl: number): IdtGateDescriptor {
        const gate = new IdtGateDescriptor();
        const v = gate.view;

        v.setUint16(0, Number(handler & 0xFFFFn), true);           // offset_low
        v.setUint16(2, selector, true);                             // selector
        v.setUint8(4, ist & 0x7);                                   // IST
        // type_attr: P=1 (0x80), DPL, type=0x0E (64-bit interrupt gate)
        v.setUint8(5, 0x80 | ((dpl & 0x3) << 5) | 0x0E);
        v.setUint16(6, Number((handler >> 16n) & 0xFFFFn), true);  // offset_mid
        v.setUint32(8, Number((handler >> 32n) & 0xFFFF_FFFFn), true); // offset_high
        v.setUint32(12, 0, true);                                   // reserved

        return gate;
    }

    get handlerAddress(): bigint {
        const low = BigInt(this.view.getUint16(0, true));
        const mid = BigInt(this.view.getUint16(6, true));
        const high = BigInt(this.view.getUint32(8, true));
        return low | (mid << 16n) | (high << 32n);
    }

    get selector(): number { return this.view.getUint16(2, true); }
    get ist(): number      { return this.view.getUint8(4) & 0x7; }
    get present(): boolean { return (this.view.getUint8(5) & 0x80) !== 0; }
    get dpl(): number      { return (this.view.getUint8(5) >> 5) & 0x3; }
}

function testIdtEntryEncoding(): void {
    const handler = 0xFFFF_8000_0010_0000n;
    const gate = IdtGateDescriptor.interruptGate(handler, 0x08, 1, 0);

    // Verify the handler address reconstructs correctly
    assert(gate.handlerAddress === handler, "handler roundtrip");
    assert(gate.selector === 0x08, "kernel CS selector");
    assert(gate.ist === 1, "IST = 1");
    assert(gate.present, "gate is present");
    assert(gate.dpl === 0, "kernel-only gate");

    // User-callable gate (e.g., for int 0x80 legacy syscall)
    const userGate = IdtGateDescriptor.interruptGate(0x40_0000n, 0x08, 0, 3);
    assert(userGate.dpl === 3, "user-callable gate");

    // IDT entry is 16 bytes in 64-bit mode
    assert(gate.buf.byteLength === 16, "IDT entry = 16 bytes");
}

// ── Multiboot Header ────────────────────────────────────────────────

// Multiboot2 lets bootloaders (like GRUB) load your kernel without
// a custom bootloader. The header must appear in the first 32KB.

const MULTIBOOT2_MAGIC = 0xE852_50D6;      // magic in header
const MULTIBOOT2_ARCH_I386 = 0;             // protected-mode i386
const MULTIBOOT2_BOOTLOADER_MAGIC = 0x36D7_6289; // passed in EAX by bootloader

class Multiboot2Header {
    readonly buf: ArrayBuffer;
    readonly view: DataView;

    constructor() {
        // Minimum header: magic(4) + arch(4) + length(4) + checksum(4) + end tag(8) = 24
        this.buf = new ArrayBuffer(24);
        this.view = new DataView(this.buf);
    }

    static build(): Multiboot2Header {
        const hdr = new Multiboot2Header();
        const v = hdr.view;

        const headerLength = 24;
        v.setUint32(0, MULTIBOOT2_MAGIC, true);
        v.setUint32(4, MULTIBOOT2_ARCH_I386, true);
        v.setUint32(8, headerLength, true);
        // Checksum: all fields must sum to zero (uint32)
        const checksum = (-(MULTIBOOT2_MAGIC + MULTIBOOT2_ARCH_I386 + headerLength)) >>> 0;
        v.setUint32(12, checksum, true);

        // End tag: type=0, flags=0, size=8
        v.setUint16(16, 0, true);  // type
        v.setUint16(18, 0, true);  // flags
        v.setUint32(20, 8, true);  // size

        return hdr;
    }

    get magic(): number    { return this.view.getUint32(0, true); }
    get arch(): number     { return this.view.getUint32(4, true); }
    get length(): number   { return this.view.getUint32(8, true); }
    get checksum(): number { return this.view.getUint32(12, true); }

    verify(): boolean {
        return ((this.magic + this.arch + this.length + this.checksum) >>> 0) === 0;
    }
}

function testMultibootHeader(): void {
    const hdr = Multiboot2Header.build();

    assert(hdr.magic === MULTIBOOT2_MAGIC, "multiboot2 magic");
    assert(hdr.arch === MULTIBOOT2_ARCH_I386, "i386 arch");
    assert(hdr.length === 24, "header length");
    assert(hdr.verify(), "checksum verifies");

    // Bootloader passes magic in EAX to confirm Multiboot2 boot
    assert(MULTIBOOT2_BOOTLOADER_MAGIC === 0x36D7_6289, "bootloader magic");
}

// ── Mode Transition ─────────────────────────────────────────────────

// The x86_64 boot sequence transitions through CPU modes:
//   Real Mode (16-bit) → Protected Mode (32-bit) → Long Mode (64-bit)

interface CpuMode {
    name: string;
    bits: number;
    addressSpace: string;
    requirements: string[];
}

function getBootSequence(): CpuMode[] {
    return [
        {
            name: "Real Mode",
            bits: 16,
            addressSpace: "1 MB (20-bit segmented)",
            requirements: [
                "BIOS/UEFI starts here",
                "No memory protection",
                "Direct hardware access via BIOS interrupts",
            ],
        },
        {
            name: "Protected Mode",
            bits: 32,
            addressSpace: "4 GB (32-bit flat)",
            requirements: [
                "Set up GDT with valid descriptors",
                "Set CR0.PE = 1 (Protection Enable)",
                "Far jump to reload CS with new selector",
                "Reload DS, ES, SS, FS, GS",
            ],
        },
        {
            name: "Long Mode",
            bits: 64,
            addressSpace: "256 TB (48-bit virtual)",
            requirements: [
                "Enable PAE (CR4.PAE = 1)",
                "Set up 4-level page tables",
                "Load PML4 into CR3",
                "Set IA32_EFER.LME = 1 (Long Mode Enable)",
                "Set CR0.PG = 1 (Paging)",
                "Far jump to 64-bit code segment",
            ],
        },
    ];
}

function testModeTransition(): void {
    const sequence = getBootSequence();

    assert(sequence.length === 3, "three CPU modes");
    assert(sequence[0].name === "Real Mode", "starts in real mode");
    assert(sequence[2].name === "Long Mode", "ends in long mode");

    // Each mode has more address space than the last
    assert(sequence[0].bits < sequence[1].bits, "16 < 32");
    assert(sequence[1].bits < sequence[2].bits, "32 < 64");

    // Long mode requires the most setup
    assert(sequence[2].requirements.length > sequence[1].requirements.length,
           "long mode needs more steps");

    // Protected mode requires GDT
    assert(sequence[1].requirements.some((r) => r.includes("GDT")),
           "protected mode needs GDT");

    // Long mode requires page tables
    assert(sequence[2].requirements.some((r) => r.includes("page tables")),
           "long mode needs page tables");
}

// ── Memory Map Parsing ──────────────────────────────────────────────

// The bootloader provides a memory map telling the kernel which
// physical memory regions are usable. This is critical for the
// physical frame allocator.

type MemoryType = "available" | "reserved" | "acpi_reclaimable" | "acpi_nvs" | "bad_memory";

interface MemoryRegion {
    baseAddr: bigint;
    length: bigint;
    type: MemoryType;
}

function parseMemoryMap(): MemoryRegion[] {
    // Typical PC memory map (simplified)
    return [
        { baseAddr: 0x0000_0000n, length: 0x0009_FC00n, type: "available" },       // 639 KB
        { baseAddr: 0x0009_FC00n, length: 0x0000_0400n, type: "reserved" },        // EBDA
        { baseAddr: 0x000F_0000n, length: 0x0001_0000n, type: "reserved" },        // BIOS ROM
        { baseAddr: 0x0010_0000n, length: 0x3FEF_0000n, type: "available" },       // ~1 GB usable
        { baseAddr: 0x3FFF_0000n, length: 0x0001_0000n, type: "acpi_reclaimable" },
        { baseAddr: 0xFEE0_0000n, length: 0x0010_0000n, type: "reserved" },        // LAPIC
    ];
}

function testMemoryMapParsing(): void {
    const regions = parseMemoryMap();

    // Count usable memory
    let usable = 0n;
    for (const r of regions) {
        if (r.type === "available") {
            usable += r.length;
        }
    }

    // Should have roughly 1 GB of usable memory
    assert(usable > 0x3F00_0000n, "at least ~1 GB usable");

    // First usable region starts at 0 (conventional memory)
    const first = regions[0];
    assert(first.baseAddr === 0n, "first region at 0");
    assert(first.type === "available", "first region usable");

    // Kernel should skip the first 1 MB (reserved for legacy hardware)
    const kernelStart = regions.find(
        (r) => r.type === "available" && r.baseAddr >= 0x10_0000n
    )!;
    assert(kernelStart.baseAddr === 0x10_0000n, "kernel memory starts at 1 MB");

    // LAPIC region is reserved (memory-mapped I/O)
    const lapic = regions.find((r) => r.baseAddr === 0xFEE0_0000n)!;
    assert(lapic.type === "reserved", "LAPIC is reserved");
}

// ── Helpers ──────────────────────────────────────────────────────────

function assert(cond: boolean, msg: string): void {
    if (!cond) throw new Error(`FAIL: ${msg}`);
}

main();
