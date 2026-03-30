// Vidya — Type Systems in C
//
// C is statically typed but with weak enforcement. Types exist at
// compile time but can be cast between freely. void* erases all type
// info. typedef and structs provide structure; enums provide named
// constants. There are no generics — use void* or macros.

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── typedef: naming types ──────────────────────────────────────────

typedef unsigned int uint;
typedef const char *str;

// ── Newtypes via structs: semantic safety ──────────────────────────

typedef struct { double value; } Meters;
typedef struct { double value; } Seconds;

double speed(Meters distance, Seconds time) {
    return distance.value / time.value;
}

// ── Enums: named integer constants ─────────────────────────────────

typedef enum {
    COLOR_RED = 0,
    COLOR_GREEN,
    COLOR_BLUE,
    COLOR_COUNT, // useful for array sizing
} Color;

const char *color_name(Color c) {
    switch (c) {
        case COLOR_RED:   return "red";
        case COLOR_GREEN: return "green";
        case COLOR_BLUE:  return "blue";
        default:          return "unknown";
    }
}

// ── Tagged unions: sum types ───────────────────────────────────────

typedef enum { VAL_INT, VAL_FLOAT, VAL_STRING } ValueKind;

typedef struct {
    ValueKind kind;
    union {
        int i;
        double f;
        const char *s;
    };
} Value;

Value value_int(int n)           { return (Value){.kind = VAL_INT, .i = n}; }
Value value_float(double f)      { return (Value){.kind = VAL_FLOAT, .f = f}; }
Value value_string(const char *s){ return (Value){.kind = VAL_STRING, .s = s}; }

void value_print(const Value *v, char *buf, size_t buflen) {
    switch (v->kind) {
        case VAL_INT:    snprintf(buf, buflen, "%d", v->i); break;
        case VAL_FLOAT:  snprintf(buf, buflen, "%.2f", v->f); break;
        case VAL_STRING: snprintf(buf, buflen, "%s", v->s); break;
    }
}

// ── void*: type erasure (generic programming) ──────────────────────

typedef int (*Comparator)(const void *, const void *);

int int_cmp(const void *a, const void *b) {
    return *(const int *)a - *(const int *)b;
}

int str_cmp(const void *a, const void *b) {
    return strcmp(*(const char **)a, *(const char **)b);
}

// Generic find using void*
void *array_find(const void *arr, size_t count, size_t elem_size,
                 const void *target, Comparator cmp) {
    const char *base = (const char *)arr;
    for (size_t i = 0; i < count; i++) {
        if (cmp(base + i * elem_size, target) == 0) {
            return (void *)(base + i * elem_size);
        }
    }
    return NULL;
}

// ── Function pointers: polymorphism ────────────────────────────────

typedef struct {
    const char *name;
    double (*area)(const void *self);
} ShapeVTable;

typedef struct {
    ShapeVTable vtable;
    double radius;
} Circle;

typedef struct {
    ShapeVTable vtable;
    double width, height;
} Rect;

double circle_area(const void *self) {
    const Circle *c = (const Circle *)self;
    return 3.14159265 * c->radius * c->radius;
}

double rect_area(const void *self) {
    const Rect *r = (const Rect *)self;
    return r->width * r->height;
}

Circle circle_new(double r) {
    return (Circle){
        .vtable = {.name = "circle", .area = circle_area},
        .radius = r,
    };
}

Rect rect_new(double w, double h) {
    return (Rect){
        .vtable = {.name = "rectangle", .area = rect_area},
        .width = w, .height = h,
    };
}

int main(void) {
    // ── Primitive types ────────────────────────────────────────────
    assert(sizeof(char) == 1);
    assert(sizeof(int) >= 2);   // at least 16 bits
    assert(sizeof(long) >= 4);  // at least 32 bits

    // ── typedef usage ──────────────────────────────────────────────
    uint count = 42;
    str greeting = "hello";
    assert(count == 42);
    assert(strcmp(greeting, "hello") == 0);

    // ── Newtypes ───────────────────────────────────────────────────
    Meters d = {100.0};
    Seconds t = {9.58};
    double v = speed(d, t);
    assert(v > 10.0);
    // speed(t, d); // won't compile — type mismatch!

    // ── Enums ──────────────────────────────────────────────────────
    assert(COLOR_RED == 0);
    assert(COLOR_COUNT == 3);
    assert(strcmp(color_name(COLOR_GREEN), "green") == 0);

    // Array indexed by enum
    int color_values[COLOR_COUNT] = {255, 128, 64};
    assert(color_values[COLOR_RED] == 255);

    // ── Tagged unions ──────────────────────────────────────────────
    Value vi = value_int(42);
    Value vf = value_float(3.14);
    Value vs = value_string("hello");

    char buf[64];
    value_print(&vi, buf, sizeof(buf));
    assert(strcmp(buf, "42") == 0);

    value_print(&vf, buf, sizeof(buf));
    assert(strcmp(buf, "3.14") == 0);

    value_print(&vs, buf, sizeof(buf));
    assert(strcmp(buf, "hello") == 0);

    // ── void* generic find ─────────────────────────────────────────
    int nums[] = {10, 20, 30, 40, 50};
    int target = 30;
    int *found = array_find(nums, 5, sizeof(int), &target, int_cmp);
    assert(found != NULL);
    assert(*found == 30);

    target = 99;
    found = array_find(nums, 5, sizeof(int), &target, int_cmp);
    assert(found == NULL);

    // ── Function pointer dispatch (vtable pattern) ─────────────────
    Circle c = circle_new(1.0);
    Rect r = rect_new(3.0, 4.0);

    // Polymorphic call through vtable
    double ca = c.vtable.area(&c);
    assert(ca > 3.14 && ca < 3.15);

    double ra = r.vtable.area(&r);
    assert(ra == 12.0);

    assert(strcmp(c.vtable.name, "circle") == 0);
    assert(strcmp(r.vtable.name, "rectangle") == 0);

    // ── Implicit conversions (C's weakness) ────────────────────────
    // C silently converts between numeric types
    int i = 3;
    double f = i;      // implicit widening: safe
    assert(f == 3.0);

    double pi = 3.14;
    int truncated = (int)pi;  // explicit narrowing
    assert(truncated == 3);

    // void* can hold any pointer — no type safety
    int x = 42;
    void *vp = &x;
    int *ip = (int *)vp;
    assert(*ip == 42);

    // ── const: immutability qualifier ──────────────────────────────
    const int immutable = 42;
    // immutable = 43; // ← compile error
    assert(immutable == 42);

    const char *const_str = "hello";
    // const_str[0] = 'H'; // ← compile error (or undefined behavior)
    assert(strcmp(const_str, "hello") == 0);

    printf("All type system examples passed.\n");
    return 0;
}
