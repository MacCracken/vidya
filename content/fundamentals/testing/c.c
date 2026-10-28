// Vidya — Testing in C
//
// C has no built-in test framework. Testing uses assert(), custom macros,
// and conventions. The standard pattern: write test functions, call them
// from main(), use assert() or custom CHECK macros for assertions.

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Minimal test framework ─────────────────────────────────────────

static int tests_run = 0;
static int tests_passed = 0;

#define CHECK(cond, msg) do { \
    tests_run++; \
    if (cond) { tests_passed++; } \
    else { fprintf(stderr, "  FAIL [%s:%d]: %s\n", __FILE__, __LINE__, msg); } \
} while(0)

#define CHECK_EQ_INT(got, expected, msg) do { \
    int _got = (got), _exp = (expected); \
    tests_run++; \
    if (_got == _exp) { tests_passed++; } \
    else { fprintf(stderr, "  FAIL [%s:%d]: %s: got %d, expected %d\n", \
           __FILE__, __LINE__, msg, _got, _exp); } \
} while(0)

#define CHECK_EQ_STR(got, expected, msg) do { \
    const char *_got = (got), *_exp = (expected); \
    tests_run++; \
    if (strcmp(_got, _exp) == 0) { tests_passed++; } \
    else { fprintf(stderr, "  FAIL [%s:%d]: %s: got '%s', expected '%s'\n", \
           __FILE__, __LINE__, msg, _got, _exp); } \
} while(0)

#define CHECK_NEAR(got, expected, tol, msg) do { \
    double _got = (got), _exp = (expected); \
    tests_run++; \
    if (fabs(_got - _exp) < (tol)) { tests_passed++; } \
    else { fprintf(stderr, "  FAIL [%s:%d]: %s: got %f, expected %f\n", \
           __FILE__, __LINE__, msg, _got, _exp); } \
} while(0)

// ── Code under test ────────────────────────────────────────────────

typedef enum { PARSE_OK, PARSE_NO_EQ, PARSE_EMPTY_KEY } ParseResult;

ParseResult parse_kv(const char *line, char *key, size_t key_sz,
                     char *value, size_t val_sz) {
    const char *eq = strchr(line, '=');
    if (eq == NULL) return PARSE_NO_EQ;

    size_t klen = eq - line;
    // Trim leading spaces
    while (klen > 0 && line[0] == ' ') { line++; klen--; }
    // Trim trailing spaces from key
    while (klen > 0 && line[klen-1] == ' ') klen--;

    if (klen == 0) return PARSE_EMPTY_KEY;

    size_t copy_len = klen < key_sz - 1 ? klen : key_sz - 1;
    memcpy(key, line, copy_len);
    key[copy_len] = '\0';

    // Value: everything after '='
    const char *v = eq + 1;
    while (*v == ' ') v++; // trim leading spaces
    size_t vlen = strlen(v);
    while (vlen > 0 && v[vlen-1] == ' ') vlen--; // trim trailing
    copy_len = vlen < val_sz - 1 ? vlen : val_sz - 1;
    memcpy(value, v, copy_len);
    value[copy_len] = '\0';

    return PARSE_OK;
}

int clamp(int value, int min, int max) {
    assert(min <= max);
    if (value < min) return min;
    if (value > max) return max;
    return value;
}

typedef struct {
    int count;
    int max;
} Counter;

Counter counter_new(int max) {
    return (Counter){.count = 0, .max = max};
}

int counter_increment(Counter *c) {
    if (c->count < c->max) {
        c->count++;
        return 1;
    }
    return 0;
}

// ── Test functions ─────────────────────────────────────────────────

void test_parse_kv_valid(void) {
    char key[64], value[64];
    ParseResult r = parse_kv("host=localhost", key, sizeof(key), value, sizeof(value));
    CHECK_EQ_INT(r, PARSE_OK, "valid parse result");
    CHECK_EQ_STR(key, "host", "valid parse key");
    CHECK_EQ_STR(value, "localhost", "valid parse value");
}

void test_parse_kv_trimmed(void) {
    char key[64], value[64];
    ParseResult r = parse_kv("  port = 3000  ", key, sizeof(key), value, sizeof(value));
    CHECK_EQ_INT(r, PARSE_OK, "trimmed parse result");
    CHECK_EQ_STR(key, "port", "trimmed key");
    CHECK_EQ_STR(value, "3000", "trimmed value");
}

void test_parse_kv_empty_value(void) {
    char key[64], value[64];
    ParseResult r = parse_kv("key=", key, sizeof(key), value, sizeof(value));
    CHECK_EQ_INT(r, PARSE_OK, "empty value parse");
    CHECK_EQ_STR(key, "key", "empty value key");
    CHECK_EQ_STR(value, "", "empty value");
}

void test_parse_kv_errors(void) {
    char key[64], value[64];
    CHECK_EQ_INT(parse_kv("no_equals", key, 64, value, 64), PARSE_NO_EQ, "no equals");
    CHECK_EQ_INT(parse_kv("=value", key, 64, value, 64), PARSE_EMPTY_KEY, "empty key");
}

void test_clamp_cases(void) {
    // Table-driven tests: array of test cases
    struct { int value, min, max, expected; const char *name; } cases[] = {
        {5,   0, 10, 5,  "in range"},
        {-1,  0, 10, 0,  "below min"},
        {100, 0, 10, 10, "above max"},
        {0,   0, 10, 0,  "at min"},
        {10,  0, 10, 10, "at max"},
        {5,   5, 5,  5,  "min equals max"},
    };
    size_t ncases = sizeof(cases) / sizeof(cases[0]);

    for (size_t i = 0; i < ncases; i++) {
        int got = clamp(cases[i].value, cases[i].min, cases[i].max);
        CHECK_EQ_INT(got, cases[i].expected, cases[i].name);
    }
}

void test_counter(void) {
    Counter c = counter_new(3);
    CHECK_EQ_INT(c.count, 0, "counter initial");
    CHECK(counter_increment(&c), "inc 1");
    CHECK(counter_increment(&c), "inc 2");
    CHECK(counter_increment(&c), "inc 3");
    CHECK(!counter_increment(&c), "inc at max");
    CHECK_EQ_INT(c.count, 3, "counter final");
}

void test_counter_zero_max(void) {
    Counter c = counter_new(0);
    CHECK(!counter_increment(&c), "zero max inc");
    CHECK_EQ_INT(c.count, 0, "zero max value");
}

// ── Main: run all tests ────────────────────────────────────────────

int main(void) {
    test_parse_kv_valid();
    test_parse_kv_trimmed();
    test_parse_kv_empty_value();
    test_parse_kv_errors();
    test_clamp_cases();
    test_counter();
    test_counter_zero_max();

    if (tests_passed == tests_run) {
        printf("All testing examples passed.\n");
        return 0;
    } else {
        fprintf(stderr, "FAILED: %d/%d passed\n", tests_passed, tests_run);
        return 1;
    }
}
