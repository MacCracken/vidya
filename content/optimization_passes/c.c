// Vidya — Optimization Passes in C
//
// Demonstrates classic compiler optimization passes on a simple IR:
//   1. Constant folding — evaluate constant expressions at compile time
//   2. Dead code elimination (DCE) — remove unused instructions
//   3. Constant propagation — replace variables with known values
//   4. Strength reduction — replace expensive ops with cheaper ones
//   5. Fixed-point iteration — run passes until no more changes
//
// Each pass transforms the IR independently. The pass manager runs them
// in a loop until a fixed point: no pass makes any changes.

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ── Simple IR ───────────────────────────────────────────────────────

typedef enum { OP_ADD, OP_SUB, OP_MUL } OpKind;

static const char *op_str(OpKind op) {
    switch (op) {
        case OP_ADD: return "+";
        case OP_SUB: return "-";
        case OP_MUL: return "*";
    }
    return "?";
}

typedef enum {
    INST_CONST,   // dst = value
    INST_BINOP,   // dst = lhs op rhs
    INST_COPY,    // dst = src
    INST_RETURN,  // return src
    INST_NOP,     // removed (placeholder for DCE)
} InstKind;

typedef struct {
    InstKind kind;
    int dst;
    int64_t value;    // INST_CONST
    OpKind op;        // INST_BINOP
    int lhs, rhs;     // INST_BINOP
    int src;           // INST_COPY, INST_RETURN
} Inst;

static void inst_print(const Inst *inst) {
    switch (inst->kind) {
        case INST_CONST:
            printf("    v%d = %ld\n", inst->dst, inst->value);
            break;
        case INST_BINOP:
            printf("    v%d = v%d %s v%d\n", inst->dst, inst->lhs,
                   op_str(inst->op), inst->rhs);
            break;
        case INST_COPY:
            printf("    v%d = v%d\n", inst->dst, inst->src);
            break;
        case INST_RETURN:
            printf("    return v%d\n", inst->src);
            break;
        case INST_NOP:
            break;
    }
}

#define MAX_INSTS 32

typedef struct {
    Inst instructions[MAX_INSTS];
    int count;
} Program;

static void prog_print(const Program *p) {
    for (int i = 0; i < p->count; i++) {
        inst_print(&p->instructions[i]);
    }
}

static void prog_compact(Program *p) {
    // Remove NOP instructions (from DCE)
    int write = 0;
    for (int read = 0; read < p->count; read++) {
        if (p->instructions[read].kind != INST_NOP) {
            p->instructions[write++] = p->instructions[read];
        }
    }
    p->count = write;
}

// ── Pass 1: Constant Folding ────────────────────────────────────────

static int constant_fold(Program *p) {
    int64_t constants[128];
    int is_const[128];
    int folded = 0;

    memset(is_const, 0, sizeof(is_const));

    for (int i = 0; i < p->count; i++) {
        Inst *inst = &p->instructions[i];
        switch (inst->kind) {
            case INST_CONST:
                constants[inst->dst] = inst->value;
                is_const[inst->dst] = 1;
                break;
            case INST_BINOP:
                if (is_const[inst->lhs] && is_const[inst->rhs]) {
                    int64_t l = constants[inst->lhs];
                    int64_t r = constants[inst->rhs];
                    int64_t val;
                    switch (inst->op) {
                        case OP_ADD: val = l + r; break;
                        case OP_SUB: val = l - r; break;
                        case OP_MUL: val = l * r; break;
                        default: continue;
                    }
                    constants[inst->dst] = val;
                    is_const[inst->dst] = 1;
                    inst->kind = INST_CONST;
                    inst->value = val;
                    folded++;
                }
                break;
            case INST_COPY:
                if (is_const[inst->src]) {
                    constants[inst->dst] = constants[inst->src];
                    is_const[inst->dst] = 1;
                }
                break;
            default:
                break;
        }
    }
    return folded;
}

// ── Pass 2: Dead Code Elimination ───────────────────────────────────

static int dead_code_elimination(Program *p) {
    // Collect all used registers
    int used[128];
    memset(used, 0, sizeof(used));

    for (int i = 0; i < p->count; i++) {
        Inst *inst = &p->instructions[i];
        switch (inst->kind) {
            case INST_BINOP:
                used[inst->lhs] = 1;
                used[inst->rhs] = 1;
                break;
            case INST_COPY:
                used[inst->src] = 1;
                break;
            case INST_RETURN:
                used[inst->src] = 1;
                break;
            default:
                break;
        }
    }

    // Remove instructions whose dst is never used
    int eliminated = 0;
    for (int i = 0; i < p->count; i++) {
        Inst *inst = &p->instructions[i];
        switch (inst->kind) {
            case INST_CONST: case INST_BINOP: case INST_COPY:
                if (!used[inst->dst]) {
                    inst->kind = INST_NOP;
                    eliminated++;
                }
                break;
            default:
                break;
        }
    }

    if (eliminated > 0) {
        prog_compact(p);
    }
    return eliminated;
}

// ── Pass 3: Constant Propagation ────────────────────────────────────

static int constant_propagation(Program *p) {
    int64_t constants[128];
    int is_const[128];
    int propagated = 0;

    memset(is_const, 0, sizeof(is_const));

    for (int i = 0; i < p->count; i++) {
        if (p->instructions[i].kind == INST_CONST) {
            constants[p->instructions[i].dst] = p->instructions[i].value;
            is_const[p->instructions[i].dst] = 1;
        }
    }

    for (int i = 0; i < p->count; i++) {
        Inst *inst = &p->instructions[i];
        if (inst->kind == INST_COPY && is_const[inst->src]) {
            inst->kind = INST_CONST;
            inst->value = constants[inst->src];
            propagated++;
        } else if (inst->kind == INST_BINOP) {
            if (is_const[inst->lhs] || is_const[inst->rhs]) {
                propagated++;
            }
        }
    }
    return propagated;
}

// ── Pass 4: Strength Reduction ──────────────────────────────────────

static int is_power_of_two(int64_t n) {
    return n > 0 && (n & (n - 1)) == 0;
}

static int strength_reduction(Program *p) {
    int64_t constants[128];
    int is_const[128];
    int reduced = 0;

    memset(is_const, 0, sizeof(is_const));

    for (int i = 0; i < p->count; i++) {
        if (p->instructions[i].kind == INST_CONST) {
            constants[p->instructions[i].dst] = p->instructions[i].value;
            is_const[p->instructions[i].dst] = 1;
        }
    }

    for (int i = 0; i < p->count; i++) {
        Inst *inst = &p->instructions[i];
        if (inst->kind != INST_BINOP) continue;

        int64_t *lhs_val = is_const[inst->lhs] ? &constants[inst->lhs] : NULL;
        int64_t *rhs_val = is_const[inst->rhs] ? &constants[inst->rhs] : NULL;

        if (inst->op == OP_MUL) {
            // Both constant + power of 2: fold directly
            if (lhs_val && rhs_val && is_power_of_two(*rhs_val)) {
                int shift = 0;
                int64_t v = *rhs_val;
                while (v > 1) { v >>= 1; shift++; }
                int64_t result = *lhs_val << shift;
                constants[inst->dst] = result;
                is_const[inst->dst] = 1;
                inst->kind = INST_CONST;
                inst->value = result;
                reduced++;
                continue;
            }
            // Multiply by 0
            if ((rhs_val && *rhs_val == 0) || (lhs_val && *lhs_val == 0)) {
                inst->kind = INST_CONST;
                inst->value = 0;
                reduced++;
                continue;
            }
            // Multiply by 1
            if (rhs_val && *rhs_val == 1) {
                inst->kind = INST_COPY;
                inst->src = inst->lhs;
                reduced++;
                continue;
            }
            if (lhs_val && *lhs_val == 1) {
                inst->kind = INST_COPY;
                inst->src = inst->rhs;
                reduced++;
                continue;
            }
        }

        if (inst->op == OP_ADD) {
            // Add 0
            if (rhs_val && *rhs_val == 0) {
                inst->kind = INST_COPY;
                inst->src = inst->lhs;
                reduced++;
            } else if (lhs_val && *lhs_val == 0) {
                inst->kind = INST_COPY;
                inst->src = inst->rhs;
                reduced++;
            }
        }
    }
    return reduced;
}

// ── Pass Manager ────────────────────────────────────────────────────

static int optimize(Program *p) {
    printf("  Running optimization passes to fixed point:\n");
    int iteration = 0;

    while (1) {
        iteration++;
        int changed = 0;

        int f = constant_fold(p);
        if (f > 0) {
            printf("    iter %d: constant folding: %d ops\n", iteration, f);
            changed = 1;
        }

        int pr = constant_propagation(p);
        if (pr > 0) {
            printf("    iter %d: constant propagation: %d propagated\n", iteration, pr);
            changed = 1;
        }

        int r = strength_reduction(p);
        if (r > 0) {
            printf("    iter %d: strength reduction: %d reduced\n", iteration, r);
            changed = 1;
        }

        int d = dead_code_elimination(p);
        if (d > 0) {
            printf("    iter %d: DCE: %d removed\n", iteration, d);
            changed = 1;
        }

        if (!changed) {
            printf("    Fixed point after %d iterations\n", iteration);
            break;
        }
    }
    return iteration;
}

// ── Main ────────────────────────────────────────────────────────────

int main(void) {
    printf("Optimization Passes — compiler transformations:\n\n");

    // ── Test 1: Full pipeline ─────────────────────────────────────
    printf("1. Input: (10 + 20) * (x + 0) * 1 where x = 5\n");
    Program p1 = {
        .instructions = {
            {.kind = INST_CONST,  .dst = 0, .value = 10},
            {.kind = INST_CONST,  .dst = 1, .value = 20},
            {.kind = INST_BINOP,  .dst = 2, .op = OP_ADD, .lhs = 0, .rhs = 1},
            {.kind = INST_CONST,  .dst = 3, .value = 5},
            {.kind = INST_CONST,  .dst = 4, .value = 0},
            {.kind = INST_BINOP,  .dst = 5, .op = OP_ADD, .lhs = 3, .rhs = 4},
            {.kind = INST_BINOP,  .dst = 6, .op = OP_MUL, .lhs = 2, .rhs = 5},
            {.kind = INST_CONST,  .dst = 7, .value = 1},
            {.kind = INST_BINOP,  .dst = 8, .op = OP_MUL, .lhs = 6, .rhs = 7},
            {.kind = INST_RETURN, .src = 8},
        },
        .count = 10,
    };

    printf("  Before (%d instructions):\n", p1.count);
    prog_print(&p1);

    optimize(&p1);

    printf("  After (%d instructions):\n", p1.count);
    prog_print(&p1);

    // Verify result is 150
    assert(p1.count <= 3);
    Inst *ret1 = &p1.instructions[p1.count - 1];
    assert(ret1->kind == INST_RETURN);
    for (int i = 0; i < p1.count; i++) {
        if (p1.instructions[i].kind == INST_CONST &&
            p1.instructions[i].dst == ret1->src) {
            assert(p1.instructions[i].value == 150);
        }
    }

    // ── Test 2: Strength reduction ────────────────────────────────
    printf("\n2. Strength reduction: x * 8 -> x << 3\n");
    Program p2 = {
        .instructions = {
            {.kind = INST_CONST,  .dst = 0, .value = 42},
            {.kind = INST_CONST,  .dst = 1, .value = 8},
            {.kind = INST_BINOP,  .dst = 2, .op = OP_MUL, .lhs = 0, .rhs = 1},
            {.kind = INST_RETURN, .src = 2},
        },
        .count = 4,
    };

    printf("  Before:\n");
    prog_print(&p2);

    optimize(&p2);

    printf("  After:\n");
    prog_print(&p2);

    // 42 * 8 = 336
    for (int i = 0; i < p2.count; i++) {
        if (p2.instructions[i].kind == INST_CONST &&
            p2.instructions[i].dst == 2) {
            assert(p2.instructions[i].value == 336);
        }
    }

    // ── Test 3: Dead code elimination ─────────────────────────────
    printf("\n3. Dead code elimination:\n");
    Program p3 = {
        .instructions = {
            {.kind = INST_CONST,  .dst = 0, .value = 1},
            {.kind = INST_CONST,  .dst = 1, .value = 2},
            {.kind = INST_CONST,  .dst = 2, .value = 3},     // dead
            {.kind = INST_BINOP,  .dst = 3, .op = OP_ADD, .lhs = 0, .rhs = 1},
            {.kind = INST_CONST,  .dst = 4, .value = 99},    // dead
            {.kind = INST_RETURN, .src = 3},
        },
        .count = 6,
    };

    printf("  Before (%d instructions):\n", p3.count);
    prog_print(&p3);

    optimize(&p3);

    printf("  After (%d instructions):\n", p3.count);
    prog_print(&p3);

    // Dead instructions removed: v2 and v4 should be gone
    // Note: after folding, v3 = v0 + v1 becomes v3 = 3 (a Const),
    // so a Const with value 3 may remain — check by register, not value
    for (int i = 0; i < p3.count; i++) {
        if (p3.instructions[i].kind == INST_CONST) {
            assert(p3.instructions[i].dst != 2);   // v2 dead
            assert(p3.instructions[i].dst != 4);   // v4 dead
        }
    }

    // ── Test 4: Constant folding standalone ───────────────────────
    printf("\n4. Constant folding: (3 + 7) * (2 - 1)\n");
    Program p4 = {
        .instructions = {
            {.kind = INST_CONST,  .dst = 0, .value = 3},
            {.kind = INST_CONST,  .dst = 1, .value = 7},
            {.kind = INST_BINOP,  .dst = 2, .op = OP_ADD, .lhs = 0, .rhs = 1},
            {.kind = INST_CONST,  .dst = 3, .value = 2},
            {.kind = INST_CONST,  .dst = 4, .value = 1},
            {.kind = INST_BINOP,  .dst = 5, .op = OP_SUB, .lhs = 3, .rhs = 4},
            {.kind = INST_BINOP,  .dst = 6, .op = OP_MUL, .lhs = 2, .rhs = 5},
            {.kind = INST_RETURN, .src = 6},
        },
        .count = 8,
    };

    int folded = constant_fold(&p4);
    assert(folded == 3);  // add, sub, mul
    printf("  Folded %d operations\n", folded);

    // ── Test 5: Identity operations ───────────────────────────────
    printf("\n5. Identity: x + 0 -> copy x\n");
    Program p5 = {
        .instructions = {
            {.kind = INST_CONST,  .dst = 0, .value = 42},
            {.kind = INST_CONST,  .dst = 1, .value = 0},
            {.kind = INST_BINOP,  .dst = 2, .op = OP_ADD, .lhs = 0, .rhs = 1},
            {.kind = INST_RETURN, .src = 2},
        },
        .count = 4,
    };

    int r = strength_reduction(&p5);
    assert(r == 1);
    assert(p5.instructions[2].kind == INST_COPY);
    assert(p5.instructions[2].src == 0);
    printf("  x + 0 reduced to copy: verified\n");

    // ── Test 6: Power-of-two detection ────────────────────────────
    printf("\n6. Power-of-two detection:\n");
    assert(is_power_of_two(1) == 1);
    assert(is_power_of_two(2) == 1);
    assert(is_power_of_two(4) == 1);
    assert(is_power_of_two(8) == 1);
    assert(is_power_of_two(16) == 1);
    assert(is_power_of_two(3) == 0);
    assert(is_power_of_two(6) == 0);
    assert(is_power_of_two(0) == 0);
    printf("  1,2,4,8,16 are powers of 2: verified\n");
    printf("  3,6,0 are not powers of 2: verified\n");

    printf("\nAll optimization pass examples passed.\n");
    return 0;
}
