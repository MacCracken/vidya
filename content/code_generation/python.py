# Vidya — Code Generation in Python
#
# Demonstrates a simple compiler backend that takes an expression AST
# and emits x86_64-style assembly text. Covers:
#   - AST representation (nested tuples)
#   - Instruction selection (arithmetic → x86_64 instructions)
#   - Stack-based expression evaluation (push/pop for temporaries)
#   - Register allocation (simple linear scan)
#   - Stack frame layout (prologue/epilogue, local variable slots)
#   - Calling convention constants (System V AMD64)
#
# This is the pattern every compiler backend follows:
#   AST → instruction selection → register assignment → text output

# ── AST Representation ────────────────────────────────────────────────
# Nodes are tuples: (kind, ...) for easy pattern matching.
# A real compiler would use classes, but tuples show the structure clearly.

def lit(n):
    return ("lit", n)

def add(left, right):
    return ("add", left, right)

def sub(left, right):
    return ("sub", left, right)

def mul(left, right):
    return ("mul", left, right)

def div(left, right):
    return ("div", left, right)

def var_ref(name):
    return ("var", name)

def assign(name, expr):
    return ("assign", name, expr)


# ── Stack-Based Code Generator ────────────────────────────────────────
# The simplest correct codegen: every intermediate goes on the stack.
# No register allocation needed — result always in rax, temporaries
# saved via push/pop.

class StackCodegen:
    """Emit x86_64 assembly strings using a stack machine pattern."""

    def __init__(self):
        self.lines = []
        self.locals = {}       # name -> rbp offset (negative)
        self.next_offset = -8  # first local at [rbp-8]

    def emit(self, instruction):
        self.lines.append("    " + instruction)

    def comment(self, text):
        self.lines.append("    ; " + text)

    def alloc_local(self, name):
        """Allocate a stack slot for a local variable."""
        if name not in self.locals:
            self.locals[name] = self.next_offset
            self.next_offset -= 8
        return self.locals[name]

    def gen_expr(self, node):
        """Generate code for an expression. Result ends up in rax."""
        kind = node[0]

        if kind == "lit":
            value = node[1]
            self.emit(f"mov rax, {value}")

        elif kind == "var":
            name = node[1]
            offset = self.locals[name]
            self.emit(f"mov rax, [rbp{offset}]")

        elif kind == "add":
            left, right = node[1], node[2]
            self.gen_expr(left)       # result in rax
            self.emit("push rax")     # save left on stack
            self.gen_expr(right)      # result in rax (right)
            self.emit("pop rcx")      # rcx = left
            self.emit("add rax, rcx") # rax = left + right

        elif kind == "sub":
            left, right = node[1], node[2]
            self.gen_expr(left)
            self.emit("push rax")
            self.gen_expr(right)
            self.emit("pop rcx")          # rcx = left, rax = right
            self.emit("sub rcx, rax")     # rcx = left - right
            self.emit("mov rax, rcx")     # rax = result

        elif kind == "mul":
            left, right = node[1], node[2]
            self.gen_expr(left)
            self.emit("push rax")
            self.gen_expr(right)
            self.emit("pop rcx")
            self.emit("imul rax, rcx")  # two-operand form, no rdx clobber

        elif kind == "div":
            left, right = node[1], node[2]
            self.gen_expr(left)
            self.emit("push rax")
            self.gen_expr(right)
            self.emit("mov rcx, rax")   # divisor in rcx
            self.emit("pop rax")        # dividend in rax
            self.comment("sign-extend rax into rdx:rax (NOT xor rdx,rdx!)")
            self.emit("cqo")            # correct for signed division
            self.emit("idiv rcx")       # rax = quotient, rdx = remainder

        elif kind == "assign":
            name, expr = node[1], node[2]
            offset = self.alloc_local(name)
            self.gen_expr(expr)
            self.emit(f"mov [rbp{offset}], rax")

    def gen_function(self, name, stmts):
        """Generate a complete function with prologue/epilogue."""
        self.lines.append(f"{name}:")
        # Prologue
        self.emit("push rbp")
        self.emit("mov rbp, rsp")
        # Placeholder for stack allocation — patched after body
        frame_idx = len(self.lines)
        self.lines.append("    sub rsp, PLACEHOLDER")

        # Body
        for stmt in stmts:
            self.gen_expr(stmt)

        # Patch frame size (round up to 16 for alignment)
        num_locals = len(self.locals)
        frame_size = ((num_locals * 8 + 15) // 16) * 16
        if frame_size == 0:
            frame_size = 16  # minimum frame
        self.lines[frame_idx] = f"    sub rsp, {frame_size}"

        # Epilogue
        self.emit("leave")  # = mov rsp, rbp; pop rbp (1 byte vs 4)
        self.emit("ret")

        return "\n".join(self.lines)


# ── Register Allocator (Linear Scan) ──────────────────────────────────
# After stack codegen works, register allocation replaces push/pop with
# register assignments. Linear scan: sort live intervals by start,
# assign registers greedily, spill when out of registers.

class LiveInterval:
    """A variable's live range: from first def to last use."""
    def __init__(self, name, start, end):
        self.name = name
        self.start = start
        self.end = end
        self.register = None
        self.spilled = False

    def __repr__(self):
        loc = self.register if self.register else "spilled"
        return f"{self.name}:[{self.start},{self.end}] -> {loc}"


def linear_scan_alloc(intervals, available_regs):
    """
    Linear scan register allocation.
    Returns the intervals with .register or .spilled set.

    Algorithm:
    1. Sort intervals by start point
    2. For each interval, expire old intervals (end < current start)
    3. If a register is free, assign it
    4. Otherwise, spill the interval with the furthest end point
    """
    intervals = sorted(intervals, key=lambda iv: iv.start)
    active = []  # currently live intervals, sorted by end point
    free_regs = list(available_regs)

    for current in intervals:
        # Expire intervals that ended before current starts
        expired = [iv for iv in active if iv.end < current.start]
        for iv in expired:
            active.remove(iv)
            free_regs.append(iv.register)

        if free_regs:
            current.register = free_regs.pop(0)
            active.append(current)
            active.sort(key=lambda iv: iv.end)
        else:
            # Spill the one with the furthest next use
            if active and active[-1].end > current.end:
                spill = active.pop()
                spill.spilled = True
                current.register = spill.register
                spill.register = None
                active.append(current)
                active.sort(key=lambda iv: iv.end)
            else:
                current.spilled = True

    return intervals


# ── Calling Convention Constants ──────────────────────────────────────
# System V AMD64 ABI — the standard on Linux/macOS/BSD

SYSV_ARG_REGS = ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
SYSV_CALLER_SAVED = ["rax", "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11"]
SYSV_CALLEE_SAVED = ["rbx", "rbp", "r12", "r13", "r14", "r15"]
SYSV_RETURN_REG = "rax"

# Syscall ABI (Linux) — different register mapping than function calls
SYSCALL_ARG_REGS = ["rdi", "rsi", "rdx", "r10", "r8", "r9"]
SYSCALL_NUM_REG = "rax"


# ── Stack Frame Layout ────────────────────────────────────────────────
# After prologue (push rbp; mov rbp, rsp):
#   [rbp+16] = arg 7 (if >6 args, passed on stack)
#   [rbp+8]  = return address (pushed by call)
#   [rbp]    = saved rbp (pushed by prologue)
#   [rbp-8]  = local 1
#   [rbp-16] = local 2
#   ...
#   [rsp]    = bottom of frame (16-byte aligned before any call)

def stack_frame_offsets(num_params, num_locals):
    """Calculate stack frame layout offsets."""
    layout = {}

    # Parameters passed in registers are stored to stack in function body
    for i in range(min(num_params, 6)):
        layout[f"param_{i}"] = -(i + 1) * 8  # [rbp-8], [rbp-16], ...

    # Extra params (7+) are on the stack above rbp
    for i in range(6, num_params):
        offset = 16 + (i - 6) * 8  # [rbp+16], [rbp+24], ...
        layout[f"param_{i}"] = offset

    # Locals come after register-stored params
    local_start = min(num_params, 6)
    for i in range(num_locals):
        layout[f"local_{i}"] = -(local_start + i + 1) * 8

    # Frame size (rounded to 16-byte alignment)
    total_slots = min(num_params, 6) + num_locals
    layout["frame_size"] = ((total_slots * 8 + 15) // 16) * 16

    return layout


# ── Interpreter for Verification ──────────────────────────────────────

def eval_expr(node):
    kind = node[0]
    if kind == "lit":
        return node[1]
    elif kind == "add":
        return eval_expr(node[1]) + eval_expr(node[2])
    elif kind == "sub":
        return eval_expr(node[1]) - eval_expr(node[2])
    elif kind == "mul":
        return eval_expr(node[1]) * eval_expr(node[2])
    elif kind == "div":
        return eval_expr(node[1]) // eval_expr(node[2])
    else:
        raise ValueError(f"unknown node: {kind}")


def main():
    # ── Test stack-based codegen ────────────────────────────────────
    tests = [
        ("42",           lit(42)),
        ("10 + 32",      add(lit(10), lit(32))),
        ("(2+3)*4",      mul(add(lit(2), lit(3)), lit(4))),
        ("10-3-2",       sub(sub(lit(10), lit(3)), lit(2))),
        ("100/10",       div(lit(100), lit(10))),
    ]

    print("Code Generation — stack-based x86_64 emission:")
    print(f"{'Expression':<20} {'Expected':>8}")
    print("-" * 35)

    for label, expr in tests:
        expected = eval_expr(expr)
        cg = StackCodegen()
        cg.gen_expr(expr)
        asm = "\n".join(cg.lines)
        print(f"{label:<20} {expected:>8}")
        # Verify the codegen produced instructions
        assert len(cg.lines) > 0, f"no output for {label}"

    # Verify specific instruction patterns
    cg = StackCodegen()
    cg.gen_expr(add(lit(10), lit(32)))
    output = "\n".join(cg.lines)
    assert "push rax" in output, "stack codegen must push temporaries"
    assert "pop rcx" in output, "stack codegen must pop into rcx"
    assert "add rax, rcx" in output, "must emit add instruction"

    # Verify division uses cqo (not xor rdx,rdx)
    cg = StackCodegen()
    cg.gen_expr(div(lit(100), lit(10)))
    output = "\n".join(cg.lines)
    assert "cqo" in output, "signed division must use cqo, not xor rdx,rdx"
    assert "idiv" in output, "must emit idiv for signed division"
    # Verify no actual xor instruction (comments don't count)
    for line in output.split("\n"):
        stripped = line.split(";")[0]  # remove comments
        assert "xor" not in stripped, "must NOT use xor rdx,rdx for signed division"

    # ── Test function generation with locals ────────────────────────
    cg = StackCodegen()
    stmts = [
        assign("x", lit(10)),
        assign("y", lit(20)),
        assign("z", add(var_ref("x"), var_ref("y"))),
    ]
    asm = cg.gen_function("compute", stmts)
    assert "push rbp" in asm, "function must have prologue"
    assert "leave" in asm, "function must use leave (1 byte vs 4)"
    assert "ret" in asm, "function must return"
    assert "sub rsp" in asm, "function must allocate stack frame"
    assert "[rbp-8]" in asm, "first local at rbp-8"
    assert "[rbp-16]" in asm, "second local at rbp-16"

    # Verify frame size is 16-byte aligned
    for line in asm.split("\n"):
        if "sub rsp" in line:
            size = int(line.strip().split(", ")[1])
            assert size % 16 == 0, f"frame size {size} not 16-byte aligned"
            break

    print(f"\nGenerated function 'compute' ({len(asm.split(chr(10)))} lines):")
    print(asm)

    # ── Test linear scan register allocation ────────────────────────
    print("\nLinear scan register allocation:")
    intervals = [
        LiveInterval("a", 0, 10),
        LiveInterval("b", 2, 8),
        LiveInterval("c", 4, 12),
        LiveInterval("d", 6, 14),
        LiveInterval("e", 9, 16),
    ]

    # Only 3 registers available — forces spilling
    result = linear_scan_alloc(intervals, ["r1", "r2", "r3"])

    assigned = 0
    spilled = 0
    for iv in result:
        if iv.spilled:
            spilled += 1
            print(f"  {iv.name}: [{iv.start},{iv.end}] -> SPILLED")
        else:
            assigned += 1
            print(f"  {iv.name}: [{iv.start},{iv.end}] -> {iv.register}")

    assert assigned > 0, "should assign some registers"
    assert assigned + spilled == 5, "all intervals accounted for"
    # With 3 regs and overlapping intervals, at least one must spill
    print(f"  {assigned} assigned, {spilled} spilled (3 physical regs)")

    # ── Test stack frame layout ─────────────────────────────────────
    print("\nStack frame layout:")

    # 3 params, 2 locals
    layout = stack_frame_offsets(3, 2)
    assert layout["param_0"] == -8, "param 0 at [rbp-8]"
    assert layout["param_1"] == -16, "param 1 at [rbp-16]"
    assert layout["param_2"] == -24, "param 2 at [rbp-24]"
    assert layout["local_0"] == -32, "local 0 after params"
    assert layout["local_1"] == -40, "local 1 after local 0"
    assert layout["frame_size"] % 16 == 0, "frame size 16-byte aligned"

    print(f"  3 params + 2 locals:")
    for name, offset in sorted(layout.items(), key=lambda x: x[0]):
        if name != "frame_size":
            print(f"    {name}: [rbp{'+' if offset > 0 else ''}{offset}]")
    print(f"    frame_size: {layout['frame_size']} bytes")

    # 8 params — some on stack
    layout8 = stack_frame_offsets(8, 0)
    assert layout8["param_6"] == 16, "param 7 at [rbp+16] (stack arg)"
    assert layout8["param_7"] == 24, "param 8 at [rbp+24] (stack arg)"
    print(f"  8 params: param_6=[rbp+{layout8['param_6']}], param_7=[rbp+{layout8['param_7']}]")

    # ── Verify calling convention constants ─────────────────────────
    assert len(SYSV_ARG_REGS) == 6, "System V has 6 integer arg registers"
    assert SYSV_ARG_REGS[0] == "rdi", "first arg in rdi"
    assert SYSV_RETURN_REG == "rax", "return value in rax"
    assert SYSCALL_ARG_REGS[3] == "r10", "syscall arg 4 in r10 (not rcx!)"
    assert SYSV_ARG_REGS[3] == "rcx", "function arg 4 in rcx"

    print("\nAll code generation examples passed.")


if __name__ == "__main__":
    main()
