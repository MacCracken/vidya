// Vidya — Boot and Startup in Zig
//
// Zig is used in real OS/runtime projects (Bun, several hobby kernels).
// packed structs map GDT/IDT entries exactly to hardware layout. comptime
// builds descriptor tables at compile time. Bit manipulation for CR0/CR4
// control registers is natural with Zig's integer types.

const std = @import("std");
const expect = std.testing.expect;

pub fn main() !void {
    try testMultibootHeader();
    try testGdtEntry();
    try testGdtDescriptor();
    try testIdtGateDescriptor();
    try testCr0Bits();
    try testCr4Bits();
    try testPageTableSetup();
    try testBootStages();

    std.debug.print("All boot and startup examples passed.\n", .{});
}

// ── Multiboot Header ────────────────────────────────────────────────
// Multiboot specification: GRUB looks for this in the first 8K of the
// kernel binary. Magic + flags + checksum must sum to zero.
const MultibootHeader = extern struct {
    magic: u32,
    flags: u32,
    checksum: u32,
};

const MultibootConst = struct {
    const MAGIC: u32 = 0x1BADB002;
    const ALIGN: u32 = 1 << 0; // Align modules on page boundaries
    const MEMINFO: u32 = 1 << 1; // Provide memory map
    const VIDEO: u32 = 1 << 2; // Provide video mode info

    fn checksum(flags: u32) u32 {
        // magic + flags + checksum must equal 0 (mod 2^32)
        return 0 -% MAGIC -% flags;
    }
};

// Multiboot2 uses a different magic
const Multiboot2Const = struct {
    const MAGIC: u32 = 0xE85250D6;
    const ARCH_I386: u32 = 0;
};

fn testMultibootHeader() !void {
    comptime {
        std.debug.assert(@sizeOf(MultibootHeader) == 12);
    }

    const flags = MultibootConst.ALIGN | MultibootConst.MEMINFO;
    const hdr = MultibootHeader{
        .magic = MultibootConst.MAGIC,
        .flags = flags,
        .checksum = MultibootConst.checksum(flags),
    };

    // Verify the checksum property: all three fields sum to 0
    const sum = hdr.magic +% hdr.flags +% hdr.checksum;
    try expect(sum == 0);

    try expect(hdr.magic == 0x1BADB002);
    try expect(hdr.flags & MultibootConst.ALIGN != 0);
    try expect(hdr.flags & MultibootConst.MEMINFO != 0);
}

// ── GDT Entry (8 bytes) ─────────────────────────────────────────────
// Global Descriptor Table entries define memory segments in protected
// and long mode. In 64-bit long mode, most fields are ignored but the
// structure must still be present.
const GdtEntry = extern struct {
    limit_low: u16, // Segment limit bits 0-15
    base_low: u16, // Base address bits 0-15
    base_mid: u8, // Base address bits 16-23
    access: u8, // Access byte: P|DPL|S|Type
    flags_limit_hi: u8, // Flags (4 bits) + limit bits 16-19
    base_high: u8, // Base address bits 24-31
};

// Access byte bits
const GdtAccess = struct {
    const PRESENT: u8 = 1 << 7; // Segment present
    const DPL_RING0: u8 = 0 << 5; // Privilege level 0
    const DPL_RING3: u8 = 3 << 5; // Privilege level 3
    const CODE_DATA: u8 = 1 << 4; // Code/data (vs system)
    const EXECUTABLE: u8 = 1 << 3; // Code segment
    const RW: u8 = 1 << 1; // Read (code) / Write (data)
    const ACCESSED: u8 = 1 << 0;
};

// Flags nibble (upper 4 bits of flags_limit_hi)
const GdtFlags = struct {
    const GRANULARITY: u8 = 1 << 7; // 4K granularity
    const SIZE_32: u8 = 1 << 6; // 32-bit protected mode
    const LONG_MODE: u8 = 1 << 5; // 64-bit long mode
};

fn makeGdtEntry(base: u32, limit: u20, access: u8, flags: u8) GdtEntry {
    return .{
        .limit_low = @truncate(limit),
        .base_low = @truncate(base),
        .base_mid = @truncate(base >> 16),
        .access = access,
        .flags_limit_hi = flags | @as(u8, @truncate(limit >> 16)),
        .base_high = @truncate(base >> 24),
    };
}

fn testGdtEntry() !void {
    comptime {
        std.debug.assert(@sizeOf(GdtEntry) == 8);
    }

    // Null descriptor — first GDT entry must be zero
    const null_entry = makeGdtEntry(0, 0, 0, 0);
    try expect(null_entry.access == 0);

    // Kernel code segment (64-bit long mode)
    const kernel_code = makeGdtEntry(
        0,
        0xFFFFF,
        GdtAccess.PRESENT | GdtAccess.DPL_RING0 | GdtAccess.CODE_DATA | GdtAccess.EXECUTABLE | GdtAccess.RW,
        GdtFlags.GRANULARITY | GdtFlags.LONG_MODE,
    );
    try expect(kernel_code.access & GdtAccess.PRESENT != 0);
    try expect(kernel_code.access & GdtAccess.EXECUTABLE != 0);
    try expect(kernel_code.flags_limit_hi & GdtFlags.LONG_MODE != 0);
    // Long mode: SIZE_32 must be clear
    try expect(kernel_code.flags_limit_hi & GdtFlags.SIZE_32 == 0);

    // Kernel data segment
    const kernel_data = makeGdtEntry(
        0,
        0xFFFFF,
        GdtAccess.PRESENT | GdtAccess.DPL_RING0 | GdtAccess.CODE_DATA | GdtAccess.RW,
        GdtFlags.GRANULARITY | GdtFlags.SIZE_32,
    );
    try expect(kernel_data.access & GdtAccess.PRESENT != 0);
    try expect(kernel_data.access & GdtAccess.EXECUTABLE == 0); // data, not code

    // User code segment (ring 3)
    const user_code = makeGdtEntry(
        0,
        0xFFFFF,
        GdtAccess.PRESENT | GdtAccess.DPL_RING3 | GdtAccess.CODE_DATA | GdtAccess.EXECUTABLE | GdtAccess.RW,
        GdtFlags.GRANULARITY | GdtFlags.LONG_MODE,
    );
    try expect(user_code.access & GdtAccess.DPL_RING3 == GdtAccess.DPL_RING3);
}

// ── GDT Descriptor (GDTR) ───────────────────────────────────────────
// Loaded with the LGDT instruction. The hardware GDTR is 10 bytes
// (2-byte limit + 8-byte base), unaligned. In Zig we model the fields
// separately since neither packed nor extern struct gives exactly 10 bytes.
const GdtDescriptor = struct {
    limit: u16, // Size of GDT - 1
    base: u64, // Linear address of GDT

    /// Encode to the 10-byte on-disk/in-memory format
    fn encode(self: GdtDescriptor) [10]u8 {
        var buf: [10]u8 = undefined;
        @memcpy(buf[0..2], &std.mem.toBytes(self.limit));
        @memcpy(buf[2..10], &std.mem.toBytes(self.base));
        return buf;
    }
};

fn testGdtDescriptor() !void {
    // 5 entries: null + kernel code + kernel data + user code + user data
    const num_entries = 5;
    const gdtr = GdtDescriptor{
        .limit = @sizeOf(GdtEntry) * num_entries - 1,
        .base = 0xFFFF_8000_0000_0000,
    };

    try expect(gdtr.limit == 39); // 5 * 8 - 1
    try expect(gdtr.base > 0);

    // The encoded form is exactly 10 bytes as hardware expects
    const encoded = gdtr.encode();
    try expect(encoded.len == 10);
}

// ── IDT Gate Descriptor (16 bytes in 64-bit mode) ────────────────────
// Interrupt Descriptor Table entries point to interrupt handlers
const IdtGateDescriptor = packed struct {
    offset_low: u16, // Handler address bits 0-15
    selector: u16, // Code segment selector
    ist: u3, // Interrupt Stack Table index
    reserved0: u5, // Must be zero
    gate_type: u4, // 0xE = interrupt gate, 0xF = trap gate
    zero: u1, // Must be zero
    dpl: u2, // Descriptor Privilege Level
    present: u1, // Segment present
    offset_mid: u16, // Handler address bits 16-31
    offset_high: u32, // Handler address bits 32-63
    reserved1: u32, // Must be zero
};

const GateType = struct {
    const INTERRUPT: u4 = 0xE; // Clears IF (disables interrupts)
    const TRAP: u4 = 0xF; // Does not clear IF
};

fn makeIdtGate(handler: u64, selector: u16, ist: u3, gate_type: u4, dpl: u2) IdtGateDescriptor {
    return .{
        .offset_low = @truncate(handler),
        .selector = selector,
        .ist = ist,
        .reserved0 = 0,
        .gate_type = gate_type,
        .zero = 0,
        .dpl = dpl,
        .present = 1,
        .offset_mid = @truncate(handler >> 16),
        .offset_high = @truncate(handler >> 32),
        .reserved1 = 0,
    };
}

fn testIdtGateDescriptor() !void {
    comptime {
        std.debug.assert(@sizeOf(IdtGateDescriptor) == 16);
    }

    const handler_addr: u64 = 0xFFFF_8000_0010_0000;
    const gate = makeIdtGate(
        handler_addr,
        0x08, // kernel code segment
        0, // no IST
        GateType.INTERRUPT,
        0, // ring 0
    );

    try expect(gate.present == 1);
    try expect(gate.gate_type == GateType.INTERRUPT);
    try expect(gate.selector == 0x08);

    // Reconstruct handler address from split fields
    const reconstructed: u64 = @as(u64, gate.offset_low) |
        (@as(u64, gate.offset_mid) << 16) |
        (@as(u64, gate.offset_high) << 32);
    try expect(reconstructed == handler_addr);

    // Double fault handler must use IST to get a known-good stack
    const df_gate = makeIdtGate(handler_addr, 0x08, 1, GateType.INTERRUPT, 0);
    try expect(df_gate.ist == 1);
}

// ── CR0 Control Register ─────────────────────────────────────────────
// CR0 controls fundamental CPU modes
const CR0 = struct {
    const PE: u64 = 1 << 0; // Protected Mode Enable
    const MP: u64 = 1 << 1; // Monitor Coprocessor
    const EM: u64 = 1 << 2; // Emulation (no FPU)
    const TS: u64 = 1 << 3; // Task Switched
    const ET: u64 = 1 << 4; // Extension Type (387)
    const NE: u64 = 1 << 5; // Numeric Error
    const WP: u64 = 1 << 16; // Write Protect (enforce in ring 0)
    const AM: u64 = 1 << 18; // Alignment Mask
    const NW: u64 = 1 << 29; // Not Write-through
    const CD: u64 = 1 << 30; // Cache Disable
    const PG: u64 = 1 << 31; // Paging Enable
};

fn testCr0Bits() !void {
    // Typical long mode CR0 value
    const cr0 = CR0.PE | CR0.MP | CR0.ET | CR0.NE | CR0.WP | CR0.PG;

    try expect(cr0 & CR0.PE != 0); // protected mode on
    try expect(cr0 & CR0.PG != 0); // paging on
    try expect(cr0 & CR0.WP != 0); // write protect on (security)
    try expect(cr0 & CR0.EM == 0); // FPU emulation off
    try expect(cr0 & CR0.CD == 0); // cache enabled
}

// ── CR4 Control Register ─────────────────────────────────────────────
// CR4 controls extensions and security features
const CR4 = struct {
    const VME: u64 = 1 << 0; // Virtual 8086 Mode Extensions
    const PVI: u64 = 1 << 1; // Protected Virtual Interrupts
    const TSD: u64 = 1 << 2; // Time Stamp Disable
    const DE: u64 = 1 << 3; // Debugging Extensions
    const PSE: u64 = 1 << 4; // Page Size Extension (4MB pages)
    const PAE: u64 = 1 << 5; // Physical Address Extension (required for long mode)
    const MCE: u64 = 1 << 6; // Machine Check Enable
    const PGE: u64 = 1 << 7; // Page Global Enable
    const OSFXSR: u64 = 1 << 9; // SSE support
    const OSXMMEXCPT: u64 = 1 << 10; // SSE exceptions
    const UMIP: u64 = 1 << 11; // User-Mode Instruction Prevention
    const FSGSBASE: u64 = 1 << 16; // FS/GS base instructions
    const PCIDE: u64 = 1 << 17; // PCID Enable
    const OSXSAVE: u64 = 1 << 18; // XSAVE and extended states
    const SMEP: u64 = 1 << 20; // Supervisor Mode Exec Prevention
    const SMAP: u64 = 1 << 21; // Supervisor Mode Access Prevention
};

fn testCr4Bits() !void {
    // Modern kernel CR4: security features enabled
    const cr4 = CR4.PAE | CR4.PGE | CR4.OSFXSR | CR4.OSXMMEXCPT |
        CR4.FSGSBASE | CR4.SMEP | CR4.SMAP;

    try expect(cr4 & CR4.PAE != 0); // required for long mode
    try expect(cr4 & CR4.SMEP != 0); // prevent kernel exec of user pages
    try expect(cr4 & CR4.SMAP != 0); // prevent kernel read of user pages
    try expect(cr4 & CR4.OSFXSR != 0); // SSE enabled
}

// ── Page Table Setup (Boot) ──────────────────────────────────────────
// During boot, we set up identity mapping + higher-half mapping
const BootPte = struct {
    const PRESENT: u64 = 1 << 0;
    const WRITABLE: u64 = 1 << 1;
    const HUGE: u64 = 1 << 7; // 2MB pages for early boot
    const NO_EXECUTE: u64 = @as(u64, 1) << 63;
};

fn testPageTableSetup() !void {
    // 2MB huge page entries for early boot identity mapping
    // Map first 8MB: four 2MB pages
    var pdt: [4]u64 = undefined;
    for (&pdt, 0..) |*entry, i| {
        entry.* = (i * 0x200000) | BootPte.PRESENT | BootPte.WRITABLE | BootPte.HUGE;
    }

    try expect(pdt[0] & BootPte.PRESENT != 0);
    try expect(pdt[0] & BootPte.HUGE != 0);
    try expect(pdt[1] & 0x000F_FFFF_FFFF_F000 == 0x200000);
    try expect(pdt[2] & 0x000F_FFFF_FFFF_F000 == 0x400000);
    try expect(pdt[3] & 0x000F_FFFF_FFFF_F000 == 0x600000);
}

// ── Boot Stages ──────────────────────────────────────────────────────
const BootStage = enum {
    firmware, // BIOS/UEFI: hardware init, find bootloader
    bootloader, // GRUB/systemd-boot: load kernel, set up multiboot
    real_mode, // 16-bit: A20 line, get memory map
    protected_mode, // 32-bit: set up GDT, enable PE bit in CR0
    long_mode, // 64-bit: set up page tables, enable PAE+PG+LME
    kernel_early, // Stack, BSS clear, parse multiboot info
    kernel_main, // Full kernel: interrupts, scheduler, drivers
};

fn testBootStages() !void {
    const stages = [_]BootStage{
        .firmware,
        .bootloader,
        .real_mode,
        .protected_mode,
        .long_mode,
        .kernel_early,
        .kernel_main,
    };

    try expect(stages.len == 7);
    try expect(stages[0] == .firmware);
    try expect(stages[4] == .long_mode);
    try expect(stages[6] == .kernel_main);

    // The key transitions:
    // real → protected: set CR0.PE, load GDT
    // protected → long: set CR4.PAE, load PML4 into CR3, set EFER.LME, set CR0.PG
}
