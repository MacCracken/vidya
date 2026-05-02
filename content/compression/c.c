/* Vidya — Compression (LZ77-shaped) in C
 *
 * Two-byte token stream matching cyrius.cyr:
 *   {0, BYTE}      literal
 *   {OFFSET, LEN}  match: copy LEN bytes from out[pos - OFFSET..]
 * Greedy O(n^2) match-finder over a 255-byte window. Decoder enforces
 * an output-cap. Match copy is byte-by-byte so offset=1 replicates the
 * trailing byte (RLE) — `memcpy` would be wrong because src and dst
 * overlap.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define MIN_MATCH 3
#define MAX_MATCH 255
#define WIN_SIZE  255
#define BUF_CAP   512

static int match_len_at(const uint8_t *src, size_t src_len, size_t hist, size_t pos) {
    int n = 0;
    int max = (int)(src_len - pos);
    if (max > MAX_MATCH) max = MAX_MATCH;
    while (n < max && src[hist + n] == src[pos + n]) n++;
    return n;
}

/* Returns 1 if a match >= MIN_MATCH found; off and len populated. */
static int best_match(const uint8_t *src, size_t src_len, size_t pos, uint8_t *off, uint8_t *len) {
    size_t win_start = (pos > WIN_SIZE) ? pos - WIN_SIZE : 0;
    int best_off = 0;
    int best_len = 0;
    for (size_t i = win_start; i < pos; i++) {
        int n = match_len_at(src, src_len, i, pos);
        if (n > best_len) { best_len = n; best_off = (int)(pos - i); }
    }
    if (best_len >= MIN_MATCH) {
        *off = (uint8_t)best_off;
        *len = (uint8_t)best_len;
        return 1;
    }
    return 0;
}

static size_t encode(const uint8_t *src, size_t src_len, uint8_t *tok) {
    size_t tpos = 0;
    size_t pos = 0;
    while (pos < src_len) {
        uint8_t off, len;
        if (best_match(src, src_len, pos, &off, &len)) {
            tok[tpos++] = off;
            tok[tpos++] = len;
            pos += len;
        } else {
            tok[tpos++] = 0;
            tok[tpos++] = src[pos];
            pos += 1;
        }
    }
    return tpos;
}

/* Returns -1 on bomb-guard trigger, else output length. */
static int decode(const uint8_t *tok, size_t tok_len, size_t out_cap, uint8_t *out) {
    size_t pos = 0;
    for (size_t i = 0; i + 1 < tok_len; i += 2) {
        uint8_t b0 = tok[i], b1 = tok[i + 1];
        if (b0 == 0) {
            if (pos + 1 > out_cap) return -1;
            out[pos++] = b1;
        } else {
            if (pos + b1 > out_cap) return -1;
            for (int k = 0; k < b1; k++) {
                out[pos + k] = out[pos - b0 + k];
            }
            pos += b1;
        }
    }
    return (int)pos;
}

int main(void) {
    uint8_t tok[BUF_CAP];
    uint8_t out[BUF_CAP];

    /* 1. Round-trip with substring match */
    const char *s1 = "ABCABCABC";
    size_t n1 = strlen(s1);
    size_t t1 = encode((const uint8_t *)s1, n1, tok);
    assert(t1 > 0 && "encoded length > 0");
    int d1 = decode(tok, t1, BUF_CAP, out);
    assert(d1 == (int)n1 && memcmp(out, s1, n1) == 0 && "ABCABCABC roundtrip");

    /* 2. Overlapping (RLE) */
    const char *s2 = "AAAAAAAA";
    size_t n2 = strlen(s2);
    size_t t2 = encode((const uint8_t *)s2, n2, tok);
    int d2 = decode(tok, t2, BUF_CAP, out);
    assert(d2 == (int)n2 && memcmp(out, s2, n2) == 0 && "AAAAAAAA roundtrip");
    assert(t2 < n2 + 4 && "AAAAAAAA actually compresses");

    /* 3. Mostly literals */
    const char *s3 = "Hello, World!";
    size_t n3 = strlen(s3);
    size_t t3 = encode((const uint8_t *)s3, n3, tok);
    int d3 = decode(tok, t3, BUF_CAP, out);
    assert(d3 == (int)n3 && memcmp(out, s3, n3) == 0 && "Hello roundtrip");

    /* 4. Bomb guard */
    uint8_t bomb[2] = {1, 200};
    int dbomb = decode(bomb, 2, 10, out);
    assert(dbomb == -1 && "bomb guard rejects oversize");

    /* 5. Empty input */
    size_t t5 = encode((const uint8_t *)"", 0, tok);
    assert(t5 == 0 && "empty input → zero tokens");
    int d5 = decode(tok, 0, BUF_CAP, out);
    assert(d5 == 0 && "empty tokens → zero output");

    printf("compression: 11/11 ok\n");
    return 0;
}
