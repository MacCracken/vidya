// Vidya — Trait and Typeclass Systems in C
//
// C has no traits, interfaces, or virtual methods. Polymorphism is
// achieved through manual vtable dispatch: a struct of function
// pointers paired with a data pointer. This is exactly what the
// compiler generates for Rust's dyn Trait — in C you build it by hand.
//
// Concepts demonstrated:
//   1. Manual vtable: struct of function pointers
//   2. Fat pointer: (data_ptr, vtable_ptr) pair
//   3. Static dispatch: direct function calls (monomorphization equivalent)
//   4. Dynamic dispatch: indirect calls through vtable
//   5. Interface composition: combining multiple vtables

#define _GNU_SOURCE
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Manual Vtable: Shape trait ────────────────────────────────────
// Rust:  trait Shape { fn area(&self) -> f64; fn name(&self) -> &str; }
// C:    struct of function pointers = vtable

// The vtable: one function pointer per "trait method"
typedef struct {
    double (*area)(const void *self);
    const char *(*name)(const void *self);
    void (*describe)(const void *self, char *buf, size_t buflen);
} ShapeVtable;

// The "dyn Shape" fat pointer: data + vtable
typedef struct {
    void *data;
    const ShapeVtable *vtable;
} ShapeObj;

// ── Circle: implements Shape ──────────────────────────────────────

typedef struct {
    double cx, cy, radius;
} Circle;

static double circle_area(const void *self) {
    const Circle *c = (const Circle *)self;
    return M_PI * c->radius * c->radius;
}

static const char *circle_name(const void *self) {
    (void)self;
    return "Circle";
}

static void circle_describe(const void *self, char *buf, size_t buflen) {
    const Circle *c = (const Circle *)self;
    snprintf(buf, buflen, "Circle(r=%.1f) area=%.2f", c->radius, circle_area(self));
}

// Circle's vtable — static, shared by all Circle instances
static const ShapeVtable CIRCLE_VTABLE = {
    .area = circle_area,
    .name = circle_name,
    .describe = circle_describe,
};

static ShapeObj circle_new(double cx, double cy, double r) {
    Circle *c = malloc(sizeof(Circle));
    assert(c != NULL);
    c->cx = cx;
    c->cy = cy;
    c->radius = r;
    return (ShapeObj){.data = c, .vtable = &CIRCLE_VTABLE};
}

// ── Rectangle: implements Shape ───────────────────────────────────

typedef struct {
    double x, y, width, height;
} Rectangle;

static double rect_area(const void *self) {
    const Rectangle *r = (const Rectangle *)self;
    return r->width * r->height;
}

static const char *rect_name(const void *self) {
    (void)self;
    return "Rect";
}

static void rect_describe(const void *self, char *buf, size_t buflen) {
    const Rectangle *r = (const Rectangle *)self;
    snprintf(buf, buflen, "Rect(%.0fx%.0f) area=%.2f",
             r->width, r->height, rect_area(self));
}

static const ShapeVtable RECT_VTABLE = {
    .area = rect_area,
    .name = rect_name,
    .describe = rect_describe,
};

static ShapeObj rect_new(double x, double y, double w, double h) {
    Rectangle *r = malloc(sizeof(Rectangle));
    assert(r != NULL);
    r->x = x;
    r->y = y;
    r->width = w;
    r->height = h;
    return (ShapeObj){.data = r, .vtable = &RECT_VTABLE};
}

// ── Dynamic dispatch: call through vtable ─────────────────────────
// This is what `shape.area()` compiles to for `dyn Shape` in Rust:
//   load vtable pointer → load function pointer → indirect call

static double shape_area(const ShapeObj *obj) {
    return obj->vtable->area(obj->data);  // indirect call
}

static const char *shape_name(const ShapeObj *obj) {
    return obj->vtable->name(obj->data);
}

static void shape_describe(const ShapeObj *obj, char *buf, size_t buflen) {
    obj->vtable->describe(obj->data, buf, buflen);
}

// ── Static dispatch: direct call, no vtable ───────────────────────
// This is what `impl Shape for Circle` + monomorphization looks like:
// the compiler knows the concrete type and calls the function directly.

static double sum_circle_areas(const Circle *circles, size_t n) {
    double total = 0.0;
    for (size_t i = 0; i < n; i++) {
        // Direct call — no vtable, inlinable, like Rust's static dispatch
        total += M_PI * circles[i].radius * circles[i].radius;
    }
    return total;
}

// ── Interface composition: multiple vtables ───────────────────────
// Rust: trait Drawable: Shape + Display
// C: combine multiple vtable structs

typedef struct {
    int (*serialize)(const void *self, char *buf, size_t buflen);
} SerializableVtable;

// Combined "trait object" with two vtables
typedef struct {
    void *data;
    const ShapeVtable *shape_vt;
    const SerializableVtable *serial_vt;
} DrawableObj;

static int circle_serialize(const void *self, char *buf, size_t buflen) {
    const Circle *c = (const Circle *)self;
    return snprintf(buf, buflen, "{\"type\":\"circle\",\"r\":%.1f}", c->radius);
}

static const SerializableVtable CIRCLE_SERIAL_VTABLE = {
    .serialize = circle_serialize,
};

static DrawableObj drawable_circle_new(double cx, double cy, double r) {
    Circle *c = malloc(sizeof(Circle));
    assert(c != NULL);
    c->cx = cx;
    c->cy = cy;
    c->radius = r;
    return (DrawableObj){
        .data = c,
        .shape_vt = &CIRCLE_VTABLE,
        .serial_vt = &CIRCLE_SERIAL_VTABLE,
    };
}

// ── Enum dispatch: alternative to vtables ─────────────────────────
// For small, closed sets of types, an enum + switch is simpler
// and avoids indirect calls. Like Rust's enum + match.

typedef enum { SHAPE_CIRCLE, SHAPE_RECT } ShapeKind;

typedef struct {
    ShapeKind kind;
    union {
        Circle circle;
        Rectangle rect;
    };
} ShapeEnum;

static double shape_enum_area(const ShapeEnum *s) {
    switch (s->kind) {
        case SHAPE_CIRCLE:
            return M_PI * s->circle.radius * s->circle.radius;
        case SHAPE_RECT:
            return s->rect.width * s->rect.height;
    }
    return 0.0;
}

int main(void) {
    char buf[128];

    // ── Dynamic dispatch through vtable ───────────────────────────
    ShapeObj shapes[3];
    shapes[0] = circle_new(0, 0, 5.0);
    shapes[1] = rect_new(0, 0, 4.0, 6.0);
    shapes[2] = circle_new(1, 1, 3.0);

    // Polymorphic iteration — like iterating Vec<Box<dyn Shape>>
    double total_area = 0.0;
    for (int i = 0; i < 3; i++) {
        total_area += shape_area(&shapes[i]);

        shape_describe(&shapes[i], buf, sizeof(buf));
        // Verify each shape describes itself correctly
        assert(strstr(buf, shape_name(&shapes[i])) != NULL);
    }

    // Circle(r=5): pi*25 ≈ 78.54, Rect(4x6): 24, Circle(r=3): pi*9 ≈ 28.27
    assert(total_area > 130.0 && total_area < 132.0);

    // ── Static dispatch: direct calls ─────────────────────────────
    Circle circles[] = {{0, 0, 1.0}, {0, 0, 2.0}, {0, 0, 3.0}};
    double static_sum = sum_circle_areas(circles, 3);
    // pi*1 + pi*4 + pi*9 = 14*pi ≈ 43.98
    assert(static_sum > 43.9 && static_sum < 44.0);

    // ── Interface composition ─────────────────────────────────────
    DrawableObj dc = drawable_circle_new(0, 0, 7.5);

    // Call through shape vtable
    double area = dc.shape_vt->area(dc.data);
    assert(area > 176.0 && area < 177.0);  // pi*56.25

    // Call through serializable vtable
    dc.serial_vt->serialize(dc.data, buf, sizeof(buf));
    assert(strstr(buf, "\"type\":\"circle\"") != NULL);
    assert(strstr(buf, "7.5") != NULL);

    free(dc.data);

    // ── Enum dispatch ─────────────────────────────────────────────
    ShapeEnum se;
    se.kind = SHAPE_CIRCLE;
    se.circle = (Circle){0, 0, 10.0};
    assert(fabs(shape_enum_area(&se) - M_PI * 100.0) < 0.01);

    se.kind = SHAPE_RECT;
    se.rect = (Rectangle){0, 0, 3.0, 7.0};
    assert(fabs(shape_enum_area(&se) - 21.0) < 0.01);

    // ── Cleanup: free heap-allocated data ─────────────────────────
    for (int i = 0; i < 3; i++) {
        free(shapes[i].data);
    }

    printf("All trait and typeclass system examples passed.\n");
    return 0;
}
