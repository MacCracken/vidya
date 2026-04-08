// Vidya — Instruction Encoding in Zig
//
// x86_64 byte-level encoding: REX prefix, ModR/M byte, MOV/ADD/JMP.
// Zig's packed structs map directly to hardware byte layouts — the
// ModR/M byte is a packed struct whose @bitCast gives the exact byte
// the CPU expects. This is how assemblers and JIT compilers emit
// machine code: build the encoding structs, cast to bytes.

const std = @import("std");
const expect = std.testing.expect;
const mem = std.mem;

pub fn main() !void {
    try testModRM();
    try testRexPrefix();
    try testMovRegImm();
    try testMovRegReg();
    try testAddRegReg();
    try testJmpRel32();
    try testRetEncoding();
    try testNopEncoding();

    std.debug.print("All instruction encoding examples passed.\n", .{});
}

// ── Register encoding ────────────────────────────────────────────────
// x86_64 register numbers used in ModR/M and REX fields.
const Reg = enum(u3) {
    rax = 0,
    rcx = 1,
    rdx = 2,
    rbx = 3,
    rsp = 4,
    rbp = 5,
    rsi = 6,
    rdi = 7,
};

// ── ModR/M byte ──────────────────────────────────────────────────────
// The ModR/M byte encodes: addressing mode (mod), register/opcode
// extension (reg), and register/memory operand (rm).
// Packed struct matches the actual bit layout.
const ModRM = packed struct {
    rm: u3, // bits [2:0]
    reg: u3, // bits [5:3]
    mod: u2, // bits [7:6]

    fn toByte(self: ModRM) u8 {
        return @bitCast(self);
    }

    /// Register-direct mode (mod=11): both operands are registers
    fn regDirect(reg: u3, rm: u3) ModRM {
        return .{ .mod = 0b11, .reg = reg, .rm = rm };
    }

    /// Memory indirect via register, no displacement (mod=00)
    fn memIndirect(reg: u3, rm: u3) ModRM {
        return .{ .mod = 0b00, .reg = reg, .rm = rm };
    }

    /// Memory + 8-bit displacement (mod=01)
    fn memDisp8(reg: u3, rm: u3) ModRM {
        return .{ .mod = 0b01, .reg = reg, .rm = rm };
    }

    /// Memory + 32-bit displacement (mod=10)
    fn memDisp32(reg: u3, rm: u3) ModRM {
        return .{ .mod = 0b10, .reg = reg, .rm = rm };
    }
};

// ── REX prefix ───────────────────────────────────────────────────────
// Required for 64-bit operand size and extended registers (r8–r15).
// Bit layout: 0100WRXB
const Rex = packed struct {
    b: u1 = 0, // extension of ModRM.rm or SIB base
    x: u1 = 0, // extension of SIB index
    r: u1 = 0, // extension of ModRM.reg
    w: u1 = 0, // 1 = 64-bit operand size
    fixed: u4 = 0b0100, // bits [7:4] always 0100

    fn toByte(self: Rex) u8 {
        return @bitCast(self);
    }

    /// REX.W — 64-bit operand size, no register extensions
    fn w64() Rex {
        return .{ .w = 1 };
    }

    /// REX.WR — 64-bit + extended reg field
    fn wr() Rex {
        return .{ .w = 1, .r = 1 };
    }
};

// ── Encoding helpers ─────────────────────────────────────────────────

/// MOV reg64, imm64 (REX.W + B8+rd + imm64)
/// This is the "movabs" form — loads a full 64-bit immediate.
fn encodeMoveRegImm64(reg: Reg, imm: u64) [10]u8 {
    var buf: [10]u8 = undefined;
    buf[0] = Rex.w64().toByte(); // REX.W
    buf[1] = 0xB8 + @as(u8, @intFromEnum(reg)); // B8+rd
    // Little-endian immediate
    inline for (0..8) |i| {
        buf[2 + i] = @truncate(imm >> @intCast(i * 8));
    }
    return buf;
}

/// MOV reg64, reg64 (REX.W + 89 /r)
fn encodeMoveRegReg(dst: Reg, src: Reg) [3]u8 {
    return .{
        Rex.w64().toByte(),
        0x89, // MOV r/m64, r64
        ModRM.regDirect(@intFromEnum(src), @intFromEnum(dst)).toByte(),
    };
}

/// ADD reg64, reg64 (REX.W + 01 /r)
fn encodeAddRegReg(dst: Reg, src: Reg) [3]u8 {
    return .{
        Rex.w64().toByte(),
        0x01, // ADD r/m64, r64
        ModRM.regDirect(@intFromEnum(src), @intFromEnum(dst)).toByte(),
    };
}

/// JMP rel32 (E9 + disp32)
fn encodeJmpRel32(displacement: i32) [5]u8 {
    var buf: [5]u8 = undefined;
    buf[0] = 0xE9;
    const d: u32 = @bitCast(displacement);
    inline for (0..4) |i| {
        buf[1 + i] = @truncate(d >> @intCast(i * 8));
    }
    return buf;
}

/// RET (C3)
fn encodeRet() [1]u8 {
    return .{0xC3};
}

/// NOP (90)
fn encodeNop() [1]u8 {
    return .{0x90};
}

// ── Tests ────────────────────────────────────────────────────────────
fn testModRM() !void {
    // ModR/M for MOV rax, rcx (mod=11, reg=rcx(1), rm=rax(0))
    const modrm = ModRM.regDirect(@intFromEnum(Reg.rcx), @intFromEnum(Reg.rax));
    try expect(modrm.mod == 0b11);
    try expect(modrm.reg == 1); // rcx
    try expect(modrm.rm == 0); // rax
    // Byte value: 11_001_000 = 0xC8
    try expect(modrm.toByte() == 0xC8);

    // ModR/M for memory indirect [rbx], reg=rax
    const mem_modrm = ModRM.memIndirect(@intFromEnum(Reg.rax), @intFromEnum(Reg.rbx));
    try expect(mem_modrm.mod == 0b00);
    // Byte: 00_000_011 = 0x03
    try expect(mem_modrm.toByte() == 0x03);

    // Verify packed struct is exactly 1 byte
    try expect(@sizeOf(ModRM) == 1);
}

fn testRexPrefix() !void {
    // REX.W = 0100_1000 = 0x48
    try expect(Rex.w64().toByte() == 0x48);

    // REX.WR = 0100_1100 = 0x4C
    try expect(Rex.wr().toByte() == 0x4C);

    // Plain REX (no flags) = 0100_0000 = 0x40
    const plain = Rex{};
    try expect(plain.toByte() == 0x40);

    // REX with B flag (extended rm) = 0100_0001 = 0x41
    const rex_b = Rex{ .b = 1 };
    try expect(rex_b.toByte() == 0x41);

    try expect(@sizeOf(Rex) == 1);
}

fn testMovRegImm() !void {
    // MOV rax, 0x0000000000000001
    // Expected: 48 B8 01 00 00 00 00 00 00 00
    const code = encodeMoveRegImm64(.rax, 1);
    try expect(code[0] == 0x48); // REX.W
    try expect(code[1] == 0xB8); // B8 + rax(0)
    try expect(code[2] == 0x01); // imm lo byte
    try expect(code[3] == 0x00);

    // MOV rcx, 0xDEADBEEF
    const code2 = encodeMoveRegImm64(.rcx, 0xDEADBEEF);
    try expect(code2[0] == 0x48);
    try expect(code2[1] == 0xB9); // B8 + rcx(1)
    try expect(code2[2] == 0xEF);
    try expect(code2[3] == 0xBE);
    try expect(code2[4] == 0xAD);
    try expect(code2[5] == 0xDE);
}

fn testMovRegReg() !void {
    // MOV rax, rcx → 48 89 C8
    // (89 = MOV r/m64,r64; ModRM = 11_001_000 = 0xC8)
    const code = encodeMoveRegReg(.rax, .rcx);
    try expect(code[0] == 0x48);
    try expect(code[1] == 0x89);
    try expect(code[2] == 0xC8);

    // MOV rbx, rdx → 48 89 D3
    // ModRM = 11_010_011 = 0xD3
    const code2 = encodeMoveRegReg(.rbx, .rdx);
    try expect(code2[2] == 0xD3);
}

fn testAddRegReg() !void {
    // ADD rax, rcx → 48 01 C8
    const code = encodeAddRegReg(.rax, .rcx);
    try expect(code[0] == 0x48);
    try expect(code[1] == 0x01);
    try expect(code[2] == 0xC8);

    // ADD rsi, rdi → 48 01 FE
    // ModRM = 11_111_110 = 0xFE
    const code2 = encodeAddRegReg(.rsi, .rdi);
    try expect(code2[2] == 0xFE);
}

fn testJmpRel32() !void {
    // JMP +0x10 → E9 10 00 00 00
    const code = encodeJmpRel32(0x10);
    try expect(code[0] == 0xE9);
    try expect(code[1] == 0x10);
    try expect(code[2] == 0x00);

    // JMP -5 (jump backward) → E9 FB FF FF FF
    const back = encodeJmpRel32(-5);
    try expect(back[0] == 0xE9);
    try expect(back[1] == 0xFB); // -5 as u32 LE = FB FF FF FF
    try expect(back[2] == 0xFF);
    try expect(back[3] == 0xFF);
    try expect(back[4] == 0xFF);
}

fn testRetEncoding() !void {
    const code = encodeRet();
    try expect(code[0] == 0xC3);
}

fn testNopEncoding() !void {
    const code = encodeNop();
    try expect(code[0] == 0x90);
}
