#define _GNU_SOURCE
// Vidya — Design Patterns in C
//
// C patterns: function pointers for strategy/observer, tagged unions
// for state machines, struct-with-vtable for polymorphism, and
// cleanup via goto or wrapper functions (C's manual RAII).

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Strategy: function pointers ───────────────────────────────────────
typedef double (*discount_fn)(double price);

static double no_discount(double p) { return p; }
static double ten_percent(double p) { return p * 0.9; }
static double flat_five(double p) { return p > 5 ? p - 5 : 0; }

static double apply_discount(double price, discount_fn strategy) {
    return strategy(price);
}

static void test_strategy(void) {
    assert(apply_discount(100, no_discount) == 100);
    assert(apply_discount(100, ten_percent) == 90);
    assert(apply_discount(100, flat_five) == 95);
    assert(apply_discount(3, flat_five) == 0);
}

// ── Observer: callback array ──────────────────────────────────────────
typedef void (*event_handler)(const char *event, void *ctx);

#define MAX_LISTENERS 8

typedef struct {
    event_handler handlers[MAX_LISTENERS];
    void *contexts[MAX_LISTENERS];
    int count;
} EventEmitter;

static void emitter_init(EventEmitter *e) { e->count = 0; }

static void emitter_on(EventEmitter *e, event_handler h, void *ctx) {
    assert(e->count < MAX_LISTENERS);
    e->handlers[e->count] = h;
    e->contexts[e->count] = ctx;
    e->count++;
}

static void emitter_emit(EventEmitter *e, const char *event) {
    for (int i = 0; i < e->count; i++) {
        e->handlers[i](event, e->contexts[i]);
    }
}

typedef struct {
    char entries[256];
    int len;
} Log;

// Advance an append cursor by snprintf's result. snprintf returns the
// length it WOULD have written, not what fit: `len += snprintf(...)`
// walks len past the buffer on truncation, the next `cap - len` size
// argument underflows to a huge size_t, and the next append overflows.
static int append_advance(int len, int written, size_t room) {
    if (written < 0 || room == 0) return len;
    return len + ((size_t)written < room ? written : (int)room - 1);
}

static void log_handler_a(const char *event, void *ctx) {
    Log *log = (Log *)ctx;
    size_t room = sizeof(log->entries) - (size_t)log->len;
    log->len = append_advance(log->len,
        snprintf(log->entries + log->len, room, "A:%s ", event), room);
}

static void log_handler_b(const char *event, void *ctx) {
    Log *log = (Log *)ctx;
    size_t room = sizeof(log->entries) - (size_t)log->len;
    log->len = append_advance(log->len,
        snprintf(log->entries + log->len, room, "B:%s ", event), room);
}

static void test_observer(void) {
    EventEmitter em;
    emitter_init(&em);
    Log log = { .entries = "", .len = 0 };

    emitter_on(&em, log_handler_a, &log);
    emitter_on(&em, log_handler_b, &log);
    emitter_emit(&em, "click");
    emitter_emit(&em, "hover");

    assert(strstr(log.entries, "A:click") != NULL);
    assert(strstr(log.entries, "B:hover") != NULL);

    // Many more events than fit: the log truncates instead of overflowing
    for (int i = 0; i < 100; i++) emitter_emit(&em, "scroll");
    assert(log.len == (int)sizeof(log.entries) - 1);
    assert(log.entries[sizeof(log.entries) - 1] == '\0');
}

// ── State machine: enum + transition table ────────────────────────────
typedef enum { DOOR_LOCKED, DOOR_CLOSED, DOOR_OPEN } DoorState;
typedef enum { ACT_UNLOCK, ACT_OPEN, ACT_CLOSE, ACT_LOCK, ACT_COUNT } DoorAction;

// -1 = invalid transition
static const int transitions[3][ACT_COUNT] = {
    /* LOCKED */ { DOOR_CLOSED, -1,         -1,          -1 },
    /* CLOSED */ { -1,          DOOR_OPEN,  -1,          DOOR_LOCKED },
    /* OPEN   */ { -1,          -1,         DOOR_CLOSED, -1 },
};

static int door_transition(DoorState state, DoorAction action) {
    // A -1 result cast back to DoorState must not index the table
    if ((int)state < 0 || state > DOOR_OPEN || (int)action < 0 || action >= ACT_COUNT)
        return -1;
    return transitions[state][action];
}

static void test_state_machine(void) {
    DoorState s = DOOR_LOCKED;
    s = (DoorState)door_transition(s, ACT_UNLOCK);
    assert(s == DOOR_CLOSED);
    s = (DoorState)door_transition(s, ACT_OPEN);
    assert(s == DOOR_OPEN);
    s = (DoorState)door_transition(s, ACT_CLOSE);
    s = (DoorState)door_transition(s, ACT_LOCK);
    assert(s == DOOR_LOCKED);

    assert(door_transition(DOOR_LOCKED, ACT_OPEN) == -1);
    assert(door_transition((DoorState)-1, ACT_OPEN) == -1);  // chained invalid state
}

// ── RAII via goto cleanup ─────────────────────────────────────────────
static int test_goto_cleanup_inner(char *log, int log_size) {
    int len = 0;
    char *buf1 = NULL, *buf2 = NULL;

    buf1 = malloc(64);
    if (!buf1) goto cleanup;
    len = append_advance(len, snprintf(log + len, (size_t)(log_size - len),
                                       "acquire:buf1 "), (size_t)(log_size - len));

    buf2 = malloc(64);
    if (!buf2) goto cleanup;
    len = append_advance(len, snprintf(log + len, (size_t)(log_size - len),
                                       "acquire:buf2 "), (size_t)(log_size - len));

    strcpy(buf1, "hello");
    strcpy(buf2, "world");

cleanup:
    if (buf2) {
        free(buf2);
        len = append_advance(len, snprintf(log + len, (size_t)(log_size - len),
                                           "release:buf2 "), (size_t)(log_size - len));
    }
    if (buf1) {
        free(buf1);
        len = append_advance(len, snprintf(log + len, (size_t)(log_size - len),
                                           "release:buf1 "), (size_t)(log_size - len));
    }
    return len;
}

static void test_goto_cleanup(void) {
    char log[256] = "";
    test_goto_cleanup_inner(log, (int)sizeof(log));
    assert(strstr(log, "acquire:buf1") != NULL);
    assert(strstr(log, "release:buf2") != NULL);
    assert(strstr(log, "release:buf1") != NULL);
}

// ── Dependency injection: vtable struct ───────────────────────────────
typedef struct {
    const char *(*log)(void *self, const char *msg);
} LoggerVtable;

typedef struct {
    LoggerVtable vtable;
    char last_entry[128];
} StdoutLogger;

static const char *stdout_log(void *self, const char *msg) {
    StdoutLogger *l = (StdoutLogger *)self;
    snprintf(l->last_entry, sizeof(l->last_entry), "[stdout] %s", msg);
    return l->last_entry;
}

typedef struct {
    LoggerVtable vtable;
    char entries[512];
    int len;
} TestLogger;

static const char *test_log(void *self, const char *msg) {
    TestLogger *l = (TestLogger *)self;
    const char *entry = l->entries + l->len;  // where THIS entry starts
    size_t room = sizeof(l->entries) - (size_t)l->len;
    l->len = append_advance(l->len,
        snprintf(l->entries + l->len, room, "[test] %s\n", msg), room);
    return entry;
}

typedef struct {
    void *logger;
    LoggerVtable *vtable;
} Service;

static const char *service_process(Service *svc, const char *item) {
    char buf[128];
    snprintf(buf, sizeof(buf), "processing %s", item);
    return svc->vtable->log(svc->logger, buf);
}

static void test_dependency_injection(void) {
    StdoutLogger sl = { .vtable = { .log = stdout_log }, .last_entry = "" };
    Service svc = { .logger = &sl, .vtable = &sl.vtable };
    const char *result = service_process(&svc, "order");
    assert(strcmp(result, "[stdout] processing order") == 0);

    TestLogger tl = { .vtable = { .log = test_log }, .entries = "", .len = 0 };
    svc.logger = &tl;
    svc.vtable = &tl.vtable;
    const char *entry = service_process(&svc, "order-1");
    assert(strstr(tl.entries, "[test] processing order-1") != NULL);
    assert(strcmp(entry, "[test] processing order-1\n") == 0);  // returns the entry
}

// ── Factory: function table ───────────────────────────────────────────
typedef struct { double area; const char *type; } Shape;

static Shape make_circle(const double *p) {
    return (Shape){ .area = M_PI * p[0] * p[0], .type = "circle" };
}
static Shape make_rectangle(const double *p) {
    return (Shape){ .area = p[0] * p[1], .type = "rectangle" };
}
static Shape make_triangle(const double *p) {
    return (Shape){ .area = 0.5 * p[0] * p[1], .type = "triangle" };
}

static int shape_factory(const char *name, const double *params, Shape *out) {
    struct { const char *name; Shape (*make)(const double *); } factories[] = {
        { "circle", make_circle },
        { "rectangle", make_rectangle },
        { "triangle", make_triangle },
    };
    for (size_t i = 0; i < sizeof(factories)/sizeof(factories[0]); i++) {
        if (strcmp(factories[i].name, name) == 0) {
            *out = factories[i].make(params);
            return 0;
        }
    }
    return -1;
}

static void test_factory(void) {
    Shape s;
    // shape_factory fills s, so it runs outside assert(): under -DNDEBUG
    // assert's expression is not evaluated and s would stay uninitialised.
    int rc = shape_factory("circle", (double[]){5}, &s);
    assert(rc == 0);
    assert(fabs(s.area - 78.539) < 0.001);

    rc = shape_factory("rectangle", (double[]){3, 4}, &s);
    assert(rc == 0);
    assert(s.area == 12);

    rc = shape_factory("hexagon", NULL, &s);
    assert(rc == -1);
}

int main(void) {
    test_strategy();
    test_observer();
    test_state_machine();
    test_goto_cleanup();
    test_dependency_injection();
    test_factory();

    printf("All design patterns examples passed.\n");
    return 0;
}
