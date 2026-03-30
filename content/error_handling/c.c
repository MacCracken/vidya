// Vidya — Error Handling in C
//
// C has no exceptions. Error handling uses return codes, errno, and
// explicit checks after every fallible operation. The caller must
// check — nothing forces it. goto is the standard pattern for cleanup
// on error in complex functions.

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Error codes: define your own enum ──────────────────────────────

typedef enum {
    ERR_OK = 0,
    ERR_NOT_FOUND,
    ERR_PARSE,
    ERR_INVALID,
    ERR_NOMEM,
} ErrorCode;

const char *error_string(ErrorCode err) {
    switch (err) {
        case ERR_OK:        return "success";
        case ERR_NOT_FOUND: return "not found";
        case ERR_PARSE:     return "parse error";
        case ERR_INVALID:   return "invalid input";
        case ERR_NOMEM:     return "out of memory";
        default:            return "unknown error";
    }
}

// ── Return code pattern ────────────────────────────────────────────
// Return error code, pass result through output parameter

ErrorCode parse_port(const char *config, int *out_port) {
    const char *p = strstr(config, "port=");
    if (p == NULL) {
        return ERR_NOT_FOUND;
    }
    p += 5; // skip "port="

    char *endptr;
    long val = strtol(p, &endptr, 10);
    if (endptr == p || (*endptr != '\0' && *endptr != '\n' && *endptr != ' ')) {
        return ERR_PARSE;
    }
    if (val < 0 || val > 65535) {
        return ERR_INVALID;
    }

    *out_port = (int)val;
    return ERR_OK;
}

// ── goto cleanup pattern ───────────────────────────────────────────
// The standard C idiom for cleanup on error in complex functions

typedef struct {
    char *host;
    int port;
} Config;

ErrorCode load_config(const char *text, Config *cfg) {
    cfg->host = NULL;

    // Allocate host
    cfg->host = malloc(64);
    if (cfg->host == NULL) {
        return ERR_NOMEM;
    }

    // Parse host
    const char *h = strstr(text, "host=");
    if (h == NULL) {
        goto cleanup;
    }
    h += 5;
    int i = 0;
    while (h[i] != '\0' && h[i] != '\n' && h[i] != ' ' && i < 63) {
        cfg->host[i] = h[i];
        i++;
    }
    cfg->host[i] = '\0';

    // Parse port
    ErrorCode err = parse_port(text, &cfg->port);
    if (err != ERR_OK) {
        goto cleanup;
    }

    return ERR_OK;

cleanup:
    free(cfg->host);
    cfg->host = NULL;
    return ERR_NOT_FOUND;
}

// ── errno: POSIX error reporting ───────────────────────────────────

void demonstrate_errno(void) {
    // fopen sets errno on failure
    FILE *f = fopen("/nonexistent/path/file.txt", "r");
    assert(f == NULL);
    assert(errno == ENOENT); // "No such file or directory"

    // strerror converts errno to message
    const char *msg = strerror(errno);
    assert(strstr(msg, "No such file") != NULL || strstr(msg, "not exist") != NULL
           || strlen(msg) > 0);

    // perror prints to stderr: "prefix: error message"
    // perror("fopen");  // prints: "fopen: No such file or directory"
}

// ── NULL checks for pointer operations ─────────────────────────────

char *safe_strdup(const char *s) {
    if (s == NULL) return NULL;
    size_t len = strlen(s) + 1;
    char *copy = malloc(len);
    if (copy == NULL) return NULL;
    memcpy(copy, s, len);
    return copy;
}

int main(void) {
    // ── Return code checking ───────────────────────────────────────
    int port;
    ErrorCode err;

    err = parse_port("host=localhost port=3000", &port);
    assert(err == ERR_OK);
    assert(port == 3000);

    // Missing port
    err = parse_port("host=localhost", &port);
    assert(err == ERR_NOT_FOUND);
    assert(strcmp(error_string(err), "not found") == 0);

    // Invalid port value
    err = parse_port("port=abc", &port);
    assert(err == ERR_PARSE);

    // ── goto cleanup ───────────────────────────────────────────────
    Config cfg;
    err = load_config("host=localhost port=8080", &cfg);
    assert(err == ERR_OK);
    assert(strcmp(cfg.host, "localhost") == 0);
    assert(cfg.port == 8080);
    free(cfg.host);

    // Missing fields
    err = load_config("nothing=here", &cfg);
    assert(err == ERR_NOT_FOUND);
    assert(cfg.host == NULL); // cleanup ran

    // ── errno ──────────────────────────────────────────────────────
    demonstrate_errno();

    // ── NULL-safe operations ───────────────────────────────────────
    char *copy = safe_strdup("hello");
    assert(copy != NULL);
    assert(strcmp(copy, "hello") == 0);
    free(copy);

    char *null_copy = safe_strdup(NULL);
    assert(null_copy == NULL);

    // ── Checking malloc ────────────────────────────────────────────
    // Always check malloc return value
    void *ptr = malloc(64);
    assert(ptr != NULL); // in real code, handle gracefully
    free(ptr);

    printf("All error handling examples passed.\n");
    return 0;
}
