/* Vidya — Serialization in C
 *
 * Varint (LEB128) + length-prefix framing + stream parser + DoS guards.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define MAX_VARINT_BYTES 10
#define MAX_MSG_SIZE 1024

static int encode_varint(uint64_t value, uint8_t *out) {
    int n = 0;
    while (value >= 128) {
        out[n++] = (value & 0x7F) | 0x80;
        value >>= 7;
    }
    out[n++] = value & 0x7F;
    return n;
}

/* Returns bytes consumed, or -1 on failure. *value out-param. */
static int decode_varint(const uint8_t *buf, int buf_len, uint64_t *value) {
    *value = 0;
    int shift = 0;
    for (int i = 0; i < MAX_VARINT_BYTES; i++) {
        if (i >= buf_len) return -1;
        uint8_t b = buf[i];
        *value += ((uint64_t)(b & 0x7F)) << shift;
        if ((b & 0x80) == 0) return i + 1;
        shift += 7;
    }
    return -1;
}

static int encode_frame(const uint8_t *payload, int payload_len, uint8_t *out) {
    int n = encode_varint((uint64_t)payload_len, out);
    memcpy(out + n, payload, payload_len);
    return n + payload_len;
}

/* Returns bytes consumed, or -1 on failure. payload_out filled. */
static int decode_frame(const uint8_t *buf, int buf_len, uint8_t *payload_out, uint64_t max_msg) {
    uint64_t length;
    int hdr = decode_varint(buf, buf_len, &length);
    if (hdr < 0) return -1;
    if (length > max_msg) return -1;
    if (hdr + (int)length > buf_len) return -1;
    memcpy(payload_out, buf + hdr, length);
    return hdr + (int)length;
}

int main(void) {
    uint8_t buf[64], pl_out[64];
    uint64_t v;

    /* Varint sizes */
    assert(encode_varint(0, buf) == 1);
    assert(buf[0] == 0);
    assert(encode_varint(127, buf) == 1);
    assert(buf[0] == 0x7F);
    assert(encode_varint(128, buf) == 2);
    assert(buf[0] == 0x80 && buf[1] == 0x01);
    assert(encode_varint(16383, buf) == 2);
    assert(encode_varint(16384, buf) == 3);

    /* Round-trip */
    int n = encode_varint(1234567890, buf);
    int dn = decode_varint(buf, n, &v);
    assert(v == 1234567890ULL);
    assert(dn == n);

    /* Overflow guard */
    uint8_t bomb[16];
    memset(bomb, 0xFF, 11);
    assert(decode_varint(bomb, 11, &v) == -1);

    /* Frame round-trip */
    const uint8_t *payload = (const uint8_t *)"hello, world";
    int frame_n = encode_frame(payload, 12, buf);
    assert(frame_n == 13);
    assert(buf[0] == 12);
    int consumed = decode_frame(buf, frame_n, pl_out, MAX_MSG_SIZE);
    assert(consumed == 13);
    assert(memcmp(pl_out, payload, 12) == 0);

    /* Stream of 3 frames */
    uint8_t stream[256];
    int off = 0;
    off += encode_frame((const uint8_t *)"AAA", 3, stream + off);
    off += encode_frame((const uint8_t *)"BBBB", 4, stream + off);
    off += encode_frame((const uint8_t *)"CCCCC", 5, stream + off);
    int pos = 0, msg_count = 0;
    while (pos < off) {
        int c = decode_frame(stream + pos, off - pos, pl_out, MAX_MSG_SIZE);
        if (c < 0) break;
        msg_count++;
        pos += c;
    }
    assert(msg_count == 3);

    /* Truncated frame */
    uint8_t trunc[6] = {100, 'B', 'C', 'D', 'E', 'F'};
    assert(decode_frame(trunc, 6, pl_out, MAX_MSG_SIZE) == -1);

    /* Oversize length rejected */
    uint8_t over[16];
    int oh = encode_varint(9999, over);
    assert(decode_frame(over, oh, pl_out, MAX_MSG_SIZE) == -1);

    printf("serialization: 19/19 ok\n");
    return 0;
}
