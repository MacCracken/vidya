# Vidya — Intermediate Representations in Python
#
# Demonstrates core IR concepts used in optimizing compilers:
#   1. Three-address code (TAC) generation from an AST
#   2. Basic block construction and control flow graph (CFG)
#   3. SSA (Static Single Assignment) form with phi nodes
#   4. Dominator tree computation
#   5. Constant folding on SSA form
#
# This is what sits between the parser and codegen in every
# optimizing compiler. The IR makes analysis and optimization tractable.

from enum import Enum, auto


# ── Three-Address Code ───────────────────────────────────────────────
# Each instruction has at most one operator and three operands.
# Every intermediate result gets its own virtual register.

class Op(Enum):
    ADD = auto()
    SUB = auto()
    MUL = auto()

    def __str__(self):
        return {Op.ADD: "+", Op.SUB: "-", Op.MUL: "*"}[self]


class Inst:
    """Base for TAC instructions."""
    pass


class LoadConst(Inst):
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


class Neg(Inst):
    __slots__ = ("dst", "src")

    def __init__(self, dst, src):
        self.dst = dst
        self.src = src

    def __str__(self):
        return f"v{self.dst} = -v{self.src}"


class BranchPos(Inst):
    __slots__ = ("cond", "then_block", "else_block")

    def __init__(self, cond, then_block, else_block):
        self.cond = cond
        self.then_block = then_block
        self.else_block = else_block

    def __str__(self):
        return f"if v{self.cond} > 0 goto B{self.then_block} else B{self.else_block}"


class Jump(Inst):
    __slots__ = ("target",)

    def __init__(self, target):
        self.target = target

    def __str__(self):
        return f"goto B{self.target}"


class Return(Inst):
    __slots__ = ("value",)

    def __init__(self, value):
        self.value = value

    def __str__(self):
        return f"return v{self.value}"


class Phi(Inst):
    """SSA phi node: merges values from different predecessor blocks."""
    __slots__ = ("dst", "inputs")

    def __init__(self, dst, inputs):
        self.dst = dst
        self.inputs = inputs  # list of (block_id, reg)

    def __str__(self):
        args = ", ".join(f"B{b}:v{r}" for b, r in self.inputs)
        return f"v{self.dst} = phi({args})"


# ── Basic Block and CFG ──────────────────────────────────────────────

class BasicBlock:
    """A straight-line sequence of instructions with no internal branches.

    Properties:
    - Execution enters only at the top (first instruction)
    - Execution exits only at the bottom (last instruction = terminator)
    - Once entered, every instruction executes exactly once
    """
    __slots__ = ("id", "instructions", "predecessors", "successors")

    def __init__(self, block_id):
        self.id = block_id
        self.instructions = []
        self.predecessors = []
        self.successors = []


class CFG:
    """Control Flow Graph: basic blocks connected by edges."""

    def __init__(self, blocks):
        self.blocks = blocks

    def __str__(self):
        lines = []
        for b in self.blocks:
            lines.append(
                f"  B{b.id} (preds: {b.predecessors}, succs: {b.successors}):"
            )
            for inst in b.instructions:
                lines.append(f"    {inst}")
        return "\n".join(lines)


# ── AST and IR Builder ───────────────────────────────────────────────

class Expr:
    pass


class Lit(Expr):
    def __init__(self, n):
        self.n = n


class Add(Expr):
    def __init__(self, l, r):
        self.l = l
        self.r = r


class Sub(Expr):
    def __init__(self, l, r):
        self.l = l
        self.r = r


class Mul(Expr):
    def __init__(self, l, r):
        self.l = l
        self.r = r


class NegExpr(Expr):
    def __init__(self, e):
        self.e = e


class IfPos(Expr):
    """if cond > 0 then a else b"""
    def __init__(self, cond, then_expr, else_expr):
        self.cond = cond
        self.then_expr = then_expr
        self.else_expr = else_expr


class IrBuilder:
    """Builds a CFG with SSA-form instructions from an AST."""

    def __init__(self):
        self.blocks = [BasicBlock(0)]
        self.current_block = 0
        self.next_reg = 0

    def fresh_reg(self):
        r = self.next_reg
        self.next_reg += 1
        return r

    def new_block(self):
        block_id = len(self.blocks)
        self.blocks.append(BasicBlock(block_id))
        return block_id

    def emit(self, inst):
        self.blocks[self.current_block].instructions.append(inst)

    def add_edge(self, from_id, to_id):
        self.blocks[from_id].successors.append(to_id)
        self.blocks[to_id].predecessors.append(from_id)

    def gen_expr(self, expr):
        """Generate TAC for an expression. Returns register holding the result."""
        if isinstance(expr, Lit):
            dst = self.fresh_reg()
            self.emit(LoadConst(dst, expr.n))
            return dst

        elif isinstance(expr, Add):
            lhs = self.gen_expr(expr.l)
            rhs = self.gen_expr(expr.r)
            dst = self.fresh_reg()
            self.emit(BinOp(dst, Op.ADD, lhs, rhs))
            return dst

        elif isinstance(expr, Sub):
            lhs = self.gen_expr(expr.l)
            rhs = self.gen_expr(expr.r)
            dst = self.fresh_reg()
            self.emit(BinOp(dst, Op.SUB, lhs, rhs))
            return dst

        elif isinstance(expr, Mul):
            lhs = self.gen_expr(expr.l)
            rhs = self.gen_expr(expr.r)
            dst = self.fresh_reg()
            self.emit(BinOp(dst, Op.MUL, lhs, rhs))
            return dst

        elif isinstance(expr, NegExpr):
            src = self.gen_expr(expr.e)
            dst = self.fresh_reg()
            self.emit(Neg(dst, src))
            return dst

        elif isinstance(expr, IfPos):
            cond_reg = self.gen_expr(expr.cond)

            then_block = self.new_block()
            else_block = self.new_block()
            merge_block = self.new_block()

            cond_block = self.current_block
            self.emit(BranchPos(cond_reg, then_block, else_block))
            self.add_edge(cond_block, then_block)
            self.add_edge(cond_block, else_block)

            # Then branch
            self.current_block = then_block
            then_reg = self.gen_expr(expr.then_expr)
            then_exit = self.current_block
            self.emit(Jump(merge_block))
            self.add_edge(then_exit, merge_block)

            # Else branch
            self.current_block = else_block
            else_reg = self.gen_expr(expr.else_expr)
            else_exit = self.current_block
            self.emit(Jump(merge_block))
            self.add_edge(else_exit, merge_block)

            # Merge with phi
            self.current_block = merge_block
            result = self.fresh_reg()
            self.emit(Phi(result, [(then_exit, then_reg), (else_exit, else_reg)]))
            return result

        raise ValueError(f"unknown expression type: {type(expr)}")

    def build(self, expr):
        result = self.gen_expr(expr)
        self.emit(Return(result))
        return CFG(self.blocks)


# ── Dominator Tree ───────────────────────────────────────────────────
# Block A dominates block B if every path from entry to B goes through A.
# The immediate dominator (idom) is the closest strict dominator.
# Dominator tree: idom[B] is B's parent.
#
# Used for: SSA construction, loop detection, code motion.

def compute_dominators(cfg):
    """Simple iterative dominator computation (Cooper, Harvey, Kennedy)."""
    n = len(cfg.blocks)
    if n == 0:
        return {}

    # dom[b] = set of blocks that dominate b
    dom = {b.id: set(range(n)) for b in cfg.blocks}
    dom[0] = {0}  # entry dominates only itself

    changed = True
    while changed:
        changed = False
        for b in cfg.blocks:
            if b.id == 0:
                continue
            if not b.predecessors:
                continue
            # dom(b) = {b} union intersection(dom(p) for p in preds(b))
            new_dom = set(range(n))
            for p in b.predecessors:
                new_dom &= dom[p]
            new_dom.add(b.id)
            if new_dom != dom[b.id]:
                dom[b.id] = new_dom
                changed = True

    return dom


def compute_idom(dom, num_blocks):
    """Compute immediate dominators from dominator sets."""
    idom = {}
    for b in range(num_blocks):
        strict_doms = dom[b] - {b}
        if not strict_doms:
            idom[b] = None  # entry block
            continue
        # idom(b) = the dominator of b that is dominated by all other dominators of b
        for candidate in strict_doms:
            # candidate is idom if it's dominated by no other strict dominator
            if all(candidate in dom[other] or other == candidate
                   for other in strict_doms):
                idom[b] = candidate
                break
    return idom


# ── Constant Folding on SSA ──────────────────────────────────────────

def constant_fold(cfg):
    """Fold constant expressions in SSA form."""
    constants = {}  # reg -> value
    folded = 0

    for block in cfg.blocks:
        new_insts = []
        for inst in block.instructions:
            if isinstance(inst, LoadConst):
                constants[inst.dst] = inst.value
                new_insts.append(inst)
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
                        new_insts.append(inst)
                        continue
                    constants[inst.dst] = val
                    new_insts.append(LoadConst(inst.dst, val))
                    folded += 1
                else:
                    new_insts.append(inst)
            elif isinstance(inst, Neg):
                if inst.src in constants:
                    val = -constants[inst.src]
                    constants[inst.dst] = val
                    new_insts.append(LoadConst(inst.dst, val))
                    folded += 1
                else:
                    new_insts.append(inst)
            else:
                new_insts.append(inst)
        block.instructions = new_insts

    return folded


# ── Main ─────────────────────────────────────────────────────────────

def main():
    print("Intermediate Representations — TAC, CFG, SSA:\n")

    # ── Test 1: TAC generation ─────────────────────────────────────
    print("1. TAC for (2 + 3) * 4:")
    expr1 = Mul(Add(Lit(2), Lit(3)), Lit(4))
    cfg1 = IrBuilder().build(expr1)
    print(cfg1)

    # Verify SSA property: each register defined exactly once
    defs = set()
    for b in cfg1.blocks:
        for inst in b.instructions:
            if hasattr(inst, "dst"):
                assert inst.dst not in defs, f"v{inst.dst} defined twice (violates SSA)"
                defs.add(inst.dst)
    print(f"   SSA verified: {len(defs)} unique definitions\n")

    # ── Test 2: CFG with branching and phi nodes ───────────────────
    print("2. CFG with branching: if 1 > 0 then 100 else 200")
    expr2 = IfPos(Lit(1), Lit(100), Lit(200))
    cfg2 = IrBuilder().build(expr2)
    print(cfg2)

    # Verify CFG structure
    assert len(cfg2.blocks) == 4, "if/else creates 4 blocks"
    # Block 0: condition + branch
    assert len(cfg2.blocks[0].successors) == 2, "condition has 2 successors"
    # Merge block (3): has phi node
    merge = cfg2.blocks[3]
    assert len(merge.predecessors) == 2, "merge has 2 predecessors"
    phi_count = sum(1 for inst in merge.instructions if isinstance(inst, Phi))
    assert phi_count == 1, "merge block has exactly one phi node"
    print(f"   CFG: 4 blocks, merge block has {phi_count} phi node\n")

    # ── Test 3: Phi node semantics ─────────────────────────────────
    print("3. Phi node semantics:")
    # A phi node selects a value based on which predecessor was taken.
    # phi(B1:v3, B2:v5) means:
    #   - if control came from B1, use v3
    #   - if control came from B2, use v5
    #
    # This is how SSA handles variables that get different values
    # on different paths through the program.
    phi_inst = None
    for inst in merge.instructions:
        if isinstance(inst, Phi):
            phi_inst = inst
            break
    assert phi_inst is not None
    assert len(phi_inst.inputs) == 2, "phi has 2 inputs (one per predecessor)"
    print(f"   {phi_inst}")
    print("   Phi selects value based on which predecessor was taken\n")

    # ── Test 4: Dominator tree ─────────────────────────────────────
    print("4. Dominator tree for if/else CFG:")
    dom = compute_dominators(cfg2)

    # Entry dominates everything
    for b in cfg2.blocks:
        assert 0 in dom[b.id], f"entry must dominate B{b.id}"

    # Each block dominates itself
    for b in cfg2.blocks:
        assert b.id in dom[b.id], f"B{b.id} must dominate itself"

    idom = compute_idom(dom, len(cfg2.blocks))
    for b_id, parent in sorted(idom.items()):
        parent_str = f"B{parent}" if parent is not None else "none (entry)"
        print(f"   B{b_id}: idom = {parent_str}")

    # Entry has no immediate dominator
    assert idom[0] is None, "entry has no idom"
    # Then and else blocks are dominated by the condition block
    assert idom[1] == 0, "then block dominated by entry"
    assert idom[2] == 0, "else block dominated by entry"
    print()

    # ── Test 5: Constant folding ───────────────────────────────────
    print("5. Constant folding on (10 + 20) * (3 - 1):")
    expr5 = Mul(Add(Lit(10), Lit(20)), Sub(Lit(3), Lit(1)))
    cfg5 = IrBuilder().build(expr5)
    print("   Before:")
    print(cfg5)

    folded = constant_fold(cfg5)
    print(f"   After ({folded} operations folded):")
    print(cfg5)

    # All operations should be folded to constants
    assert folded == 3, f"expected 3 folds (add, sub, mul), got {folded}"

    # Final result should be 60
    ret_inst = cfg5.blocks[0].instructions[-1]
    assert isinstance(ret_inst, Return)
    result_reg = ret_inst.value
    # Find the LoadConst for the result
    for inst in cfg5.blocks[0].instructions:
        if isinstance(inst, LoadConst) and inst.dst == result_reg:
            assert inst.value == 60, f"expected 60, got {inst.value}"
            break
    print()

    # ── Test 6: Basic block properties ─────────────────────────────
    print("6. Basic block properties:")
    # A basic block is maximal: it cannot be extended without violating
    # the single-entry, single-exit property.
    #
    # Leaders (first instruction of a basic block):
    #   - First instruction of the function
    #   - Target of any branch
    #   - Instruction immediately after a branch
    #
    # SSA property within a basic block:
    #   - Each register assigned exactly once
    #   - All uses of a register are dominated by its definition
    #   - No need for phi nodes within a single block

    # Verify single-entry: each block has defined predecessors
    for b in cfg2.blocks:
        if b.id == 0:
            assert len(b.predecessors) == 0, "entry has no predecessors"
        else:
            assert len(b.predecessors) > 0, f"B{b.id} must have predecessors"

    # Verify terminators: last instruction controls flow
    for b in cfg2.blocks:
        if not b.instructions:
            continue
        last = b.instructions[-1]
        if b.successors:
            assert isinstance(last, (BranchPos, Jump)), \
                f"B{b.id} has successors but no branch/jump terminator"

    print("   Single entry: verified (predecessors correct)")
    print("   Terminators: verified (branches match successors)")
    print("   SSA: each register defined exactly once")

    print("\nAll intermediate representation examples passed.")


if __name__ == "__main__":
    main()
