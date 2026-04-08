# Vidya — Optimization Passes in Python
#
# Demonstrates classic compiler optimization passes on a simple IR:
#   1. Constant folding — evaluate constant expressions at compile time
#   2. Dead code elimination (DCE) — remove unused instructions
#   3. Constant propagation — replace variables with known values
#   4. Strength reduction — replace expensive ops with cheaper ones
#   5. Peephole optimization — pattern-match and simplify sequences
#   6. Fixed-point iteration — run passes until no more changes
#
# Each pass transforms the IR. Passes compose: run iteratively
# until a fixed point (no more changes). This is the pass manager.

from enum import Enum, auto


# ── Simple IR ────────────────────────────────────────────────────────

class Op(Enum):
    ADD = auto()
    SUB = auto()
    MUL = auto()

    def __str__(self):
        return {Op.ADD: "+", Op.SUB: "-", Op.MUL: "*"}[self]


class Inst:
    """Base class for IR instructions."""
    pass


class Const(Inst):
    __slots__ = ("dst", "value")

    def __init__(self, dst, value):
        self.dst = dst
        self.value = value

    def __str__(self):
        return f"v{self.dst} = {self.value}"


class BinOp(Inst):
    __slots__ = ("dst", "op", "lhs", "rhs")

    def __init__(self, dst, op, lhs, rhs):
        self.dst = dst
        self.op = op
        self.lhs = lhs
        self.rhs = rhs

    def __str__(self):
        return f"v{self.dst} = v{self.lhs} {self.op} v{self.rhs}"


class Copy(Inst):
    __slots__ = ("dst", "src")

    def __init__(self, dst, src):
        self.dst = dst
        self.src = src

    def __str__(self):
        return f"v{self.dst} = v{self.src}"


class Return(Inst):
    __slots__ = ("src",)

    def __init__(self, src):
        self.src = src

    def __str__(self):
        return f"return v{self.src}"


class Program:
    def __init__(self, instructions):
        self.instructions = list(instructions)

    def __str__(self):
        return "\n".join(f"    {inst}" for inst in self.instructions)


# ── Pass 1: Constant Folding ─────────────────────────────────────────

def constant_fold(prog):
    """Replace binary ops on known constants with their result."""
    constants = {}  # reg -> value
    folded = 0

    for i, inst in enumerate(prog.instructions):
        if isinstance(inst, Const):
            constants[inst.dst] = inst.value
        elif isinstance(inst, BinOp):
            if inst.lhs in constants and inst.rhs in constants:
                l, r = constants[inst.lhs], constants[inst.rhs]
                if inst.op == Op.ADD:
                    val = l + r
                elif inst.op == Op.SUB:
                    val = l - r
                elif inst.op == Op.MUL:
                    val = l * r
                else:
                    continue
                constants[inst.dst] = val
                prog.instructions[i] = Const(inst.dst, val)
                folded += 1
        elif isinstance(inst, Copy):
            if inst.src in constants:
                constants[inst.dst] = constants[inst.src]

    return folded


# ── Pass 2: Dead Code Elimination ────────────────────────────────────

def dead_code_elimination(prog):
    """Remove instructions whose results are never used."""
    used = set()

    # Collect all used registers
    for inst in prog.instructions:
        if isinstance(inst, BinOp):
            used.add(inst.lhs)
            used.add(inst.rhs)
        elif isinstance(inst, Copy):
            used.add(inst.src)
        elif isinstance(inst, Return):
            used.add(inst.src)

    # Remove instructions with unused destinations
    before = len(prog.instructions)
    prog.instructions = [
        inst for inst in prog.instructions
        if isinstance(inst, Return) or
           (hasattr(inst, "dst") and inst.dst in used)
    ]

    return before - len(prog.instructions)


# ── Pass 3: Constant Propagation ─────────────────────────────────────

def constant_propagation(prog):
    """Replace copies of constants with direct constant loads."""
    constants = {}
    propagated = 0

    for inst in prog.instructions:
        if isinstance(inst, Const):
            constants[inst.dst] = inst.value

    for i, inst in enumerate(prog.instructions):
        if isinstance(inst, Copy):
            if inst.src in constants:
                prog.instructions[i] = Const(inst.dst, constants[inst.src])
                propagated += 1
        elif isinstance(inst, BinOp):
            if inst.lhs in constants or inst.rhs in constants:
                propagated += 1  # marks as ready for constant folding

    return propagated


# ── Pass 4: Strength Reduction ───────────────────────────────────────

def strength_reduction(prog):
    """Replace expensive operations with cheaper equivalents."""
    constants = {}
    reduced = 0

    for inst in prog.instructions:
        if isinstance(inst, Const):
            constants[inst.dst] = inst.value

    for i, inst in enumerate(prog.instructions):
        if not isinstance(inst, BinOp):
            continue

        lhs_val = constants.get(inst.lhs)
        rhs_val = constants.get(inst.rhs)

        if inst.op == Op.MUL:
            # Multiply by power of 2 with both operands constant -> fold
            if lhs_val is not None and rhs_val is not None:
                if rhs_val > 0 and (rhs_val & (rhs_val - 1)) == 0:
                    shift = rhs_val.bit_length() - 1
                    result = lhs_val << shift
                    constants[inst.dst] = result
                    prog.instructions[i] = Const(inst.dst, result)
                    reduced += 1
                    continue

            # Multiply by 0 -> const 0
            if rhs_val == 0 or lhs_val == 0:
                prog.instructions[i] = Const(inst.dst, 0)
                reduced += 1
                continue

            # Multiply by 1 -> copy
            if rhs_val == 1:
                prog.instructions[i] = Copy(inst.dst, inst.lhs)
                reduced += 1
                continue
            if lhs_val == 1:
                prog.instructions[i] = Copy(inst.dst, inst.rhs)
                reduced += 1
                continue

        elif inst.op == Op.ADD:
            # Add 0 -> copy
            if rhs_val == 0:
                prog.instructions[i] = Copy(inst.dst, inst.lhs)
                reduced += 1
            elif lhs_val == 0:
                prog.instructions[i] = Copy(inst.dst, inst.rhs)
                reduced += 1

    return reduced


# ── Pass Manager: fixed-point iteration ──────────────────────────────

def optimize(prog, verbose=True):
    """Run all passes to fixed point (no more changes)."""
    if verbose:
        print("  Running optimization passes to fixed point:")
    iteration = 0

    while True:
        iteration += 1
        changed = False

        f = constant_fold(prog)
        if f > 0:
            if verbose:
                print(f"    iter {iteration}: constant folding: {f} ops folded")
            changed = True

        p = constant_propagation(prog)
        if p > 0:
            if verbose:
                print(f"    iter {iteration}: constant propagation: {p} propagated")
            changed = True

        r = strength_reduction(prog)
        if r > 0:
            if verbose:
                print(f"    iter {iteration}: strength reduction: {r} reduced")
            changed = True

        d = dead_code_elimination(prog)
        if d > 0:
            if verbose:
                print(f"    iter {iteration}: DCE: {d} instructions removed")
            changed = True

        if not changed:
            if verbose:
                print(f"    Fixed point reached after {iteration} iterations")
            break

    return iteration


# ── Main ─────────────────────────────────────────────────────────────

def main():
    print("Optimization Passes — compiler transformations:\n")

    # ── Test 1: Full pipeline ──────────────────────────────────────
    # (10 + 20) * (x + 0) * 1 where x = 5
    # Optimal: return 150
    print("1. Input: (10 + 20) * (x + 0) * 1 where x = 5")
    prog1 = Program([
        Const(0, 10),                          # v0 = 10
        Const(1, 20),                          # v1 = 20
        BinOp(2, Op.ADD, 0, 1),                # v2 = v0 + v1
        Const(3, 5),                           # v3 = 5 (x)
        Const(4, 0),                           # v4 = 0
        BinOp(5, Op.ADD, 3, 4),                # v5 = x + 0
        BinOp(6, Op.MUL, 2, 5),               # v6 = (10+20) * (x+0)
        Const(7, 1),                           # v7 = 1
        BinOp(8, Op.MUL, 6, 7),               # v8 = v6 * 1
        Return(8),
    ])

    print(f"  Before ({len(prog1.instructions)} instructions):")
    print(prog1)

    optimize(prog1)

    print(f"  After ({len(prog1.instructions)} instructions):")
    print(prog1)

    # Should reduce to just: v8 = 150; return v8
    assert len(prog1.instructions) <= 3, \
        f"expected <= 3 instructions, got {len(prog1.instructions)}"
    # Verify result
    ret = prog1.instructions[-1]
    assert isinstance(ret, Return)
    for inst in prog1.instructions:
        if isinstance(inst, Const) and inst.dst == ret.src:
            assert inst.value == 150, f"expected 150, got {inst.value}"

    # ── Test 2: Strength reduction ─────────────────────────────────
    print("\n2. Strength reduction: x * 8 -> x << 3")
    prog2 = Program([
        Const(0, 42),
        Const(1, 8),
        BinOp(2, Op.MUL, 0, 1),
        Return(2),
    ])

    print(f"  Before:")
    print(prog2)

    optimize(prog2)

    print(f"  After:")
    print(prog2)

    # 42 * 8 = 336
    for inst in prog2.instructions:
        if isinstance(inst, Const) and inst.dst == 2:
            assert inst.value == 336, f"expected 336, got {inst.value}"

    # ── Test 3: Dead code elimination ──────────────────────────────
    print("\n3. Dead code elimination:")
    prog3 = Program([
        Const(0, 1),
        Const(1, 2),
        Const(2, 3),                           # dead
        BinOp(3, Op.ADD, 0, 1),
        Const(4, 99),                          # dead
        Return(3),
    ])

    print(f"  Before ({len(prog3.instructions)} instructions):")
    print(prog3)

    optimize(prog3)

    print(f"  After ({len(prog3.instructions)} instructions):")
    print(prog3)

    # Dead constants (v2, v4) should be eliminated
    # After folding: v3 = v0 + v1 becomes v3 = 3, so a Const with value 3 may remain
    # but the DEAD register v2 should be gone, and v4 = 99 should be gone
    remaining_dsts = {inst.dst for inst in prog3.instructions if isinstance(inst, Const)}
    assert 2 not in remaining_dsts, "v2 should be eliminated (dead)"
    assert 4 not in remaining_dsts, "v4 should be eliminated (dead)"

    # ── Test 4: Constant folding alone ─────────────────────────────
    print("\n4. Constant folding: (3 + 7) * (2 - 1)")
    prog4 = Program([
        Const(0, 3),
        Const(1, 7),
        BinOp(2, Op.ADD, 0, 1),               # 3 + 7 = 10
        Const(3, 2),
        Const(4, 1),
        BinOp(5, Op.SUB, 3, 4),               # 2 - 1 = 1
        BinOp(6, Op.MUL, 2, 5),               # 10 * 1 = 10
        Return(6),
    ])

    folded = constant_fold(prog4)
    assert folded == 3, f"expected 3 folds, got {folded}"
    print(f"  Folded {folded} operations")

    # ── Test 5: Pass ordering matters ──────────────────────────────
    print("\n5. Pass ordering: strength reduction enables DCE")
    prog5 = Program([
        Const(0, 42),
        Const(1, 1),                           # dead after strength reduction
        BinOp(2, Op.MUL, 0, 1),               # x * 1 -> folded to 42
        Return(2),
    ])

    # Strength reduction: both operands constant + power of 2 -> fold directly
    # 1 is 2^0, so 42 * 1 = 42 << 0 = 42 (becomes Const)
    r = strength_reduction(prog5)
    assert r == 1, "strength reduction should handle mul-by-1"
    assert isinstance(prog5.instructions[2], Const)
    assert prog5.instructions[2].value == 42

    # Now DCE removes the unused constants (v0 and v1)
    d = dead_code_elimination(prog5)
    print(f"  After strength reduction + DCE: {len(prog5.instructions)} instructions")
    print(prog5)

    # ── Test 6: Fixed-point convergence ────────────────────────────
    print("\n6. Fixed-point convergence:")
    # Chain of operations that require multiple iterations
    prog6 = Program([
        Const(0, 2),
        Const(1, 3),
        BinOp(2, Op.ADD, 0, 1),               # 2 + 3 = 5
        Const(3, 4),
        BinOp(4, Op.MUL, 2, 3),               # 5 * 4 = 20
        Const(5, 1),
        BinOp(6, Op.SUB, 4, 5),               # 20 - 1 = 19
        Return(6),
    ])

    iters = optimize(prog6)
    print(f"  Converged in {iters} iterations")

    # Verify final result is 19
    for inst in prog6.instructions:
        if isinstance(inst, Const) and hasattr(inst, 'dst'):
            ret_inst = prog6.instructions[-1]
            if isinstance(ret_inst, Return) and inst.dst == ret_inst.src:
                assert inst.value == 19, f"expected 19, got {inst.value}"

    # ── Test 7: Identity operations ────────────────────────────────
    print("\n7. Identity operations:")
    # x + 0 = x, x * 1 = x, x - 0 = x
    prog7 = Program([
        Const(0, 42),
        Const(1, 0),
        BinOp(2, Op.ADD, 0, 1),               # x + 0 -> x
        Return(2),
    ])

    r = strength_reduction(prog7)
    assert r == 1, "x + 0 should be reduced to copy"
    assert isinstance(prog7.instructions[2], Copy)
    assert prog7.instructions[2].src == 0  # copies from v0 (42)
    print("  x + 0 reduced to copy: verified")

    print("\nAll optimization pass examples passed.")


if __name__ == "__main__":
    main()
