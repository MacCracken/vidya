// Vidya — Lexing and Parsing in C
//
// Demonstrates a complete lexer + recursive-descent parser for arithmetic
// expressions. This is the foundational pattern for every hand-written
// compiler frontend:
//   1. Lexer: chars -> tokens (scanning with position tracking)
//   2. Parser: tokens -> AST (recursive descent with Pratt binding power)
//   3. Evaluator: AST -> result (tree-walk over the AST)
//
// Supports +, -, *, /, unary minus, and parenthesized sub-expressions.
// AST nodes are heap-allocated structs with a tagged union (ExprKind).

#include <assert.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Tokens ────────────────────────────────────────────────────────────

typedef enum {
    TOK_NUMBER,
    TOK_PLUS,
    TOK_MINUS,
    TOK_STAR,
    TOK_SLASH,
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_EOF,
} TokenKind;

typedef struct {
    TokenKind kind;
    int       pos;
    long      number_value;  // valid when kind == TOK_NUMBER
} Token;

// ── Lexer ─────────────────────────────────────────────────────────────

typedef struct {
    const char *source;
    int         pos;
    int         len;
} Lexer;

static void lexer_init(Lexer *lex, const char *source) {
    lex->source = source;
    lex->pos = 0;
    lex->len = (int)strlen(source);
}

static char lexer_peek(const Lexer *lex) {
    if (lex->pos < lex->len) return lex->source[lex->pos];
    return '\0';
}

static char lexer_advance(Lexer *lex) {
    if (lex->pos < lex->len) return lex->source[lex->pos++];
    return '\0';
}

static void lexer_skip_whitespace(Lexer *lex) {
    while (lex->pos < lex->len && isspace((unsigned char)lex->source[lex->pos])) {
        lex->pos++;
    }
}

static Token lexer_next(Lexer *lex) {
    lexer_skip_whitespace(lex);

    Token tok;
    tok.pos = lex->pos;
    tok.number_value = 0;

    char c = lexer_advance(lex);
    if (c == '\0') { tok.kind = TOK_EOF;    return tok; }

    switch (c) {
        case '+': tok.kind = TOK_PLUS;   return tok;
        case '-': tok.kind = TOK_MINUS;  return tok;
        case '*': tok.kind = TOK_STAR;   return tok;
        case '/': tok.kind = TOK_SLASH;  return tok;
        case '(': tok.kind = TOK_LPAREN; return tok;
        case ')': tok.kind = TOK_RPAREN; return tok;
        default: break;
    }

    if (isdigit((unsigned char)c)) {
        long val = c - '0';
        while (isdigit((unsigned char)lexer_peek(lex))) {
            val = val * 10 + (lexer_advance(lex) - '0');
        }
        tok.kind = TOK_NUMBER;
        tok.number_value = val;
        return tok;
    }

    fprintf(stderr, "unexpected character '%c' at position %d\n", c, tok.pos);
    exit(1);
}

// ── AST ───────────────────────────────────────────────────────────────

typedef enum {
    EXPR_NUMBER,
    EXPR_UNARY_MINUS,
    EXPR_BINOP,
} ExprKind;

typedef struct Expr Expr;

struct Expr {
    ExprKind kind;
    union {
        long number;                       // EXPR_NUMBER
        struct { Expr *operand; } unary;   // EXPR_UNARY_MINUS
        struct {
            char  op;
            Expr *left;
            Expr *right;
        } binop;                           // EXPR_BINOP
    };
};

static Expr *expr_number(long value) {
    Expr *e = malloc(sizeof(Expr));
    e->kind = EXPR_NUMBER;
    e->number = value;
    return e;
}

static Expr *expr_unary_minus(Expr *operand) {
    Expr *e = malloc(sizeof(Expr));
    e->kind = EXPR_UNARY_MINUS;
    e->unary.operand = operand;
    return e;
}

static Expr *expr_binop(char op, Expr *left, Expr *right) {
    Expr *e = malloc(sizeof(Expr));
    e->kind = EXPR_BINOP;
    e->binop.op = op;
    e->binop.left = left;
    e->binop.right = right;
    return e;
}

static void expr_free(Expr *e) {
    if (!e) return;
    switch (e->kind) {
        case EXPR_NUMBER: break;
        case EXPR_UNARY_MINUS:
            expr_free(e->unary.operand);
            break;
        case EXPR_BINOP:
            expr_free(e->binop.left);
            expr_free(e->binop.right);
            break;
    }
    free(e);
}

// ── Pratt Parser ──────────────────────────────────────────────────────

typedef struct {
    Lexer lexer;
    Token current;
} Parser;

static void parser_init(Parser *p, const char *source) {
    lexer_init(&p->lexer, source);
    p->current = lexer_next(&p->lexer);
}

static Token parser_advance(Parser *p) {
    Token prev = p->current;
    p->current = lexer_next(&p->lexer);
    return prev;
}

static void parser_expect(Parser *p, TokenKind kind) {
    if (p->current.kind != kind) {
        fprintf(stderr, "expected token %d at position %d, got %d\n",
                kind, p->current.pos, p->current.kind);
        exit(1);
    }
    parser_advance(p);
}

// Binding power: (left, right). Returns 0 if not an infix operator.
static int infix_bp(TokenKind kind, int *l_bp, int *r_bp) {
    switch (kind) {
        case TOK_PLUS:  case TOK_MINUS: *l_bp = 1; *r_bp = 2; return 1;
        case TOK_STAR:  case TOK_SLASH: *l_bp = 3; *r_bp = 4; return 1;
        default: return 0;
    }
}

static int prefix_bp(TokenKind kind) {
    if (kind == TOK_MINUS) return 5;
    return -1;
}

static char op_char(TokenKind kind) {
    switch (kind) {
        case TOK_PLUS:  return '+';
        case TOK_MINUS: return '-';
        case TOK_STAR:  return '*';
        case TOK_SLASH: return '/';
        default:        return '?';
    }
}

static Expr *parse_expr(Parser *p, int min_bp);

static Expr *parse_expr(Parser *p, int min_bp) {
    Expr *lhs;

    // ── Prefix / atoms ───────────────────────────────────────────
    switch (p->current.kind) {
        case TOK_NUMBER: {
            Token tok = parser_advance(p);
            lhs = expr_number(tok.number_value);
            break;
        }
        case TOK_LPAREN: {
            parser_advance(p);
            lhs = parse_expr(p, 0);
            parser_expect(p, TOK_RPAREN);
            break;
        }
        default: {
            int pbp = prefix_bp(p->current.kind);
            if (pbp >= 0) {
                parser_advance(p);
                Expr *operand = parse_expr(p, pbp);
                lhs = expr_unary_minus(operand);
            } else {
                fprintf(stderr, "expected expression at position %d\n", p->current.pos);
                exit(1);
            }
            break;
        }
    }

    // ── Infix loop ───────────────────────────────────────────────
    for (;;) {
        TokenKind op_kind = p->current.kind;
        if (op_kind == TOK_EOF || op_kind == TOK_RPAREN) break;

        int l_bp, r_bp;
        if (!infix_bp(op_kind, &l_bp, &r_bp)) break;
        if (l_bp < min_bp) break;

        char op = op_char(op_kind);
        parser_advance(p);
        Expr *rhs = parse_expr(p, r_bp);
        lhs = expr_binop(op, lhs, rhs);
    }

    return lhs;
}

// ── Tree-walk evaluator ───────────────────────────────────────────────

static long eval(const Expr *e) {
    switch (e->kind) {
        case EXPR_NUMBER:
            return e->number;
        case EXPR_UNARY_MINUS:
            return -eval(e->unary.operand);
        case EXPR_BINOP: {
            long l = eval(e->binop.left);
            long r = eval(e->binop.right);
            switch (e->binop.op) {
                case '+': return l + r;
                case '-': return l - r;
                case '*': return l * r;
                case '/': return l / r;
                default:  return 0;
            }
        }
    }
    return 0;
}

// ── Main ──────────────────────────────────────────────────────────────

typedef struct {
    const char *input;
    long        expected;
} TestCase;

int main(void) {
    TestCase tests[] = {
        {"42",                 42},
        {"2 + 3",              5},
        {"2 + 3 * 4",         14},
        {"(2 + 3) * 4",       20},
        {"-5 + 3",            -2},
        {"10 - 3 - 2",         5},
        {"2 * 3 + 4 * 5",     26},
        {"-(3 + 4) * 2",     -14},
        {"3 + 4 * (2 - 1)",    7},
    };
    int count = sizeof(tests) / sizeof(tests[0]);

    for (int i = 0; i < count; i++) {
        Parser p;
        parser_init(&p, tests[i].input);
        Expr *ast = parse_expr(&p, 0);
        long result = eval(ast);

        printf("%-25s => %4ld  (expected %4ld) %s\n",
               tests[i].input, result, tests[i].expected,
               result == tests[i].expected ? "ok" : "FAIL");

        assert(result == tests[i].expected);
        expr_free(ast);
    }

    printf("\nAll %d tests passed.\n", count);
    return 0;
}
