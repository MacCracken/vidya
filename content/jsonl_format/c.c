/* Vidya — JSON Lines (JSONL) in C
 *
 * In-memory JSONL primitives mirroring cyrius.cyr.
 */

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define BUF_CAP 1024
#define IDX_CAP 64

static uint8_t jsonl_buf[BUF_CAP];
static size_t jsonl_len = 0;
static size_t line_offsets[IDX_CAP];
static size_t line_lengths[IDX_CAP];
static size_t line_count = 0;
static uint8_t esc_buf[256];
static uint8_t unesc_buf[256];

static void append_record(const uint8_t *rec, size_t rec_len) {
    memcpy(jsonl_buf + jsonl_len, rec, rec_len);
    jsonl_len += rec_len;
    jsonl_buf[jsonl_len++] = '\n';
}

static void build_index(void) {
    line_count = 0;
    size_t start = 0;
    for (size_t i = 0; i < jsonl_len; i++) {
        if (jsonl_buf[i] == '\n') {
            line_offsets[line_count] = start;
            line_lengths[line_count] = i - start;
            line_count++;
            start = i + 1;
        }
    }
    if (start < jsonl_len) {
        line_offsets[line_count] = start;
        line_lengths[line_count] = jsonl_len - start;
        line_count++;
    }
}

static int json_escape(uint8_t *dst, size_t dst_cap, const uint8_t *src, size_t src_len) {
    if (src_len * 2 > dst_cap) return -1;
    size_t w = 0;
    for (size_t i = 0; i < src_len; i++) {
        uint8_t c = src[i];
        if (c == '"')      { dst[w++] = '\\'; dst[w++] = '"'; }
        else if (c == '\\'){ dst[w++] = '\\'; dst[w++] = '\\'; }
        else if (c == '\n'){ dst[w++] = '\\'; dst[w++] = 'n'; }
        else if (c == '\t'){ dst[w++] = '\\'; dst[w++] = 't'; }
        else if (c == '\r'){ dst[w++] = '\\'; dst[w++] = 'r'; }
        else               { dst[w++] = c; }
    }
    return (int)w;
}

static size_t json_unescape(uint8_t *dst, const uint8_t *src, size_t src_len) {
    size_t w = 0;
    for (size_t i = 0; i < src_len; ) {
        if (src[i] == '\\' && i + 1 < src_len) {
            uint8_t n = src[i + 1];
            if (n == '"')      { dst[w++] = '"';  i += 2; }
            else if (n == '\\'){ dst[w++] = '\\'; i += 2; }
            else if (n == 'n') { dst[w++] = '\n'; i += 2; }
            else if (n == 't') { dst[w++] = '\t'; i += 2; }
            else if (n == 'r') { dst[w++] = '\r'; i += 2; }
            else               { dst[w++] = src[i]; i++; }
        } else {
            dst[w++] = src[i++];
        }
    }
    return w;
}

int main(void) {
    /* Test 1: build, index, extract */
    append_record((const uint8_t *)"{\"id\":1}", 8);
    append_record((const uint8_t *)"{\"id\":2}", 8);
    append_record((const uint8_t *)"{\"id\":3}", 8);
    build_index();
    assert(line_count == 3 && "3 records indexed");
    assert(line_lengths[2] == 8 && "third record length 8");
    assert(memcmp(jsonl_buf + line_offsets[2], "{\"id\":3}", 8) == 0 && "third record bytes");

    /* Test 2: no trailing newline */
    if (jsonl_len > 0 && jsonl_buf[jsonl_len - 1] == '\n') jsonl_len--;
    build_index();
    assert(line_count == 3 && "3 records indexed without trailing newline");

    /* Test 3: escape */
    uint8_t s3[12] = { 's','a','y',' ','"','h','i','"', '\t','\n','\r','\\' };
    int en = json_escape(esc_buf, sizeof esc_buf, s3, 12);
    assert(en == 18 && "escape produces 18 bytes");

    /* Test 4: bounds check */
    uint8_t s4[4] = { '"','"','"','"' };
    assert(json_escape(esc_buf, 4, s4, 4) == -1 && "escape refuses tight cap");

    /* Test 5: roundtrip */
    size_t un = json_unescape(unesc_buf, esc_buf, (size_t)en);
    assert(un == 12 && "unescape recovers 12");
    assert(memcmp(unesc_buf, s3, 12) == 0 && "round-trip bytes match");

    printf("jsonl_format: 8/8 ok\n");
    return 0;
}
