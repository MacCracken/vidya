// Vidya — Strings in C
//
// C has no built-in string type. Strings are null-terminated char arrays.
// You manage memory, track lengths, and guard against buffer overflows
// yourself. <string.h> provides the standard operations.

#define _GNU_SOURCE
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

int main(void) {
    // ── Creation ────────────────────────────────────────────────────
    // String literals are read-only, stored in static memory
    const char *literal = "hello";
    assert(strlen(literal) == 5);

    // Stack-allocated mutable string
    char buf[64] = "hello";
    assert(strcmp(buf, "hello") == 0);

    // snprintf: safe formatted string creation
    char formatted[64];
    snprintf(formatted, sizeof(formatted), "%s world", "hello");
    assert(strcmp(formatted, "hello world") == 0);

    // ── Null terminator ────────────────────────────────────────────
    // Every C string ends with '\0'. strlen doesn't count it.
    char manual[] = {'h', 'e', 'l', 'l', 'o', '\0'};
    assert(strlen(manual) == 5);
    assert(sizeof(manual) == 6); // includes null terminator

    // ── String comparison ──────────────────────────────────────────
    assert(strcmp("hello", "hello") == 0);       // equal
    assert(strcmp("abc", "def") < 0);            // less than
    assert(strncmp("hello", "help", 3) == 0);   // first 3 chars equal

    // Case-insensitive (POSIX, not standard C)
    assert(strcasecmp("Hello", "hello") == 0);

    // ── Copying: strncpy and snprintf ──────────────────────────────
    char dest[32];

    // GOOD: snprintf always null-terminates and respects buffer size
    snprintf(dest, sizeof(dest), "%s", "hello world");
    assert(strcmp(dest, "hello world") == 0);

    // BAD: strcpy doesn't check bounds
    // strcpy(dest, very_long_string); // ← buffer overflow!

    // strncpy: copies at most n bytes, but may NOT null-terminate!
    char safe[8];
    strncpy(safe, "hello", sizeof(safe) - 1);
    safe[sizeof(safe) - 1] = '\0'; // always null-terminate manually
    assert(strcmp(safe, "hello") == 0);

    // ── Concatenation ──────────────────────────────────────────────
    char result[64] = "";
    snprintf(result, sizeof(result), "%s %s", "hello", "world");
    assert(strcmp(result, "hello world") == 0);

    // strncat: append with length limit
    char cat_buf[32] = "hello";
    strncat(cat_buf, " world", sizeof(cat_buf) - strlen(cat_buf) - 1);
    assert(strcmp(cat_buf, "hello world") == 0);

    // ── Searching ──────────────────────────────────────────────────
    const char *text = "hello world";
    const char *found = strstr(text, "world");
    assert(found != NULL);
    assert(found == text + 6);

    // Find single character
    const char *ch = strchr(text, 'w');
    assert(ch != NULL);
    assert(*ch == 'w');

    // ── String to number conversion ────────────────────────────────
    int num = atoi("42");
    assert(num == 42);

    // strtol is safer — detects errors
    char *endptr;
    long val = strtol("42abc", &endptr, 10);
    assert(val == 42);
    assert(*endptr == 'a'); // stopped at non-digit

    // ── Dynamic string allocation ──────────────────────────────────
    // Heap-allocated string for unknown sizes
    const char *src = "hello dynamic";
    char *heap_str = malloc(strlen(src) + 1);
    assert(heap_str != NULL);
    strcpy(heap_str, src);
    assert(strcmp(heap_str, "hello dynamic") == 0);
    free(heap_str);

    // ── String builder pattern ─────────────────────────────────────
    // Build a string incrementally with snprintf offset tracking
    char builder[128];
    int offset = 0;
    for (int i = 0; i < 5; i++) {
        offset += snprintf(builder + offset, sizeof(builder) - offset,
                          "%d ", i);
    }
    // Trim trailing space
    if (offset > 0) builder[offset - 1] = '\0';
    assert(strcmp(builder, "0 1 2 3 4") == 0);

    // ── Character operations ───────────────────────────────────────
    assert(toupper('a') == 'A');
    assert(tolower('A') == 'a');
    assert(isdigit('5'));
    assert(isalpha('a'));
    assert(isspace(' '));

    // ── Tokenizing ─────────────────────────────────────────────────
    char csv[] = "alice,bob,charlie";
    int token_count = 0;
    char *token = strtok(csv, ",");
    while (token != NULL) {
        token_count++;
        token = strtok(NULL, ",");
    }
    assert(token_count == 3);
    // WARNING: strtok modifies the input string and uses static state

    printf("All string examples passed.\n");
    return 0;
}
