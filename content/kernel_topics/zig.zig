// Vidya — Kernel Topics in Zig
//
// Zig is designed for systems programming: packed structs map to
// hardware registers, comptime generates descriptor tables, volatile
// pointers enforce MMIO semantics, and no hidden allocations. Zig
// is used in real kernel work (e.g., Bun's I/O layer, RTOS projects).

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

pub fn main() !void {
    try testPageTableEntry();
    try testVaddrDecompose();
    try testMmioRegister();
    try testInterruptTable();
    try testGdtEntry();
    try testAbiLayout();

    std.debug.print("All kernel topics examples passed.\n", .{});
}

// ── Page Table Entry (x86_64) ─────────────────────────────────────────
const PteFlags = struct {
    const PRESENT: u64 = 1 << 0;
    const WRITABLE: u64 = 1 << 1;
    const USER: u64 = 1 << 2;
    const WRITE_THROUGH: u64 = 1 << 3;
    const NO_CACHE: u64 = 1 << 4;
    const ACCESSED: u64 = 1 << 5;
    const DIRTY: u64 = 1 << 6;
    const HUGE_PAGE: u64 = 1 << 7;
    const NO_EXECUTE: u64 = @as(u64, 1) << 63;
    const ADDR_MASK: u64 = 0x000F_FFFF_FFFF_F000;
};

const PageTableEntry = struct {
    raw: u64,

    fn new(phys_addr: u64, flags: u64) PageTableEntry {
        return .{ .raw = (phys_addr & PteFlags.ADDR_MASK) | flags };
    }

    fn present(self: PageTableEntry) bool { return self.raw & PteFlags.PRESENT != 0; }
    fn writable(self: PageTableEntry) bool { return self.raw & PteFlags.WRITABLE != 0; }
    fn user(self: PageTableEntry) bool { return self.raw & PteFlags.USER != 0; }
    fn noExecute(self: PageTableEntry) bool { return self.raw & PteFlags.NO_EXECUTE != 0; }
    fn physAddr(self: PageTableEntry) u64 { return self.raw & PteFlags.ADDR_MASK; }
};

fn testPageTableEntry() !void {
    const code = PageTableEntry.new(0x1000, PteFlags.PRESENT);
    try expect(code.present());
    try expect(!code.writable());
    try expect(code.physAddr() == 0x1000);

    const data = PageTableEntry.new(0x200_000, PteFlags.PRESENT | PteFlags.WRITABLE | PteFlags.USER | PteFlags.NO_EXECUTE);
    try expect(data.present() and data.writable() and data.user() and data.noExecute());

    const unmapped = PageTableEntry{ .raw = 0 };
    try expect(!unmapped.present());

    const uncacheable = PageTableEntry.new(0x3000, PteFlags.PRESENT | PteFlags.NO_CACHE | PteFlags.WRITE_THROUGH);
    try expect(uncacheable.raw & PteFlags.NO_CACHE != 0);
}

// ── Virtual Address Decomposition ─────────────────────────────────────
const VAddrParts = struct {
    pml4: u9,
    pdpt: u9,
    pd: u9,
    pt: u9,
    offset: u12,
};

fn decomposeVaddr(vaddr: u64) VAddrParts {
    return .{
        .pml4 = @truncate((vaddr >> 39) & 0x1FF),
        .pdpt = @truncate((vaddr >> 30) & 0x1FF),
        .pd = @truncate((vaddr >> 21) & 0x1FF),
        .pt = @truncate((vaddr >> 12) & 0x1FF),
        .offset = @truncate(vaddr & 0xFFF),
    };
}

fn testVaddrDecompose() !void {
    const p = decomposeVaddr(0x0000_7FFF_FFFF_F000);
    try expect(p.pml4 == 0xFF);
    try expect(p.pdpt == 0x1FF);
    try expect(p.pd == 0x1FF);
    try expect(p.pt == 0x1FF);
    try expect(p.offset == 0);

    const k = decomposeVaddr(0xFFFF_8000_0000_0000);
    try expect(k.pml4 == 256);
}

// ── MMIO Register ─────────────────────────────────────────────────────
// In a real kernel: var reg: *volatile u32 = @ptrFromInt(0xFE000000);
const MmioRegister = struct {
    value: u32,
    name: []const u8,

    fn read(self: *const MmioRegister) u32 {
        return self.value;
    }

    fn write(self: *MmioRegister, val: u32) void {
        self.value = val;
    }

    fn setBits(self: *MmioRegister, mask: u32) void {
        self.write(self.read() | mask);
    }

    fn clearBits(self: *MmioRegister, mask: u32) void {
        self.write(self.read() & ~mask);
    }
};

fn testMmioRegister() !void {
    var ctrl = MmioRegister{ .value = 0, .name = "UART_CTRL" };
    ctrl.setBits(0b11);
    try expect(ctrl.read() == 0b11);

    ctrl.clearBits(0b10);
    try expect(ctrl.read() == 0b01);
}

// ── Interrupt Table ───────────────────────────────────────────────────
const InterruptHandler = *const fn (vector: u8) []const u8;

const IdtEntry = struct {
    vector: u8,
    name: []const u8,
    handler: InterruptHandler,
    ist: u8,
};

fn handleDE(_: u8) []const u8 { return "handled: #DE"; }
fn handleDF(_: u8) []const u8 { return "handled: #DF"; }
fn handlePF(_: u8) []const u8 { return "handled: #PF"; }
fn handleTimer(_: u8) []const u8 { return "handled: timer"; }

fn testInterruptTable() !void {
    const idt = [_]IdtEntry{
        .{ .vector = 0, .name = "Divide Error", .handler = &handleDE, .ist = 0 },
        .{ .vector = 8, .name = "Double Fault", .handler = &handleDF, .ist = 1 },
        .{ .vector = 14, .name = "Page Fault", .handler = &handlePF, .ist = 0 },
        .{ .vector = 32, .name = "Timer", .handler = &handleTimer, .ist = 0 },
    };

    try expect(mem.eql(u8, idt[0].handler(0), "handled: #DE"));
    try expect(mem.eql(u8, idt[2].handler(14), "handled: #PF"));
    try expect(idt[1].ist > 0); // double fault uses IST
    try expect(mem.eql(u8, idt[1].name, "Double Fault"));
}

// ── GDT Entry ─────────────────────────────────────────────────────────
const GdtEntry = struct {
    raw: u64,

    fn null_entry() GdtEntry { return .{ .raw = 0 }; }
    fn kernelCode() GdtEntry { return .{ .raw = 0x00AF_9A00_0000_FFFF }; }
    fn kernelData() GdtEntry { return .{ .raw = 0x00CF_9200_0000_FFFF }; }

    fn present(self: GdtEntry) bool { return (self.raw >> 47) & 1 == 1; }
    fn dpl(self: GdtEntry) u2 { return @truncate((self.raw >> 45) & 0x3); }
    fn longMode(self: GdtEntry) bool { return (self.raw >> 53) & 1 == 1; }
};

fn testGdtEntry() !void {
    const null_seg = GdtEntry.null_entry();
    try expect(!null_seg.present());

    const code = GdtEntry.kernelCode();
    try expect(code.present());
    try expect(code.dpl() == 0);
    try expect(code.longMode());

    const data = GdtEntry.kernelData();
    try expect(data.present());
    try expect(data.dpl() == 0);

    // Minimal GDT: null + code + data
    const gdt = [_]GdtEntry{ GdtEntry.null_entry(), GdtEntry.kernelCode(), GdtEntry.kernelData() };
    try expect(gdt.len == 3);
    try expect(!gdt[0].present());
    try expect(gdt[1].present());
}

// ── ABI Struct Layout ─────────────────────────────────────────────────
// Packed structs in Zig match hardware layout exactly
const IcmpHeader = packed struct {
    msg_type: u8,
    code: u8,
    checksum: u16,
    data: u32,
};

const TrapFrame = packed struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
    esi: u32,
    edi: u32,
    ebp: u32,
    esp: u32,
    rip: u64,
    rflags: u64,
};

fn testAbiLayout() !void {
    // ICMP header: exactly 8 bytes, no padding
    try expect(@sizeOf(IcmpHeader) == 8);

    // Trap frame: 8*4 + 2*8 = 48 bytes
    try expect(@sizeOf(TrapFrame) == 48);

    // Verify field access on packed struct
    const icmp = IcmpHeader{ .msg_type = 8, .code = 0, .checksum = 0x1234, .data = 0xDEADBEEF };
    try expect(icmp.msg_type == 8);
    try expect(icmp.data == 0xDEADBEEF);
}
