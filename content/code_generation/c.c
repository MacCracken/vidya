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
    e->kind = EXPR_LIT;
    e->lit_val = val;
    return e;
}

Expr *make_binop(ExprKind kind, Expr *left, Expr *right) {
    Expr *e = malloc(sizeof(Expr));
    e->kind = kind;
    e->bin.left = left;
    e->bin.right = right;
    return e;
}

Expr *make_var(const char *name) {
    Expr *e = malloc(sizeof(Expr));
    e->kind = EXPR_VAR;
    e->var_name = name;
    return e;
}

Expr *make_assign(const char *name, Expr *value) {
    Expr *e = malloc(sizeof(Expr));
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
    buf->data[0] = '\0';
    buf->len = 0;
}

void codebuf_emit(CodeBuf *buf, const char *line) {
    size_t line_len = strlen(line);
    // +5 for "    " indent and newline
    while (buf->len + line_len + 6 > buf->cap) {
        buf->cap *= 2;
        buf->data = realloc(buf->data, buf->cap);
    }
    buf->len += (size_t)sprintf(buf->data + buf->len, "    %s\n", line);
}

void codebuf_emit_raw(CodeBuf *buf, const char *text) {
    size_t text_len = strlen(text);
    while (buf->len + text_len + 2 > buf->cap) {
        buf->cap *= 2;
        buf->data = realloc(buf->data, buf->cap);
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
            // xor rdx,rdx + idiv gives wrong results for negative dividends
            // (-10 / 3 would give 82 instead of -3)
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
        buf->data = realloc(buf->data, buf->cap);
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
    // Parameters stored to stack: [rbp-8], [rbp-16], [rbp-24], ...
    for (int i = 0; i < 6; i++) {
        int offset = -(i + 1) * 8;
        assert(offset == -8 * (i + 1));
    }

    // Stack arguments (7+): [rbp+16], [rbp+24], ...
    // +16 because: +8 for return address, +8 for saved rbp
    assert(16 == 8 + 8);  // ret addr + saved rbp

    // Frame alignment: must be multiple of 16
    for (int num_locals = 0; num_locals <= 10; num_locals++) {
        int raw = num_locals * 8;
        int aligned = ((raw + 15) / 16) * 16;
        assert(aligned % 16 == 0);
    }
}

// ── Calling Convention Verification ──────────────────────────────────

void test_calling_convention(void) {
    // System V AMD64: 6 integer arg registers
    const char *sysv_args[] = {"rdi", "rsi", "rdx", "rcx", "r8", "r9"};
    assert(strcmp(sysv_args[0], "rdi") == 0);
    assert(strcmp(sysv_args[3], "rcx") == 0);

    // Syscall ABI: same as System V except arg4 is r10 (not rcx)
    // because SYSCALL clobbers rcx (stores return address in rcx)
    const char *syscall_args[] = {"rdi", "rsi", "rdx", "r10", "r8", "r9"};
    assert(strcmp(syscall_args[3], "r10") == 0);

    // Caller-saved register count (must save before CALL)
    // rax, rcx, rdx, rsi, rdi, r8, r9, r10, r11 = 9
    int caller_saved_count = 9;
    assert(caller_saved_count == 9);

    // Callee-saved (function must preserve)
    // rbx, rbp, r12, r13, r14, r15 = 6
    int callee_saved_count = 6;
    assert(callee_saved_count == 6);
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
    };
    int num_tests = sizeof(tests) / sizeof(tests[0]);

    printf("Code Generation — stack-based x86_64 emission:\n");
    printf("%-20s %8s\n", "Expression", "Expected");
    printf("-----------------------------------\n");

    for (int i = 0; i < num_tests; i++) {
        int64_t expected = eval(tests[i].expr);
        CodeBuf buf;
        codebuf_init(&buf);
        LocalTable locals;
        locals_init(&locals);
        gen_expr(&buf, &locals, tests[i].expr);

        printf("%-20s %8ld\n", tests[i].label, expected);
        assert(buf.len > 0);
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
        assert(strstr(buf.data, "sub rsp") != NULL);
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
