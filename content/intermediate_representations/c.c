// Vidya — Intermediate Representations in C
//
// Demonstrates core IR concepts used in optimizing compilers:
//   1. Three-address code (TAC) generation from a simple AST
//   2. Basic block construction and CFG (control flow graph)
//   3. SSA form with phi nodes
//   4. Dominator computation
//   5. Constant folding on SSA form
//
// This is the representation that sits between parsing and codegen.
// Every optimizing compiler has one (LLVM IR, GCC GIMPLE/RTL, etc.).

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// ── Three-Address Code ──────────────────────────────────────────────

typedef enum {
    TAC_CONST,      // dst = immediate
    TAC_ADD,        // dst = lhs + rhs
    TAC_SUB,        // dst = lhs - rhs
    TAC_MUL,        // dst = lhs * rhs
    TAC_NEG,        // dst = -src
    TAC_BRANCH_POS, // if cond > 0 goto then_block else else_block
    TAC_JUMP,       // goto target
    TAC_RETURN,     // return value
    TAC_PHI,        // dst = phi(inputs)
} TacKind;

#define MAX_PHI_INPUTS 4

typedef struct {
    TacKind kind;
    int dst;        // destination register
    int64_t value;  // for TAC_CONST
    int lhs, rhs;   // for binary ops
    int src;         // for TAC_NEG
    int cond;        // for TAC_BRANCH_POS
    int then_block, else_block;  // for TAC_BRANCH_POS
    int target;      // for TAC_JUMP
    int ret_reg;     // for TAC_RETURN
    struct { int block; int reg; } phi_inputs[MAX_PHI_INPUTS];
    int phi_count;
} Tac;

static void tac_print(const Tac *t) {
    switch (t->kind) {
        case TAC_CONST:
            printf("    v%d = %ld\n", t->dst, t->value);
            break;
        case TAC_ADD:
            printf("    v%d = v%d + v%d\n", t->dst, t->lhs, t->rhs);
            break;
        case TAC_SUB:
            printf("    v%d = v%d - v%d\n", t->dst, t->lhs, t->rhs);
            break;
        case TAC_MUL:
            printf("    v%d = v%d * v%d\n", t->dst, t->lhs, t->rhs);
            break;
        case TAC_NEG:
            printf("    v%d = -v%d\n", t->dst, t->src);
            break;
        case TAC_BRANCH_POS:
            printf("    if v%d > 0 goto B%d else B%d\n",
                   t->cond, t->then_block, t->else_block);
            break;
        case TAC_JUMP:
            printf("    goto B%d\n", t->target);
            break;
        case TAC_RETURN:
            printf("    return v%d\n", t->ret_reg);
            break;
        case TAC_PHI:
            printf("    v%d = phi(", t->dst);
            for (int i = 0; i < t->phi_count; i++) {
                if (i > 0) printf(", ");
                printf("B%d:v%d", t->phi_inputs[i].block, t->phi_inputs[i].reg);
            }
            printf(")\n");
            break;
    }
}

// ── Basic Block and CFG ─────────────────────────────────────────────

#define MAX_INSTS_PER_BLOCK 32
#define MAX_BLOCKS 16
#define MAX_EDGES 8

typedef struct {
    int id;
    Tac instructions[MAX_INSTS_PER_BLOCK];
    int num_insts;
    int predecessors[MAX_EDGES];
    int num_preds;
    int successors[MAX_EDGES];
    int num_succs;
} BasicBlock;

typedef struct {
    BasicBlock blocks[MAX_BLOCKS];
    int num_blocks;
    int current_block;
    int next_reg;
} IrBuilder;

static void builder_init(IrBuilder *b) {
    memset(b, 0, sizeof(*b));
    b->num_blocks = 1;  // block 0 = entry
}

static int fresh_reg(IrBuilder *b) {
    return b->next_reg++;
}

static int new_block(IrBuilder *b) {
    int id = b->num_blocks++;
    assert(id < MAX_BLOCKS);
    b->blocks[id].id = id;
    return id;
}

static void emit(IrBuilder *b, Tac inst) {
    BasicBlock *blk = &b->blocks[b->current_block];
    assert(blk->num_insts < MAX_INSTS_PER_BLOCK);
    blk->instructions[blk->num_insts++] = inst;
}

static void add_edge(IrBuilder *b, int from, int to) {
    BasicBlock *f = &b->blocks[from];
    BasicBlock *t = &b->blocks[to];
    assert(f->num_succs < MAX_EDGES);
    assert(t->num_preds < MAX_EDGES);
    f->successors[f->num_succs++] = to;
    t->predecessors[t->num_preds++] = from;
}

// ── AST ─────────────────────────────────────────────────────────────

typedef enum {
    EXPR_LIT, EXPR_ADD, EXPR_SUB, EXPR_MUL, EXPR_NEG, EXPR_IFPOS,
} ExprKind;

typedef struct Expr Expr;
struct Expr {
    ExprKind kind;
    int64_t value;
    Expr *left, *right;
    Expr *cond, *then_expr, *else_expr;
};

// Static expression pool (avoid malloc for simplicity)
#define EXPR_POOL_SIZE 64
static Expr expr_pool[EXPR_POOL_SIZE];
static int expr_pool_idx = 0;

static Expr *alloc_expr(void) {
    assert(expr_pool_idx < EXPR_POOL_SIZE);
    Expr *e = &expr_pool[expr_pool_idx++];
    memset(e, 0, sizeof(*e));
    return e;
}

static Expr *lit(int64_t n) {
    Expr *e = alloc_expr();
    e->kind = EXPR_LIT;
    e->value = n;
    return e;
}

static Expr *binop(ExprKind k, Expr *l, Expr *r) {
    Expr *e = alloc_expr();
    e->kind = k;
    e->left = l;
    e->right = r;
    return e;
}

static Expr *negexpr(Expr *inner) __attribute__((unused));
static Expr *negexpr(Expr *inner) {
    Expr *e = alloc_expr();
    e->kind = EXPR_NEG;
    e->left = inner;
    return e;
}

static Expr *ifpos(Expr *cond, Expr *then_e, Expr *else_e) {
    Expr *e = alloc_expr();
    e->kind = EXPR_IFPOS;
    e->cond = cond;
    e->then_expr = then_e;
    e->else_expr = else_e;
    return e;
}

// ── TAC Generation ──────────────────────────────────────────────────

static int gen_expr(IrBuilder *b, const Expr *e) {
    switch (e->kind) {
        case EXPR_LIT: {
            int dst = fresh_reg(b);
            Tac t = {.kind = TAC_CONST, .dst = dst, .value = e->value};
            emit(b, t);
            return dst;
        }
        case EXPR_ADD: case EXPR_SUB: case EXPR_MUL: {
            int lhs = gen_expr(b, e->left);
            int rhs = gen_expr(b, e->right);
            int dst = fresh_reg(b);
            TacKind k = e->kind == EXPR_ADD ? TAC_ADD :
                        e->kind == EXPR_SUB ? TAC_SUB : TAC_MUL;
            Tac t = {.kind = k, .dst = dst, .lhs = lhs, .rhs = rhs};
            emit(b, t);
            return dst;
        }
        case EXPR_NEG: {
            int src = gen_expr(b, e->left);
            int dst = fresh_reg(b);
            Tac t = {.kind = TAC_NEG, .dst = dst, .src = src};
            emit(b, t);
            return dst;
        }
        case EXPR_IFPOS: {
            int cond_reg = gen_expr(b, e->cond);
            int then_blk = new_block(b);
            int else_blk = new_block(b);
            int merge_blk = new_block(b);
            int cond_blk = b->current_block;

            Tac br = {.kind = TAC_BRANCH_POS, .cond = cond_reg,
                      .then_block = then_blk, .else_block = else_blk};
            emit(b, br);
            add_edge(b, cond_blk, then_blk);
            add_edge(b, cond_blk, else_blk);

            // Then
            b->current_block = then_blk;
            int then_reg = gen_expr(b, e->then_expr);
            int then_exit = b->current_block;
            Tac jmp1 = {.kind = TAC_JUMP, .target = merge_blk};
            emit(b, jmp1);
            add_edge(b, then_exit, merge_blk);

            // Else
            b->current_block = else_blk;
            int else_reg = gen_expr(b, e->else_expr);
            int else_exit = b->current_block;
            Tac jmp2 = {.kind = TAC_JUMP, .target = merge_blk};
            emit(b, jmp2);
            add_edge(b, else_exit, merge_blk);

            // Merge with phi
            b->current_block = merge_blk;
            int result = fresh_reg(b);
            Tac phi = {.kind = TAC_PHI, .dst = result, .phi_count = 2};
            phi.phi_inputs[0].block = then_exit;
            phi.phi_inputs[0].reg = then_reg;
            phi.phi_inputs[1].block = else_exit;
            phi.phi_inputs[1].reg = else_reg;
            emit(b, phi);
            return result;
        }
    }
    return -1;
}

static void build_cfg(IrBuilder *b, const Expr *e) {
    int result = gen_expr(b, e);
    Tac ret = {.kind = TAC_RETURN, .ret_reg = result};
    emit(b, ret);
}

static void print_cfg(const IrBuilder *b) {
    for (int i = 0; i < b->num_blocks; i++) {
        const BasicBlock *blk = &b->blocks[i];
        printf("  B%d (preds: [", blk->id);
        for (int j = 0; j < blk->num_preds; j++) {
            if (j > 0) printf(", ");
            printf("%d", blk->predecessors[j]);
        }
        printf("], succs: [");
        for (int j = 0; j < blk->num_succs; j++) {
            if (j > 0) printf(", ");
            printf("%d", blk->successors[j]);
        }
        printf("]):\n");
        for (int j = 0; j < blk->num_insts; j++) {
            tac_print(&blk->instructions[j]);
        }
    }
}

// ── Constant Folding ────────────────────────────────────────────────

static int constant_fold(IrBuilder *b) {
    int64_t constants[128];
    int is_const[128];
    int folded = 0;

    memset(is_const, 0, sizeof(is_const));

    for (int i = 0; i < b->num_blocks; i++) {
        BasicBlock *blk = &b->blocks[i];
        for (int j = 0; j < blk->num_insts; j++) {
            Tac *t = &blk->instructions[j];
            switch (t->kind) {
                case TAC_CONST:
                    constants[t->dst] = t->value;
                    is_const[t->dst] = 1;
                    break;
                case TAC_ADD: case TAC_SUB: case TAC_MUL:
                    if (is_const[t->lhs] && is_const[t->rhs]) {
                        int64_t l = constants[t->lhs];
                        int64_t r = constants[t->rhs];
                        int64_t val = t->kind == TAC_ADD ? l + r :
                                      t->kind == TAC_SUB ? l - r : l * r;
                        constants[t->dst] = val;
                        is_const[t->dst] = 1;
                        t->kind = TAC_CONST;
                        t->value = val;
                        folded++;
                    }
                    break;
                case TAC_NEG:
                    if (is_const[t->src]) {
                        int64_t val = -constants[t->src];
                        constants[t->dst] = val;
                        is_const[t->dst] = 1;
                        t->kind = TAC_CONST;
                        t->value = val;
                        folded++;
                    }
                    break;
                default:
                    break;
            }
        }
    }
    return folded;
}

// ── Dominator Computation ───────────────────────────────────────────
// Uses bit sets: dom[b] is a bitmask of blocks that dominate b.

static void compute_dominators(const IrBuilder *builder, uint16_t *dom) {
    int n = builder->num_blocks;
    uint16_t all = (uint16_t)((1 << n) - 1);

    // Entry dominated only by itself
    dom[0] = 1;
    // All others start with all blocks as potential dominators
    for (int i = 1; i < n; i++) {
        dom[i] = all;
    }

    int changed = 1;
    while (changed) {
        changed = 0;
        for (int i = 1; i < n; i++) {
            const BasicBlock *blk = &builder->blocks[i];
            if (blk->num_preds == 0) continue;

            uint16_t new_dom = all;
            for (int j = 0; j < blk->num_preds; j++) {
                new_dom &= dom[blk->predecessors[j]];
            }
            new_dom |= (uint16_t)(1 << i);  // block dominates itself

            if (new_dom != dom[i]) {
                dom[i] = new_dom;
                changed = 1;
            }
        }
    }
}

// ── Main ────────────────────────────────────────────────────────────

int main(void) {
    printf("Intermediate Representations — TAC, CFG, SSA:\n\n");

    // ── Test 1: TAC generation ────────────────────────────────────
    printf("1. TAC for (2 + 3) * 4:\n");
    IrBuilder b1;
    builder_init(&b1);
    build_cfg(&b1, binop(EXPR_MUL, binop(EXPR_ADD, lit(2), lit(3)), lit(4)));
    print_cfg(&b1);

    // Verify SSA: each register defined exactly once
    int defs[64] = {0};
    for (int i = 0; i < b1.num_blocks; i++) {
        for (int j = 0; j < b1.blocks[i].num_insts; j++) {
            Tac *t = &b1.blocks[i].instructions[j];
            if (t->kind != TAC_BRANCH_POS && t->kind != TAC_JUMP &&
                t->kind != TAC_RETURN) {
                assert(defs[t->dst] == 0);  // not yet defined
                defs[t->dst] = 1;
            }
        }
    }
    printf("  SSA property verified: each register defined once\n\n");

    // ── Test 2: CFG with phi nodes ────────────────────────────────
    printf("2. CFG with branching: if 1 > 0 then 100 else 200\n");
    expr_pool_idx = 0;  // reset pool
    IrBuilder b2;
    builder_init(&b2);
    build_cfg(&b2, ifpos(lit(1), lit(100), lit(200)));
    print_cfg(&b2);

    // Verify structure
    assert(b2.num_blocks == 4);  // cond, then, else, merge
    assert(b2.blocks[0].num_succs == 2);  // branch has 2 successors
    assert(b2.blocks[3].num_preds == 2);  // merge has 2 predecessors

    // Verify phi node in merge block
    int phi_count = 0;
    for (int j = 0; j < b2.blocks[3].num_insts; j++) {
        if (b2.blocks[3].instructions[j].kind == TAC_PHI) {
            phi_count++;
            assert(b2.blocks[3].instructions[j].phi_count == 2);
        }
    }
    assert(phi_count == 1);
    printf("  Merge block has %d phi node with 2 inputs\n\n", phi_count);

    // ── Test 3: Dominator tree ────────────────────────────────────
    printf("3. Dominator tree:\n");
    uint16_t dom[MAX_BLOCKS];
    compute_dominators(&b2, dom);

    // Entry dominates everything
    for (int i = 0; i < b2.num_blocks; i++) {
        assert(dom[i] & 1);  // bit 0 = entry
    }

    // Each block dominates itself
    for (int i = 0; i < b2.num_blocks; i++) {
        assert(dom[i] & (1 << i));
    }

    for (int i = 0; i < b2.num_blocks; i++) {
        printf("  B%d dominated by: {", i);
        int first = 1;
        for (int j = 0; j < b2.num_blocks; j++) {
            if (dom[i] & (1 << j)) {
                if (!first) printf(", ");
                printf("B%d", j);
                first = 0;
            }
        }
        printf("}\n");
    }
    printf("\n");

    // ── Test 4: Constant folding ──────────────────────────────────
    printf("4. Constant folding on (10 + 20) * (3 - 1):\n");
    expr_pool_idx = 0;
    IrBuilder b4;
    builder_init(&b4);
    build_cfg(&b4, binop(EXPR_MUL,
                         binop(EXPR_ADD, lit(10), lit(20)),
                         binop(EXPR_SUB, lit(3), lit(1))));

    printf("  Before:\n");
    print_cfg(&b4);

    int folded = constant_fold(&b4);
    printf("  After (%d operations folded):\n", folded);
    print_cfg(&b4);

    assert(folded == 3);  // add, sub, mul all folded

    // Verify final result is 60
    Tac *ret = &b4.blocks[0].instructions[b4.blocks[0].num_insts - 1];
    assert(ret->kind == TAC_RETURN);
    // Find the const that feeds the return
    for (int j = 0; j < b4.blocks[0].num_insts; j++) {
        Tac *t = &b4.blocks[0].instructions[j];
        if (t->kind == TAC_CONST && t->dst == ret->ret_reg) {
            assert(t->value == 60);
        }
    }

    // ── Test 5: Basic block properties ────────────────────────────
    printf("5. Basic block properties:\n");
    // A basic block guarantees:
    //   - Single entry point (only the first instruction is a branch target)
    //   - Sequential execution (no branches except at the end)
    //   - The terminator controls all exits
    //
    // In SSA form within a basic block:
    //   - Each virtual register is assigned exactly once
    //   - Uses are dominated by definitions (def before use, linearly)
    //   - Phi nodes only appear at block entry (not mid-block)

    // Verify terminators match successor edges
    for (int i = 0; i < b2.num_blocks; i++) {
        BasicBlock *blk = &b2.blocks[i];
        if (blk->num_insts == 0) continue;
        Tac *last = &blk->instructions[blk->num_insts - 1];
        if (blk->num_succs > 0) {
            assert(last->kind == TAC_BRANCH_POS || last->kind == TAC_JUMP);
        }
    }
    printf("  Terminators match successor edges: verified\n");
    printf("  SSA single-definition: verified\n");
    printf("  Entry dominates all blocks: verified\n");

    printf("\nAll intermediate representation examples passed.\n");
    return 0;
}
