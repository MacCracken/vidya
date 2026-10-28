// Vidya — Macro Systems in C
//
// The C preprocessor (cpp) is a text substitution engine that runs
// before compilation. It has no knowledge of C syntax, types, or
// scoping. This makes it powerful but dangerous — no hygiene, no
// type checking, no scoping rules.
//
// Concepts demonstrated:
//   1. Include guards — prevent double inclusion
//   2. Object-like and function-like macros
//   3. Stringify (#) and token paste (##) operators
//   4. Variadic macros (__VA_ARGS__)
//   5. X-macros — code generation from a list
//   6. Conditional compilation (#ifdef, #if)
//   7. Macro pitfalls — why Rust macros are better
//
// Comparison:
//   C preprocessor: text substitution, no hygiene, no scoping
//   Rust macro_rules!: pattern matching on token trees, hygienic
//   Rust proc macros: full AST manipulation, runs Rust code

#include <assert.h>
#include <stdio.h>
#include <string.h>

// ── Include Guards ────────────────────────────────────────────────
// Prevent a header from being processed twice. Without this, its
// contents are redefined: object and function definitions, and (before
// C23) every struct, are compile errors. C23 (N3037) tolerates only an
// identical redefinition of a tagged struct/union/enum.
//
// #ifndef MY_HEADER_H
// #define MY_HEADER_H
// ... declarations ...
// #endif
//
// Modern alternative: #pragma once (non-standard but universal)

// ── Object-Like Macros: Constants ─────────────────────────────────
// Simple text replacement. No parentheses, no arguments.
// Use for constants, feature flags, platform detection.

#define MAX_BUFFER_SIZE 256
#define VERSION_MAJOR 1
#define VERSION_MINOR 5
#define VERSION_STRING "1.5.0"

// ── Function-Like Macros ──────────────────────────────────────────
// Take arguments. ALWAYS parenthesize the arguments and the whole
// expression — operator precedence doesn't work like function calls.

// BAD: no parens — BAD_MIN(1, 5) + 1 expands to 1 < 5 ? 1 : 5 + 1, so the
// + 1 binds to the else branch and the result is 1, not 2.
// #define BAD_MIN(a, b) a < b ? a : b

// GOOD: fully parenthesized
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define CLAMP(x, lo, hi) (MIN(MAX((x), (lo)), (hi)))

// But even parenthesized macros have double-evaluation:
// MIN(expensive(), y) calls expensive() TWICE if it's the minimum.
// Rust macro_rules! has the same hazard if $a appears twice in the
// expansion (its expr fragments fix precedence, not evaluation count).
// The C fix is a static inline function, which evaluates each argument once.

// ── Stringify (#) ─────────────────────────────────────────────────
// The # operator turns a macro argument into a string literal.
// Used for assertion messages, debug logging, serialization.

#define STRINGIFY(x) #x
#define ASSERT_EQ(a, b)                                              \
    do {                                                             \
        if ((a) != (b)) {                                            \
            printf("FAIL: %s != %s at %s:%d\n",                      \
                   STRINGIFY(a), STRINGIFY(b), __FILE__, __LINE__);   \
            assert(0);                                               \
        }                                                            \
    } while (0)

// ── Token Paste (##) ──────────────────────────────────────────────
// The ## operator concatenates two tokens into one.
// Used for generating unique names, type-generic functions.

#define MAKE_GETTER(type, field) \
    static type get_##field(const void *obj, int offset) { \
        return *(const type *)((const char *)obj + offset); \
    }

// Generates: get_int, get_double
MAKE_GETTER(int, int)
MAKE_GETTER(double, double)

// ── Variadic Macros ───────────────────────────────────────────────
// __VA_ARGS__ captures variable arguments, like Rust's $(...)*

#define LOG(fmt, ...) printf("[LOG] " fmt "\n" __VA_OPT__(,) __VA_ARGS__)
// __VA_OPT__(,) emits the comma only when arguments were passed (C23;
// C23 also allows LOG("no args") with zero variadic arguments). Older
// code uses the GCC/Clang extension `, ##__VA_ARGS__` for the same job.

// ── X-Macros: Code Generation from a Table ────────────────────────
// Define a list of data once, then expand it in multiple contexts.
// This is the C equivalent of Rust's macro-generated enum + impl.

// The "X-table": each entry defines (NAME, VALUE, STRING)
#define ERROR_TABLE(X) \
    X(ERR_NONE,    0, "success")        \
    X(ERR_IO,      1, "i/o error")      \
    X(ERR_PARSE,   2, "parse error")    \
    X(ERR_MEMORY,  3, "out of memory")  \
    X(ERR_TIMEOUT, 4, "timeout")

// Expand the table to generate the enum
#define GENERATE_ENUM(name, val, str) name = val,
typedef enum {
    ERROR_TABLE(GENERATE_ENUM)
} ErrorCode;

// Expand the table to generate the string lookup
#define GENERATE_STRING(name, val, str) case name: return str;
static const char *error_to_string(ErrorCode code) {
    switch (code) {
        ERROR_TABLE(GENERATE_STRING)
        default: return "unknown";
    }
}

// Expand the table to generate the name lookup
#define GENERATE_NAME(name, val, str) case name: return #name;
static const char *error_to_name(ErrorCode code) {
    switch (code) {
        ERROR_TABLE(GENERATE_NAME)
        default: return "UNKNOWN";
    }
}

// ── Conditional Compilation ───────────────────────────────────────

#define ENABLE_EXTRA_CHECKS

#ifdef ENABLE_EXTRA_CHECKS
static int extra_validation(int x) {
    return x >= 0 && x <= 100;
}
#endif

// Platform detection (standard macros)
// #ifdef _WIN32
//     #define PATH_SEP '\\'
// #else
//     #define PATH_SEP '/'
// #endif

// ── do { ... } while(0) Idiom ─────────────────────────────────────
// Multi-statement macros must use do/while(0) to behave as a single
// statement. Without it, if/else breaks:
//   if (x) MULTI_MACRO(y); else z;
// Unbraced, only the macro's first statement is guarded by the if; braced
// as { ... }, the trailing ; ends the if and the else is a syntax error.

#define SWAP(a, b)       \
    do {                 \
        int tmp_ = (a);  \
        (a) = (b);       \
        (b) = tmp_;      \
    } while (0)

// ── Type-Generic Selection (C11 _Generic) ─────────────────────────
// The closest C gets to Rust's trait dispatch at compile time.
// _Generic selects an expression based on the type of its first argument.

static const char *type_name_int(int x) { (void)x; return "int"; }
static const char *type_name_double(double x) { (void)x; return "double"; }
static const char *type_name_str(const char *x) { (void)x; return "string"; }

#define TYPE_NAME(x) _Generic((x), \
    int: type_name_int,            \
    double: type_name_double,      \
    const char *: type_name_str,   \
    char *: type_name_str          \
)(x)

// ── Compile-Time Assertions ───────────────────────────────────────
// static_assert checks conditions at compile time. Like Rust's const
// assertions. It is a keyword in C23 and the message is optional; C11
// spelled it _Static_assert, which C23 keeps as an alternate spelling.

static_assert(sizeof(int) >= 4, "int must be at least 32 bits");
static_assert(MAX_BUFFER_SIZE == 256);

int main(void) {
    // ── Object-like macros ────────────────────────────────────────
    char buf[MAX_BUFFER_SIZE];
    assert(sizeof(buf) == 256);
    assert(VERSION_MAJOR == 1);
    assert(strcmp(VERSION_STRING, "1.5.0") == 0);

    // ── Function-like macros ──────────────────────────────────────
    ASSERT_EQ(MIN(3, 7), 3);
    ASSERT_EQ(MAX(3, 7), 7);
    ASSERT_EQ(CLAMP(15, 0, 10), 10);
    ASSERT_EQ(CLAMP(-5, 0, 10), 0);
    ASSERT_EQ(CLAMP(5, 0, 10), 5);

    // ── Stringify ─────────────────────────────────────────────────
    assert(strcmp(STRINGIFY(hello), "hello") == 0);
    assert(strcmp(STRINGIFY(2 + 2), "2 + 2") == 0);

    // ── Token paste ───────────────────────────────────────────────
    int data = 42;
    assert(get_int(&data, 0) == 42);

    double dval = 3.14;
    double got = get_double(&dval, 0);
    assert(got > 3.13 && got < 3.15);

    // ── Variadic macros ───────────────────────────────────────────
    LOG("testing macros: %d", 42);
    LOG("no args");

    // ── X-macros ──────────────────────────────────────────────────
    assert(ERR_NONE == 0);
    assert(ERR_TIMEOUT == 4);
    assert(strcmp(error_to_string(ERR_IO), "i/o error") == 0);
    assert(strcmp(error_to_string(ERR_MEMORY), "out of memory") == 0);
    assert(strcmp(error_to_name(ERR_PARSE), "ERR_PARSE") == 0);

    // ── Conditional compilation ───────────────────────────────────
    #ifdef ENABLE_EXTRA_CHECKS
    assert(extra_validation(50) == 1);
    assert(extra_validation(150) == 0);
    #endif

    // ── SWAP macro ────────────────────────────────────────────────
    int a = 10, b = 20;
    SWAP(a, b);
    assert(a == 20 && b == 10);

    // ── Type-generic selection ────────────────────────────────────
    assert(strcmp(TYPE_NAME(42), "int") == 0);
    assert(strcmp(TYPE_NAME(3.14), "double") == 0);
    assert(strcmp(TYPE_NAME("hi"), "string") == 0);

    // ── Predefined macros ─────────────────────────────────────────
    // __FILE__, __LINE__, __func__ are predefined by the compiler
    assert(strlen(__FILE__) > 0);
    assert(__LINE__ > 0);
    assert(strcmp(__func__, "main") == 0);

    printf("All macro system examples passed.\n");
    return 0;
}
