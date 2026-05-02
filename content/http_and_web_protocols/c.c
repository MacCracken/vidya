/* Vidya — HTTP and Web Protocols in C
 *
 * HTTP/1.1 request parser. Sequential parse: request line → headers → body.
 */

#include <assert.h>
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define HEADER_CAP 16
#define STR_CAP 256
#define BODY_CAP 1024

typedef struct {
    uint8_t method[16];   int method_len;
    uint8_t path[STR_CAP];   int path_len;
    uint8_t version[16];     int version_len;
    uint8_t headers_name[HEADER_CAP][STR_CAP];
    int headers_name_len[HEADER_CAP];
    uint8_t headers_value[HEADER_CAP][STR_CAP];
    int headers_value_len[HEADER_CAP];
    int header_count;
    uint8_t body[BODY_CAP];
    int body_len;
} Request;

static int find_crlf(const uint8_t *buf, int len, int start) {
    for (int i = start; i + 1 < len; i++) {
        if (buf[i] == '\r' && buf[i + 1] == '\n') return i;
    }
    return -1;
}

static int parse_request(const uint8_t *buf, int len, Request *req) {
    memset(req, 0, sizeof *req);
    int rl_end = find_crlf(buf, len, 0);
    if (rl_end < 0) return 0;

    int sp1 = -1, sp2 = -1;
    for (int i = 0; i < rl_end; i++) if (buf[i] == ' ') { sp1 = i; break; }
    if (sp1 < 0) return 0;
    for (int i = sp1 + 1; i < rl_end; i++) if (buf[i] == ' ') { sp2 = i; break; }
    if (sp2 < 0) return 0;

    req->method_len = sp1;
    memcpy(req->method, buf, sp1);
    req->path_len = sp2 - sp1 - 1;
    memcpy(req->path, buf + sp1 + 1, req->path_len);
    req->version_len = rl_end - sp2 - 1;
    memcpy(req->version, buf + sp2 + 1, req->version_len);

    int pos = rl_end + 2;
    while (1) {
        if (pos + 1 >= len) return 0;
        if (buf[pos] == '\r' && buf[pos + 1] == '\n') {
            pos += 2;
            int bl = len - pos;
            if (bl > BODY_CAP) bl = BODY_CAP;
            req->body_len = bl;
            if (bl > 0) memcpy(req->body, buf + pos, bl);
            return 1;
        }
        int line_end = find_crlf(buf, len, pos);
        if (line_end < 0) return 0;
        int colon = -1;
        for (int i = pos; i < line_end; i++) if (buf[i] == ':') { colon = i; break; }
        if (colon < 0) return 0;
        if (req->header_count >= HEADER_CAP) return 0;
        int name_len = colon - pos;
        for (int i = 0; i < name_len; i++) {
            req->headers_name[req->header_count][i] = (uint8_t)tolower(buf[pos + i]);
        }
        req->headers_name_len[req->header_count] = name_len;
        int vstart = colon + 1;
        while (vstart < line_end && buf[vstart] == ' ') vstart++;
        int value_len = line_end - vstart;
        memcpy(req->headers_value[req->header_count], buf + vstart, value_len);
        req->headers_value_len[req->header_count] = value_len;
        req->header_count++;
        pos = line_end + 2;
    }
}

static const uint8_t *header_lookup(const Request *req, const char *name, int *out_len) {
    int n = (int)strlen(name);
    uint8_t lower[STR_CAP];
    for (int i = 0; i < n; i++) lower[i] = (uint8_t)tolower((unsigned char)name[i]);
    for (int i = 0; i < req->header_count; i++) {
        if (req->headers_name_len[i] == n &&
            memcmp(req->headers_name[i], lower, n) == 0) {
            *out_len = req->headers_value_len[i];
            return req->headers_value[i];
        }
    }
    *out_len = 0;
    return NULL;
}

int main(void) {
    Request r;
    int hl;

    const char *req1 = "GET /index.html HTTP/1.1\r\nHost: example.com\r\n\r\n";
    assert(parse_request((const uint8_t *)req1, 47, &r));
    assert(r.method_len == 3 && memcmp(r.method, "GET", 3) == 0);
    assert(r.path_len == 11 && memcmp(r.path, "/index.html", 11) == 0);
    assert(r.version_len == 8 && memcmp(r.version, "HTTP/1.1", 8) == 0);
    assert(r.header_count == 1);

    const uint8_t *v;
    v = header_lookup(&r, "host", &hl);
    assert(v && hl == 11 && memcmp(v, "example.com", 11) == 0);
    v = header_lookup(&r, "HOST", &hl);
    assert(v != NULL);
    v = header_lookup(&r, "Host", &hl);
    assert(v != NULL);

    const char *req3 = "GET / HTTP/1.1\r\nHost: x\r\nUser-Agent: test/1.0\r\nAccept: */*\r\n\r\n";
    assert(parse_request((const uint8_t *)req3, 62, &r));
    assert(r.header_count == 3);
    v = header_lookup(&r, "user-agent", &hl);
    assert(v && hl == 8 && memcmp(v, "test/1.0", 8) == 0);

    const char *req4 = "POST /api HTTP/1.1\r\nContent-Length: 11\r\n\r\nhello world";
    assert(parse_request((const uint8_t *)req4, 53, &r));
    assert(r.method_len == 4 && memcmp(r.method, "POST", 4) == 0);
    assert(r.body_len == 11 && memcmp(r.body, "hello world", 11) == 0);

    const char *req5 = "POST /a HTTP/1.1\r\nContent-Length: 13\r\n\r\nline1\r\nline2!";
    assert(parse_request((const uint8_t *)req5, 53, &r));
    assert(r.body_len == 13 && memcmp(r.body, "line1\r\nline2!", 13) == 0);

    const char *req6 = "GET / HTTP/1.1\r\nHost: x\r\n";
    assert(!parse_request((const uint8_t *)req6, 25, &r));

    parse_request((const uint8_t *)req1, 47, &r);
    assert(header_lookup(&r, "authorization", &hl) == NULL);

    printf("http_and_web_protocols: 24/24 ok\n");
    return 0;
}
