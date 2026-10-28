// Vidya — Code Generation in C
//
// Demonstrates a simple compiler backend: AST → x86_64 assembly text.
// Uses the stack machine pattern — the simplest correct codegen:
//   - Every expression result goes in rax
//   - Temporaries saved via push/pop
//   - No register allocation needed (optimize later)
//
// Covers: AST node structs, recursive codegen, stack frame layout,
// instruction selection for arithmetic, calling convention constants.
//
// This is how every compiler backend starts: get it correct first
// with stack codegen, then add register allocation as a separate pass.

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── AST Node Types ───────────────────────────────────────────────────

typedef enum {
    EXPR_LIT,
    EXPR_ADD,
    EXPR_SUB,
    EXPR_MUL,
    EXPR_DIV,
    EXPR_VAR,
    EXPR_ASSIGN,
} ExprKind;

typedef struct Expr Expr;
struct Expr {
    ExprKind kind;
    union {
        int64_t lit_val;                      // EXPR_LIT
        struct { Expr *left, *right; } bin;   // EXPR_ADD/SUB/MUL/DIV
        const char *var_name;                 // EXPR_VAR
        struct { const char *name; Expr *value; } assign;  // EXPR_ASSIGN
    };
};

// ── AST Constructors ─────────────────────────────────────────────────

Expr *make_lit(int64_t val) {
    Expr *e = malloc(sizeof(Expr));
    assert(e != NULL);
    e->kind = EXPR_LIT;
    e->lit_val = val;
    return e;
}

Expr *make_binop(ExprKind kind, Expr *left, Expr *right) {
    Expr *e = malloc(sizeof(Expr));
    assert(e != NULL);
    e->kind = kind;
    e->bin.left = left;
    e->bin.right = right;
    return e;
}

Expr *make_var(const char *name) {
    Expr *e = malloc(sizeof(Expr));
    assert(e != NULL);
    e->kind = EXPR_VAR;
    e->var_name = name;
    return e;
}

Expr *make_assign(const char *name, Expr *value) {
    Expr *e = malloc(sizeof(Expr));
    assert(e != NULL);
    e->kind = EXPR_ASSIGN;
    e->assign.name = name;
    e->assign.value = value;
    return e;
}

void free_expr(Expr *e) {
    if (!e) return;
    switch (e->kind) {
        case EXPR_ADD: case EXPR_SUB: case EXPR_MUL: case EXPR_DIV:
            free_expr(e->bin.left);
            free_expr(e->bin.right);
            break;
        case EXPR_ASSIGN:
            free_expr(e->assign.value);
            break;
        default:
            break;
    }
    free(e);
}

// ── Code Buffer ──────────────────────────────────────────────────────
// Emits assembly text into a growable buffer.

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} CodeBuf;

void codebuf_init(CodeBuf *buf) {
    buf->cap = 4096;
    buf->data = malloc(buf->cap);
    assert(buf->data != NULL);
    buf->data[0] = '\0';
    buf->len = 0;
}

void codebuf_emit(CodeBuf *buf, const char *line) {
    size_t line_len = strlen(line);
    // +5 for "    " indent and newline
    while (buf->len + line_len + 6 > buf->cap) {
        buf->cap *= 2;
        // Trap: `buf->data = realloc(buf->data, ...)` leaks the old block if
        // realloc fails — NULL clobbers the only pointer to it (CWE-401,
        // which `gcc -fanalyzer` will trace). Grow via a temporary instead.
        char *grown = realloc(buf->data, buf->cap);
        assert(grown != NULL);
        buf->data = grown;
    }
    buf->len += (size_t)sprintf(buf->data + buf->len, "    %s\n", line);
}

void codebuf_emit_raw(CodeBuf *buf, const char *text) {
    size_t text_len = strlen(text);
    while (buf->len + text_len + 2 > buf->cap) {
        buf->cap *= 2;
        char *grown = realloc(buf->data, buf->cap);
        assert(grown != NULL);
        buf->data = grown;
    }
    buf->len += (size_t)sprintf(buf->data + buf->len, "%s\n", text);
}

void codebuf_free(CodeBuf *buf) {
    free(buf->data);
}

// ── Local Variable Table ─────────────────────────────────────────────

#define MAX_LOCALS 64

typedef struct {
    const char *name;
    int offset;  // negative offset from rbp
} Local;

typedef struct {
    Local locals[MAX_LOCALS];
    int count;
    int next_offset;  // next available rbp offset (negative)
} LocalTable;

void locals_init(LocalTable *t) {
    t->count = 0;
    t->next_offset = -8;  // first local at [rbp-8]
}

int locals_lookup(LocalTable *t, const char *name) {
    for (int i = 0; i < t->count; i++) {
        if (strcmp(t->locals[i].name, name) == 0) {
            return t->locals[i].offset;
        }
    }
    return 0;  // not found
}

int locals_alloc(LocalTable *t, const char *name) {
    // Check if already allocated
    int existing = locals_lookup(t, name);
    if (existing != 0) return existing;

    assert(t->count < MAX_LOCALS);
    t->locals[t->count].name = name;
    t->locals[t->count].offset = t->next_offset;
    t->count++;
    t->next_offset -= 8;
    return t->locals[t->count - 1].offset;
}

// ── Stack-Based Code Generator ───────────────────────────────────────
// Pattern: evaluate expression, result in rax.
// For binary ops: eval left → push rax → eval right → pop rcx → operate.

void gen_expr(CodeBuf *buf, LocalTable *locals, const Expr *expr) {
    char line[256];

    switch (expr->kind) {
        case EXPR_LIT:
            snprintf(line, sizeof(line), "mov rax, %ld", expr->lit_val);
            codebuf_emit(buf, line);
            break;

        case EXPR_VAR: {
            int offset = locals_lookup(locals, expr->var_name);
            snprintf(line, sizeof(line), "mov rax, [rbp%d]", offset);
            codebuf_emit(buf, line);
            break;
        }

        case EXPR_ADD:
            gen_expr(buf, locals, expr->bin.left);   // rax = left
            codebuf_emit(buf, "push rax");            // save left
            gen_expr(buf, locals, expr->bin.right);  // rax = right
            codebuf_emit(buf, "pop rcx");             // rcx = left
            codebuf_emit(buf, "add rax, rcx");        // rax = left + right
            break;

        case EXPR_SUB:
            gen_expr(buf, locals, expr->bin.left);
            codebuf_emit(buf, "push rax");
            gen_expr(buf, locals, expr->bin.right);
            codebuf_emit(buf, "pop rcx");             // rcx = left, rax = right
            codebuf_emit(buf, "sub rcx, rax");        // rcx = left - right
            codebuf_emit(buf, "mov rax, rcx");        // rax = result
            break;

        case EXPR_MUL:
            gen_expr(buf, locals, expr->bin.left);
            codebuf_emit(buf, "push rax");
            gen_expr(buf, locals, expr->bin.right);
            codebuf_emit(buf, "pop rcx");
            // Two-operand imul: doesn't clobber rdx
            codebuf_emit(buf, "imul rax, rcx");
            break;

        case EXPR_DIV:
            gen_expr(buf, locals, expr->bin.left);
            codebuf_emit(buf, "push rax");
            gen_expr(buf, locals, expr->bin.right);
            codebuf_emit(buf, "mov rcx, rax");        // divisor in rcx
            codebuf_emit(buf, "pop rax");              // dividend in rax
            // CRITICAL: use cqo (sign-extend), NOT xor rdx,rdx
            // idiv divides the 128-bit rdx:rax. With rdx zeroed, -10 becomes
            // the positive 2^64 - 10, so -10 / 3 gives 6148914691236517202
            // instead of -3.
            codebuf_emit(buf, "cqo");
            codebuf_emit(buf, "idiv rcx");
            break;

        case EXPR_ASSIGN: {
            int offset = locals_alloc(locals, expr->assign.name);
            gen_expr(buf, locals, expr->assign.value);
            snprintf(line, sizeof(line), "mov [rbp%d], rax", offset);
            codebuf_emit(buf, line);
            break;
        }
    }
}

// ── Function Generation ──────────────────────────────────────────────

void gen_function(CodeBuf *buf, const char *name, Expr **stmts, int stmt_count) {
    LocalTable locals;
    locals_init(&locals);

    // Function label
    char label[128];
    snprintf(label, sizeof(label), "%s:", name);
    codebuf_emit_raw(buf, label);

    // Prologue
    codebuf_emit(buf, "push rbp");
    codebuf_emit(buf, "mov rbp, rsp");

    // We need to know frame size, but don't know it yet.
    // In a real compiler: emit placeholder bytes, patch the imm32 after body.
    // Here we use a two-pass approach: generate body first, then emit frame size.

    // Save position — we'll insert "sub rsp, N" here after the body
    size_t frame_insert_pos = buf->len;
    // Reserve space: "    sub rsp, NNNN\n" = max ~25 chars
    const char *placeholder = "    sub rsp, 0          \n";
    size_t placeholder_len = strlen(placeholder);
    while (buf->len + placeholder_len + 1 > buf->cap) {
        buf->cap *= 2;
        char *grown = realloc(buf->data, buf->cap);
        assert(grown != NULL);
        buf->data = grown;
    }
    memcpy(buf->data + buf->len, placeholder, placeholder_len + 1);
    buf->len += placeholder_len;

    // Body
    for (int i = 0; i < stmt_count; i++) {
        gen_expr(buf, &locals, stmts[i]);
    }

    // Patch frame size (round up to 16-byte alignment)
    int frame_size = ((locals.count * 8 + 15) / 16) * 16;
    if (frame_size == 0) frame_size = 16;
    char patch[64];
    int patch_len = snprintf(patch, sizeof(patch), "    sub rsp, %d", frame_size);
    // Overwrite placeholder in-place, padding remainder with spaces
    memcpy(buf->data + frame_insert_pos, patch, (size_t)patch_len);
    for (size_t j = frame_insert_pos + (size_t)patch_len;
         j < frame_insert_pos + placeholder_len - 1; j++) {
        buf->data[j] = ' ';
    }

    // Epilogue — use 'leave' (1 byte) instead of mov rsp,rbp; pop rbp (4 bytes)
    codebuf_emit(buf, "leave");
    codebuf_emit(buf, "ret");
}

// ── Interpreter for Verification ─────────────────────────────────────

int64_t eval(const Expr *expr) {
    switch (expr->kind) {
        case EXPR_LIT: return expr->lit_val;
        case EXPR_ADD: return eval(expr->bin.left) + eval(expr->bin.right);
        case EXPR_SUB: return eval(expr->bin.left) - eval(expr->bin.right);
        case EXPR_MUL: return eval(expr->bin.left) * eval(expr->bin.right);
        case EXPR_DIV: return eval(expr->bin.left) / eval(expr->bin.right);
        default: return 0;
    }
}

// ── Executor for Verification ────────────────────────────────────────
// Runs the emitted text on a toy rax/rcx/rdx + stack machine, so each test
// checks that the generated code computes what eval() computes. Covers the
// instruction subset gen_expr emits for literal expressions.

static int64_t run_asm(const char *text) {
    int64_t rax = 0, rcx = 0, rdx = 0, stack[64];
    int sp = 0;
    while (*text) {
        while (*text == ' ') text++;
        const char *eol = strchr(text, '\n');
        size_t n = eol ? (size_t)(eol - text) : strlen(text);
        char ins[64];
        assert(n < sizeof(ins));
        memcpy(ins, text, n);
        ins[n] = '\0';
        text += n + (eol != NULL);

        long long imm;
        if (sscanf(ins, "mov rax, %lld", &imm) == 1) rax = imm;
        else if (strcmp(ins, "push rax") == 0) { assert(sp < 64); stack[sp++] = rax; }
        else if (strcmp(ins, "pop rcx") == 0)  { assert(sp > 0); rcx = stack[--sp]; }
        else if (strcmp(ins, "pop rax") == 0)  { assert(sp > 0); rax = stack[--sp]; }
        else if (strcmp(ins, "add rax, rcx") == 0)  rax += rcx;
        else if (strcmp(ins, "sub rcx, rax") == 0)  rcx -= rax;
        else if (strcmp(ins, "imul rax, rcx") == 0) rax *= rcx;
        else if (strcmp(ins, "mov rax, rcx") == 0)  rax = rcx;
        else if (strcmp(ins, "mov rcx, rax") == 0)  rcx = rax;
        else if (strcmp(ins, "cqo") == 0) rdx = rax < 0 ? -1 : 0;
        else if (strcmp(ins, "idiv rcx") == 0) {
            // idiv divides rdx:rax; it is only a 64-bit divide when rdx
            // holds rax's sign extension — exactly what cqo sets up.
            assert(rdx == (rax < 0 ? -1 : 0));
            rax /= rcx;
        } else {
            fprintf(stderr, "run_asm: unsupported '%s'\n", ins);
            exit(1);
        }
    }
    assert(sp == 0);  // every push was matched by a pop
    return rax;
}

// ── Stack Frame Layout ───────────────────────────────────────────────
// Verify the memory layout a compiler must produce.
//
// After prologue (push rbp; mov rbp, rsp):
//   [rbp+24]  = arg 8 (stack arg)
//   [rbp+16]  = arg 7 (stack arg)
//   [rbp+8]   = return address
//   [rbp]     = saved rbp
//   [rbp-8]   = param 0 / local 0
//   [rbp-16]  = param 1 / local 1
//   ...
//   [rsp]     = bottom of frame (16-byte aligned)

void test_frame_layout(void) {
    // Locals get consecutive slots: [rbp-8], [rbp-16], [rbp-24], ...
    static const char *names[] = {"a", "b", "c", "d", "e", "f"};
    LocalTable t;
    locals_init(&t);
    // locals_alloc mutates t, so it runs outside assert(): under -DNDEBUG
    // assert's expression is not evaluated and no slot would be allocated.
    for (int i = 0; i < 6; i++) {
        int off = locals_alloc(&t, names[i]);
        assert(off == -8 * (i + 1));
    }
    // Re-assigning an existing name reuses its slot
    int off_a = locals_alloc(&t, "a");
    assert(off_a == -8);
    assert(t.count == 6);

    // Stack arguments (7+): [rbp+16], [rbp+24], ...
    // +16 because: +8 for return address, +8 for saved rbp
}

// ── Calling Convention Verification ──────────────────────────────────

void test_calling_convention(void) {
    // System V AMD64: 6 integer arg registers
    const char *sysv_args[] = {"rdi", "rsi", "rdx", "rcx", "r8", "r9"};

    // Syscall ABI: same as System V except arg4 is r10 (not rcx)
    // because SYSCALL clobbers rcx (stores return address in rcx)
    const char *syscall_args[] = {"rdi", "rsi", "rdx", "r10", "r8", "r9"};
    for (int i = 0; i < 6; i++) {
        int same = strcmp(sysv_args[i], syscall_args[i]) == 0;
        assert(same == (i != 3));  // the two lists differ only at arg 4
    }

    // Caller-saved (must save before CALL) and callee-saved (function must
    // preserve) partition the 15 general registers other than rsp.
    const char *caller_saved[] = {"rax", "rcx", "rdx", "rsi", "rdi",
                                  "r8", "r9", "r10", "r11"};
    const char *callee_saved[] = {"rbx", "rbp", "r12", "r13", "r14", "r15"};
    size_t n_caller = sizeof(caller_saved) / sizeof(caller_saved[0]);
    size_t n_callee = sizeof(callee_saved) / sizeof(callee_saved[0]);
    assert(n_caller == 9 && n_callee == 6);
    for (size_t i = 0; i < n_caller; i++) {
        for (size_t j = 0; j < n_callee; j++) {
            assert(strcmp(caller_saved[i], callee_saved[j]) != 0);
        }
    }
}

int main(void) {
    // ── Test expression codegen ────────────────────────────────────
    typedef struct { const char *label; Expr *expr; } TestCase;

    TestCase tests[] = {
        {"42",        make_lit(42)},
        {"10 + 32",   make_binop(EXPR_ADD, make_lit(10), make_lit(32))},
        {"(2+3)*4",   make_binop(EXPR_MUL,
                        make_binop(EXPR_ADD, make_lit(2), make_lit(3)),
                        make_lit(4))},
        {"10-3-2",    make_binop(EXPR_SUB,
                        make_binop(EXPR_SUB, make_lit(10), make_lit(3)),
                        make_lit(2))},
        {"100/10",    make_binop(EXPR_DIV, make_lit(100), make_lit(10))},
        {"-10/3",     make_binop(EXPR_DIV, make_lit(-10), make_lit(3))},
    };
    int num_tests = sizeof(tests) / sizeof(tests[0]);

    printf("Code Generation — stack-based x86_64 emission:\n");
    printf("%-20s %8s %8s\n", "Expression", "Expected", "Emitted");
    printf("--------------------------------------------\n");

    for (int i = 0; i < num_tests; i++) {
        int64_t expected = eval(tests[i].expr);
        CodeBuf buf;
        codebuf_init(&buf);
        LocalTable locals;
        locals_init(&locals);
        gen_expr(&buf, &locals, tests[i].expr);

        int64_t got = run_asm(buf.data);
        printf("%-20s %8ld %8ld\n", tests[i].label, expected, got);
        assert(got == expected);  // generated code computes the same value
        codebuf_free(&buf);
    }

    // ── Verify instruction patterns ────────────────────────────────
    {
        CodeBuf buf;
        codebuf_init(&buf);
        LocalTable locals;
        locals_init(&locals);
        Expr *add_expr = make_binop(EXPR_ADD, make_lit(10), make_lit(32));
        gen_expr(&buf, &locals, add_expr);
        assert(strstr(buf.data, "push rax") != NULL);
        assert(strstr(buf.data, "pop rcx") != NULL);
        assert(strstr(buf.data, "add rax, rcx") != NULL);
        codebuf_free(&buf);
        free_expr(add_expr);
    }

    // Verify division uses cqo
    {
        CodeBuf buf;
        codebuf_init(&buf);
        LocalTable locals;
        locals_init(&locals);
        Expr *div_expr = make_binop(EXPR_DIV, make_lit(100), make_lit(10));
        gen_expr(&buf, &locals, div_expr);
        assert(strstr(buf.data, "cqo") != NULL);
        assert(strstr(buf.data, "idiv") != NULL);
        codebuf_free(&buf);
        free_expr(div_expr);
    }

    // ── Test function generation ───────────────────────────────────
    {
        CodeBuf buf;
        codebuf_init(&buf);
        Expr *stmts[3];
        stmts[0] = make_assign("x", make_lit(10));
        stmts[1] = make_assign("y", make_lit(20));
        stmts[2] = make_assign("z",
                       make_binop(EXPR_ADD, make_var("x"), make_var("y")));
        gen_function(&buf, "compute", stmts, 3);
        assert(strstr(buf.data, "push rbp") != NULL);
        assert(strstr(buf.data, "leave") != NULL);
        assert(strstr(buf.data, "ret") != NULL);
        // 3 locals * 8 = 24 bytes, rounded up to 16-byte alignment = 32
        assert(strstr(buf.data, "sub rsp, 32") != NULL);
        assert(strstr(buf.data, "mov [rbp-24], rax") != NULL);  // z
        printf("\nGenerated function:\n%s", buf.data);
        codebuf_free(&buf);
        for (int i = 0; i < 3; i++) free_expr(stmts[i]);
    }

    // ── Test frame layout and calling convention ───────────────────
    test_frame_layout();
    test_calling_convention();

    // ── Clean up test expressions ──────────────────────────────────
    for (int i = 0; i < num_tests; i++) {
        free_expr(tests[i].expr);
    }

    printf("\nAll code generation examples passed.\n");
    return 0;
}
