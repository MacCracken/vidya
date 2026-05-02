// Vidya — SQL Parsing in C
//
// Idiomatic shape: a char-by-char state machine driving a fixed-size
// token buffer. Each Token holds a {kind, ptr, len} triple — zero-copy
// references back into the original SQL string. Keywords are detected
// by uppercasing during compare, which keeps the matcher case-insensitive
// without mutating the source. Mirrors the cyrius.cyr reference.

#include <assert.h>
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef enum {
    T_EOF    = 0,
    T_IDENT  = 1,
    T_INT    = 2,
    T_STAR   = 3,
    T_EQ     = 4,
    T_LPAREN = 5,
    T_RPAREN = 6,
    T_COMMA  = 7,
    T_SELECT = 10,
    T_FROM   = 11,
    T_WHERE  = 12,
} Tok;

typedef struct {
    Tok         kind;
    const char *p;
    int         len;
} Token;

#define MAX_TOKENS 128

static int kw_eq(const char *p, int len, const char *kw) {
    int kl = (int)strlen(kw);
    if (len != kl) return 0;
    for (int i = 0; i < len; i++) {
        char a = p[i];
        if (a >= 'a' && a <= 'z') a = (char)(a - 32);
        if (a != kw[i]) return 0;
    }
    return 1;
}

static Tok classify(const char *p, int len) {
    if (kw_eq(p, len, "SELECT")) return T_SELECT;
    if (kw_eq(p, len, "FROM"))   return T_FROM;
    if (kw_eq(p, len, "WHERE"))  return T_WHERE;
    return T_IDENT;
}

static int is_alpha(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_';
}
static int is_alnum(char c) {
    return is_alpha(c) || (c >= '0' && c <= '9');
}

static int tokenize(const char *sql, Token *out, int max) {
    int pos = 0;
    int n = 0;
    int slen = (int)strlen(sql);

    while (pos < slen && n < max - 1) {
        char c = sql[pos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            pos++;
            continue;
        }
        if (is_alpha(c)) {
            int start = pos;
            while (pos < slen && is_alnum(sql[pos])) pos++;
            out[n].kind = classify(&sql[start], pos - start);
            out[n].p    = &sql[start];
            out[n].len  = pos - start;
            n++;
            continue;
        }
        if (c >= '0' && c <= '9') {
            int start = pos;
            while (pos < slen && sql[pos] >= '0' && sql[pos] <= '9') pos++;
            out[n].kind = T_INT;
            out[n].p    = &sql[start];
            out[n].len  = pos - start;
            n++;
            continue;
        }
        Tok k;
        switch (c) {
            case '*': k = T_STAR;   break;
            case '=': k = T_EQ;     break;
            case '(': k = T_LPAREN; break;
            case ')': k = T_RPAREN; break;
            case ',': k = T_COMMA;  break;
            default:  pos++;        continue;
        }
        out[n].kind = k;
        out[n].p    = &sql[pos];
        out[n].len  = 1;
        n++;
        pos++;
    }
    out[n].kind = T_EOF;
    out[n].p    = NULL;
    out[n].len  = 0;
    n++;
    return n;
}

static int is_valid_select(const Token *toks, int n) {
    if (n < 1 || toks[0].kind != T_SELECT) return 0;
    int from_idx = -1;
    for (int i = 0; i < n; i++) {
        if (toks[i].kind == T_FROM) { from_idx = i; break; }
    }
    if (from_idx < 0) return 0;
    if (from_idx == 1) return 0; // nothing between SELECT and FROM
    if (from_idx + 1 >= n || toks[from_idx + 1].kind != T_IDENT) return 0;
    return 1;
}

static void assert_kinds(const Token *toks, int n, const Tok *exp, int en, const char *msg) {
    if (n != en) {
        fprintf(stderr, "%s: token count %d != expected %d\n", msg, n, en);
        assert(n == en);
    }
    for (int i = 0; i < n; i++) {
        if (toks[i].kind != exp[i]) {
            fprintf(stderr, "%s [%d]: kind %d != %d\n", msg, i, toks[i].kind, exp[i]);
            assert(toks[i].kind == exp[i]);
        }
    }
}

static int text_eq(const Token *t, const char *s) {
    int sl = (int)strlen(s);
    if (t->len != sl) return 0;
    return memcmp(t->p, s, sl) == 0;
}

int main(void) {
    Token toks[MAX_TOKENS];
    int n;

    // Test 1: canonical SELECT (mirrors cyrius reference)
    n = tokenize("SELECT * FROM users WHERE id = 1", toks, MAX_TOKENS);
    Tok e1[] = { T_SELECT, T_STAR, T_FROM, T_IDENT, T_WHERE,
                 T_IDENT, T_EQ, T_INT, T_EOF };
    assert_kinds(toks, n, e1, (int)(sizeof(e1)/sizeof(e1[0])), "canonical");
    assert(text_eq(&toks[3], "users"));
    assert(text_eq(&toks[5], "id"));
    assert(text_eq(&toks[7], "1"));

    // Test 2: case insensitive
    n = tokenize("select * from T", toks, MAX_TOKENS);
    Tok e2[] = { T_SELECT, T_STAR, T_FROM, T_IDENT, T_EOF };
    assert_kinds(toks, n, e2, 5, "lowercase");

    n = tokenize("Select * From T", toks, MAX_TOKENS);
    assert_kinds(toks, n, e2, 5, "mixed case");

    // Test 3: 'selected' is an identifier, not SELECT
    n = tokenize("selected", toks, MAX_TOKENS);
    assert(toks[0].kind == T_IDENT);
    assert(text_eq(&toks[0], "selected"));

    // Test 4: parens, commas
    n = tokenize("SELECT (a, b) FROM t", toks, MAX_TOKENS);
    Tok e4[] = { T_SELECT, T_LPAREN, T_IDENT, T_COMMA, T_IDENT, T_RPAREN,
                 T_FROM, T_IDENT, T_EOF };
    assert_kinds(toks, n, e4, 9, "parens");

    // Test 5: integer literal
    n = tokenize("12345", toks, MAX_TOKENS);
    assert(toks[0].kind == T_INT);
    assert(text_eq(&toks[0], "12345"));

    // Test 6: validator
    n = tokenize("SELECT * FROM t", toks, MAX_TOKENS);
    assert(is_valid_select(toks, n) == 1);
    n = tokenize("SELECT a FROM t WHERE id = 1", toks, MAX_TOKENS);
    assert(is_valid_select(toks, n) == 1);
    n = tokenize("FROM t", toks, MAX_TOKENS);
    assert(is_valid_select(toks, n) == 0);
    n = tokenize("SELECT FROM t", toks, MAX_TOKENS);
    assert(is_valid_select(toks, n) == 0);
    n = tokenize("SELECT * FROM", toks, MAX_TOKENS);
    assert(is_valid_select(toks, n) == 0);

    // Test 7: whitespace tolerance
    n = tokenize("  SELECT\t*\nFROM\tt  ", toks, MAX_TOKENS);
    assert_kinds(toks, n, e2, 5, "whitespace");

    printf("All sql_parsing examples passed.\n");
    return 0;
}
