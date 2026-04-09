// Vidya — Tracing & Structured Logging in C
//
// C has no built-in logging framework. This implements level-filtered
// logging with fprintf, nanosecond timestamps via clock_gettime,
// span enter/exit with elapsed timing, packed error codes using
// bitwise operations, and a lock-free ring buffer for binary trace events.

#define _POSIX_C_SOURCE 199309L

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

// ── Log levels ────────────────────────────────────────────────────────

typedef enum {
    LOG_ERROR = 0,
    LOG_WARN  = 1,
    LOG_INFO  = 2,
    LOG_DEBUG = 3,
    LOG_TRACE = 4,
} LogLevel;

static const char *level_name(LogLevel level) {
    switch (level) {
        case LOG_ERROR: return "ERROR";
        case LOG_WARN:  return "WARN";
        case LOG_INFO:  return "INFO";
        case LOG_DEBUG: return "DEBUG";
        case LOG_TRACE: return "TRACE";
    }
    return "?";
}

// ── Logger with level filtering ───────────────────────────────────────

typedef struct {
    LogLevel max_level;
    int count;
    LogLevel last_level;   // level of most recent recorded entry
} Logger;

static void logger_init(Logger *log, LogLevel max_level) {
    log->max_level = max_level;
    log->count = 0;
    log->last_level = LOG_ERROR;
}

static void logger_log(Logger *log, LogLevel level, const char *target,
                       const char *message) {
    if (level > log->max_level) return;

    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    uint64_t ns = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;

    fprintf(stdout, "[%s +%luNs] %s: %s\n", level_name(level), ns, target, message);
    log->last_level = level;
    log->count++;
}

// ── Span: enter/exit with elapsed ns ──────────────────────────────────

typedef struct {
    const char *name;
    struct timespec start;
} Span;

static void span_enter(Span *span, const char *name) {
    span->name = name;
    clock_gettime(CLOCK_MONOTONIC, &span->start);
    fprintf(stdout, "[SPAN] --> %s\n", name);
}

static uint64_t span_exit(const Span *span) {
    struct timespec end;
    clock_gettime(CLOCK_MONOTONIC, &end);
    uint64_t start_ns = (uint64_t)span->start.tv_sec * 1000000000ULL
                      + (uint64_t)span->start.tv_nsec;
    uint64_t end_ns   = (uint64_t)end.tv_sec * 1000000000ULL
                      + (uint64_t)end.tv_nsec;
    uint64_t elapsed  = end_ns - start_ns;
    fprintf(stdout, "[SPAN] <-- %s (%luns)\n", span->name, elapsed);
    return elapsed;
}

// ── Packed error codes ────────────────────────────────────────────────
// Layout: [63..32] = category, [31..0] = code

#define CATEGORY_SHIFT 32
#define CODE_MASK      0xFFFFFFFFULL

#define CAT_IO    1
#define CAT_PARSE 2
#define CAT_AUTH  3

static uint64_t pack_error(uint32_t category, uint32_t code) {
    return ((uint64_t)category << CATEGORY_SHIFT) | (uint64_t)code;
}

static uint32_t unpack_category(uint64_t packed) {
    return (uint32_t)(packed >> CATEGORY_SHIFT);
}

static uint32_t unpack_code(uint64_t packed) {
    return (uint32_t)(packed & CODE_MASK);
}

// ── Ring buffer for binary trace events ───────────────────────────────
// Fixed-size, overwrites oldest events when full. No allocation needed.

#define RING_CAP 8

typedef struct {
    uint64_t timestamp_ns;
    uint32_t event_id;
    uint32_t payload;
} TraceEvent;

typedef struct {
    TraceEvent buf[RING_CAP];
    int head;   // next write position
    int count;  // number of valid entries (max RING_CAP)
} RingBuffer;

static void ring_init(RingBuffer *rb) {
    memset(rb, 0, sizeof(*rb));
}

static void ring_push(RingBuffer *rb, uint32_t event_id, uint32_t payload) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);

    TraceEvent *ev = &rb->buf[rb->head];
    ev->timestamp_ns = (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
    ev->event_id = event_id;
    ev->payload = payload;

    rb->head = (rb->head + 1) % RING_CAP;
    if (rb->count < RING_CAP) rb->count++;
}

// Read the i-th oldest valid event (0 = oldest)
static const TraceEvent *ring_read(const RingBuffer *rb, int i) {
    if (i < 0 || i >= rb->count) return NULL;
    int start = (rb->count < RING_CAP) ? 0 : rb->head;
    int idx = (start + i) % RING_CAP;
    return &rb->buf[idx];
}

int main(void) {
    // ── Level filtering ───────────────────────────────────────────────
    Logger log;
    logger_init(&log, LOG_INFO);

    logger_log(&log, LOG_ERROR, "db", "connection refused");
    logger_log(&log, LOG_WARN,  "db", "retry attempt 2");
    logger_log(&log, LOG_INFO,  "db", "connected");
    logger_log(&log, LOG_DEBUG, "db", "query plan cached");   // filtered
    logger_log(&log, LOG_TRACE, "db", "raw packet dump");     // filtered

    assert(log.count == 3);

    // Error-only logger
    Logger strict;
    logger_init(&strict, LOG_ERROR);
    logger_log(&strict, LOG_ERROR, "app", "crash");
    logger_log(&strict, LOG_WARN,  "app", "degraded");  // filtered
    assert(strict.count == 1);

    // Trace-level logger captures everything
    Logger verbose;
    logger_init(&verbose, LOG_TRACE);
    logger_log(&verbose, LOG_ERROR, "app", "fatal");
    logger_log(&verbose, LOG_TRACE, "app", "heartbeat");
    assert(verbose.count == 2);

    // ── Level ordering ────────────────────────────────────────────────
    assert(LOG_ERROR < LOG_WARN);
    assert(LOG_WARN < LOG_INFO);
    assert(LOG_INFO < LOG_DEBUG);
    assert(LOG_DEBUG < LOG_TRACE);

    // ── Span timing ──────────────────────────────────────────────────
    Span compute;
    span_enter(&compute, "compute");
    volatile uint64_t sum = 0;
    for (int i = 0; i < 1000; i++) sum += (uint64_t)i;
    assert(sum == 499500);
    uint64_t compute_ns = span_exit(&compute);
    fprintf(stdout, "compute span: %luns\n", compute_ns);

    // Nested spans: outer >= inner
    Span outer, inner;
    span_enter(&outer, "request");
    span_enter(&inner, "parse_body");
    uint64_t inner_ns = span_exit(&inner);
    uint64_t outer_ns = span_exit(&outer);
    assert(outer_ns >= inner_ns);

    // ── Packed error codes ────────────────────────────────────────────
    uint64_t err = pack_error(CAT_IO, 42);
    assert(unpack_category(err) == CAT_IO);
    assert(unpack_code(err) == 42);

    uint64_t err2 = pack_error(CAT_PARSE, 7);
    assert(unpack_category(err2) == CAT_PARSE);
    assert(unpack_code(err2) == 7);

    uint64_t err3 = pack_error(CAT_AUTH, 0xDEAD);
    assert(unpack_category(err3) == CAT_AUTH);
    assert(unpack_code(err3) == 0xDEAD);

    // Different categories
    assert(pack_error(CAT_IO, 1) != pack_error(CAT_PARSE, 1));

    // Deterministic
    assert(pack_error(CAT_IO, 99) == pack_error(CAT_IO, 99));

    // Max values
    uint64_t max_err = pack_error(0xFFFFFFFF, 0xFFFFFFFF);
    assert(unpack_category(max_err) == 0xFFFFFFFF);
    assert(unpack_code(max_err) == 0xFFFFFFFF);

    // ── Ring buffer ───────────────────────────────────────────────────
    RingBuffer rb;
    ring_init(&rb);

    // Push fewer than capacity
    ring_push(&rb, 1, 100);
    ring_push(&rb, 2, 200);
    ring_push(&rb, 3, 300);
    assert(rb.count == 3);

    const TraceEvent *ev = ring_read(&rb, 0);
    assert(ev != NULL);
    assert(ev->event_id == 1);
    assert(ev->payload == 100);

    ev = ring_read(&rb, 2);
    assert(ev != NULL);
    assert(ev->event_id == 3);

    // Out of bounds
    assert(ring_read(&rb, 3) == NULL);
    assert(ring_read(&rb, -1) == NULL);

    // Fill and overflow — oldest events are overwritten
    ring_init(&rb);
    for (int i = 0; i < RING_CAP + 3; i++) {
        ring_push(&rb, (uint32_t)(i + 10), (uint32_t)(i * 10));
    }
    assert(rb.count == RING_CAP);

    // Oldest surviving event should be event_id = 13 (index 3 of 0..10)
    ev = ring_read(&rb, 0);
    assert(ev != NULL);
    assert(ev->event_id == 13);

    // Newest event
    ev = ring_read(&rb, RING_CAP - 1);
    assert(ev != NULL);
    assert(ev->event_id == (uint32_t)(RING_CAP + 3 - 1 + 10));

    printf("All tracing examples passed.\n");
    return 0;
}
