// Vidya — Module Systems in C
//
// C has no module system. Code organization relies on:
//   1. Header files (.h) — declarations (the "public API")
//   2. Translation units (.c) — definitions (the "implementation")
//   3. static — file-scope visibility (private to translation unit)
//   4. extern — cross-file symbol access (public)
//   5. Include guards — prevent double-inclusion of headers
//   6. Separate compilation — each .c compiles independently
//
// Compared to Rust:
//   header file    ≈ pub items in a mod
//   static         ≈ pub(crate) or private
//   extern         ≈ pub
//   #include       ≈ use (but textual, not semantic)
//   translation unit ≈ crate (compilation unit)
//   linking        ≈ extern crate (resolved at link time)
//
// This file simulates multi-file organization in a single file,
// since vidya examples must be self-contained.

#include <assert.h>
#include <stdio.h>
#include <string.h>

// ══════════════════════════════════════════════════════════════════
// Simulated header: "config.h"
// ══════════════════════════════════════════════════════════════════
// In a real project, this would be config.h with include guards:
//
//   #ifndef CONFIG_H
//   #define CONFIG_H
//   typedef struct { ... } Config;
//   Config *config_new(const char *host, int port);
//   void config_free(Config *cfg);
//   const char *config_host(const Config *cfg);
//   int config_port(const Config *cfg);
//   #endif

// Include guard pattern:
//   #ifndef prevents processing the same header twice.
//   Without it, typedef/struct definitions would conflict.
//   #pragma once is a non-standard but widely-supported alternative.

typedef struct {
    char host[64];
    int port;
    int debug;
} Config;

// Public API — these would be in the header
Config *config_new(const char *host, int port);
void config_free(Config *cfg);
const char *config_host(const Config *cfg);
int config_port(const Config *cfg);
void config_set_debug(Config *cfg, int debug);

// ══════════════════════════════════════════════════════════════════
// Simulated implementation: "config.c"
// ══════════════════════════════════════════════════════════════════
// In a real project, this would be config.c which #includes config.h.

#include <stdlib.h>

// static functions are PRIVATE to this translation unit.
// They cannot be called from other .c files.
// This is C's only visibility control — like Rust's default private.

static int validate_port(int port) {
    return port > 0 && port <= 65535;
}

static void init_defaults(Config *cfg) {
    cfg->debug = 0;
}

// Non-static functions are PUBLIC (extern by default).
// They are visible to the linker and callable from any .c file.

Config *config_new(const char *host, int port) {
    if (!validate_port(port)) return NULL;

    Config *cfg = malloc(sizeof(Config));
    if (cfg == NULL) return NULL;

    init_defaults(cfg);
    snprintf(cfg->host, sizeof(cfg->host), "%s", host);
    cfg->port = port;
    return cfg;
}

void config_free(Config *cfg) {
    free(cfg);
}

const char *config_host(const Config *cfg) {
    return cfg->host;
}

int config_port(const Config *cfg) {
    return cfg->port;
}

void config_set_debug(Config *cfg, int debug) {
    cfg->debug = debug;
}

// ══════════════════════════════════════════════════════════════════
// Simulated header: "logger.h"
// ══════════════════════════════════════════════════════════════════

typedef enum {
    LOG_DEBUG,
    LOG_INFO,
    LOG_WARN,
    LOG_ERROR,
} LogLevel;

// Opaque type pattern: declare struct in header, define in .c.
// Users can only interact through the API — they can't access fields.
// This is like Rust's pub struct with private fields.
//
// In real code:
//   // logger.h
//   typedef struct Logger Logger;  // opaque — no field access
//   Logger *logger_new(LogLevel min_level);
//
//   // logger.c
//   struct Logger { LogLevel min_level; int count; };

typedef struct {
    LogLevel min_level;
    int message_count;
} Logger;

Logger *logger_new(LogLevel min_level);
void logger_free(Logger *log);
void logger_log(Logger *log, LogLevel level, const char *msg);
int logger_count(const Logger *log);

// ══════════════════════════════════════════════════════════════════
// Simulated implementation: "logger.c"
// ══════════════════════════════════════════════════════════════════

static const char *level_name(LogLevel level) {
    switch (level) {
        case LOG_DEBUG: return "DEBUG";
        case LOG_INFO:  return "INFO";
        case LOG_WARN:  return "WARN";
        case LOG_ERROR: return "ERROR";
        default:        return "?";
    }
}

Logger *logger_new(LogLevel min_level) {
    Logger *log = malloc(sizeof(Logger));
    if (log == NULL) return NULL;
    log->min_level = min_level;
    log->message_count = 0;
    return log;
}

void logger_free(Logger *log) {
    free(log);
}

void logger_log(Logger *log, LogLevel level, const char *msg) {
    if (level >= log->min_level) {
        log->message_count++;
        // In real code: printf("[%s] %s\n", level_name(level), msg);
        (void)msg;
        (void)level_name(level);
    }
}

int logger_count(const Logger *log) {
    return log->message_count;
}

// ══════════════════════════════════════════════════════════════════
// static vs extern linkage
// ══════════════════════════════════════════════════════════════════
//
// static int x;        — file-scoped (internal linkage)
// int y;               — program-scoped (external linkage)
// extern int z;        — declaration only (defined elsewhere)
//
// static limits visibility to the current translation unit.
// This is the ONLY tool C provides for encapsulation.

// File-scoped global: only visible in this translation unit
static int module_initialized = 0;

// External global: visible to other translation units (if declared)
int module_version = 1;

static void ensure_initialized(void) {
    if (!module_initialized) {
        module_initialized = 1;
    }
}

// ══════════════════════════════════════════════════════════════════
// Namespace simulation with prefixes
// ══════════════════════════════════════════════════════════════════
// C has no namespaces. The convention is to prefix all public
// symbols with a module name:
//   config_new, config_free     — config module
//   logger_new, logger_log      — logger module
//   str_dup, str_concat         — string module
//
// This is why C library functions have short, cryptic names:
//   strncmp, memcpy, fprintf — manually namespaced

static char *str_dup(const char *s) {
    size_t len = strlen(s) + 1;
    char *copy = malloc(len);
    if (copy) memcpy(copy, s, len);
    return copy;
}

static int str_starts_with(const char *s, const char *prefix) {
    return strncmp(s, prefix, strlen(prefix)) == 0;
}

// ══════════════════════════════════════════════════════════════════
// Forward declarations
// ══════════════════════════════════════════════════════════════════
// Headers contain declarations (function signatures, type names).
// The compiler only needs to know the signature to type-check a call.
// The linker resolves the actual function address later.
//
// This enables separate compilation: each .c file compiles
// independently, seeing only declarations from headers.

int main(void) {
    ensure_initialized();
    assert(module_initialized == 1);
    assert(module_version == 1);

    // ── Config module API ─────────────────────────────────────────
    Config *cfg = config_new("localhost", 8080);
    assert(cfg != NULL);
    assert(strcmp(config_host(cfg), "localhost") == 0);
    assert(config_port(cfg) == 8080);

    config_set_debug(cfg, 1);
    assert(cfg->debug == 1);

    // Invalid port — constructor returns NULL
    Config *bad = config_new("host", -1);
    assert(bad == NULL);

    config_free(cfg);

    // ── Logger module API ─────────────────────────────────────────
    Logger *log = logger_new(LOG_WARN);
    assert(log != NULL);

    logger_log(log, LOG_DEBUG, "ignored");  // below min level
    logger_log(log, LOG_INFO, "ignored");   // below min level
    logger_log(log, LOG_WARN, "warning");   // logged
    logger_log(log, LOG_ERROR, "error");    // logged

    assert(logger_count(log) == 2);

    logger_free(log);

    // ── Namespace prefix convention ───────────────────────────────
    char *s = str_dup("hello module");
    assert(strcmp(s, "hello module") == 0);
    assert(str_starts_with(s, "hello"));
    assert(!str_starts_with(s, "world"));
    free(s);

    // ── Static linkage verification ───────────────────────────────
    // validate_port is static — cannot be called from another .c file.
    // We can call it here because we're in the same translation unit.
    assert(validate_port(80) == 1);
    assert(validate_port(0) == 0);
    assert(validate_port(70000) == 0);

    printf("All module system examples passed.\n");
    return 0;
}
