// Vidya — Pattern Matching in C
//
// C has no pattern matching like Rust or Python. switch/case works only
// on integers. For structured matching, you use if-else chains, function
// pointers (dispatch tables), and tagged unions.

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Tagged union: C's enum + union pattern ─────────────────────────

typedef enum { SHAPE_CIRCLE, SHAPE_RECT, SHAPE_TRI } ShapeKind;

typedef struct {
    ShapeKind kind;
    union {
        struct { double radius; } circle;
        struct { double width, height; } rect;
        struct { double base, height; } tri;
    };
} Shape;

double shape_area(const Shape *s) {
    switch (s->kind) {
        case SHAPE_CIRCLE: return 3.14159265 * s->circle.radius * s->circle.radius;
        case SHAPE_RECT:   return s->rect.width * s->rect.height;
        case SHAPE_TRI:    return 0.5 * s->tri.base * s->tri.height;
        default:           return 0.0;
    }
}

const char *shape_name(const Shape *s) {
    switch (s->kind) {
        case SHAPE_CIRCLE: return "circle";
        case SHAPE_RECT:   return "rectangle";
        case SHAPE_TRI:    return "triangle";
        default:           return "unknown";
    }
}

// ── Dispatch table: function pointer matching ──────────────────────

typedef const char *(*StatusHandler)(void);

const char *handle_ok(void)        { return "ok"; }
const char *handle_redirect(void)  { return "redirect"; }
const char *handle_not_found(void) { return "not found"; }
const char *handle_error(void)     { return "server error"; }
const char *handle_unknown(void)   { return "unknown"; }

typedef struct {
    int code;
    StatusHandler handler;
} StatusEntry;

const char *classify_status(int code) {
    static const StatusEntry table[] = {
        {200, handle_ok},
        {301, handle_redirect},
        {302, handle_redirect},
        {404, handle_not_found},
        {500, handle_error},
    };
    static const size_t table_len = sizeof(table) / sizeof(table[0]);

    for (size_t i = 0; i < table_len; i++) {
        if (table[i].code == code) {
            return table[i].handler();
        }
    }
    return handle_unknown();
}

// ── String matching helper ─────────────────────────────────────────

int starts_with(const char *str, const char *prefix) {
    return strncmp(str, prefix, strlen(prefix)) == 0;
}

int ends_with(const char *str, const char *suffix) {
    size_t slen = strlen(str);
    size_t suflen = strlen(suffix);
    if (suflen > slen) return 0;
    return strcmp(str + slen - suflen, suffix) == 0;
}

const char *classify_range(int x) {
    if (x < 0) return "negative";
    if (x == 0) return "zero";
    if (x <= 10) return "small";
    return "large";
}

int is_weekend(int day) {
    switch (day) {
        case 0: case 6: return 1;
        default: return 0;
    }
}

int main(void) {
    // ── switch/case on integers ────────────────────────────────────
    int n = 42;
    const char *label;
    switch (n) {
        case 0:  label = "zero"; break;
        case 42: label = "answer"; break;
        default: label = "other"; break;
    }
    assert(strcmp(label, "answer") == 0);

    // ── Range matching (if-else, no range syntax in switch) ────────
    assert(strcmp(classify_range(-5), "negative") == 0);
    assert(strcmp(classify_range(0), "zero") == 0);
    assert(strcmp(classify_range(7), "small") == 0);
    assert(strcmp(classify_range(100), "large") == 0);

    // ── Tagged union matching ──────────────────────────────────────
    Shape circle = {.kind = SHAPE_CIRCLE, .circle = {.radius = 1.0}};
    Shape rect = {.kind = SHAPE_RECT, .rect = {.width = 3, .height = 4}};
    Shape tri = {.kind = SHAPE_TRI, .tri = {.base = 6, .height = 4}};

    double a = shape_area(&circle);
    assert(a > 3.14 && a < 3.15);
    assert(shape_area(&rect) == 12.0);
    assert(shape_area(&tri) == 12.0);

    assert(strcmp(shape_name(&circle), "circle") == 0);
    assert(strcmp(shape_name(&rect), "rectangle") == 0);

    // ── Dispatch table ─────────────────────────────────────────────
    assert(strcmp(classify_status(200), "ok") == 0);
    assert(strcmp(classify_status(301), "redirect") == 0);
    assert(strcmp(classify_status(404), "not found") == 0);
    assert(strcmp(classify_status(999), "unknown") == 0);

    // ── String prefix/suffix matching ──────────────────────────────
    assert(starts_with("hello world", "hello"));
    assert(!starts_with("hello world", "world"));
    assert(ends_with("archive.tar.gz", ".tar.gz"));
    assert(ends_with("main.rs", ".rs"));

    // ── Fallthrough in switch (C's default behavior) ───────────────
    // Unlike most languages, C switch falls through without break!
    int val = 1;
    int hit_one = 0, hit_two = 0;
    switch (val) {
        case 1:
            hit_one = 1;
            // no break — falls through!
        case 2:
            hit_two = 1;
            break;
    }
    assert(hit_one && hit_two); // both hit due to fallthrough

    // ── Multiple values per case (using fallthrough) ───────────────
    assert(is_weekend(0));  // Sunday
    assert(is_weekend(6));  // Saturday
    assert(!is_weekend(3)); // Wednesday

    printf("All pattern matching examples passed.\n");
    return 0;
}
