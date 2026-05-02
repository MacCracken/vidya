/* Vidya — Page Management in C
 *
 * Fixed-size 4KB pages, single file. Header at offset 0; page 0 reserved
 * as null sentinel; data pages at PAGE_SZ + num * PAGE_SZ. Free list is
 * a stack with `next` pointer at byte offset 8 of each freed page.
 * Mirrors the cyrius reference's test surface exactly.
 */

#include <assert.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define PAGE_SZ 4096
#define MAGIC 0x50415452U
#define H_PGCOUNT 8
#define H_FREEHEAD 16
#define FP_NEXT 8

typedef struct { uint64_t page_count; uint64_t freehead; } Header;

static off_t page_offset(uint64_t num) { return (off_t)(PAGE_SZ + num * PAGE_SZ); }

static void hdr_init(Header *h) { h->page_count = 1; h->freehead = 0; }

static void hdr_to_bytes(const Header *h, uint8_t buf[PAGE_SZ]) {
    memset(buf, 0, PAGE_SZ);
    uint32_t m = MAGIC;
    memcpy(buf, &m, 4);
    memcpy(buf + H_PGCOUNT, &h->page_count, 8);
    memcpy(buf + H_FREEHEAD, &h->freehead, 8);
}

static int hdr_verify(const uint8_t buf[PAGE_SZ]) {
    uint32_t m;
    memcpy(&m, buf, 4);
    return m == MAGIC;
}

static void hdr_load(Header *h, const uint8_t buf[PAGE_SZ]) {
    memcpy(&h->page_count, buf + H_PGCOUNT, 8);
    memcpy(&h->freehead, buf + H_FREEHEAD, 8);
}

static int page_read(int fd, uint64_t num, uint8_t *buf) {
    if (lseek(fd, page_offset(num), SEEK_SET) < 0) return -1;
    return (int)read(fd, buf, PAGE_SZ);
}

static int page_write(int fd, uint64_t num, const uint8_t *buf) {
    if (lseek(fd, page_offset(num), SEEK_SET) < 0) return -1;
    return (int)write(fd, buf, PAGE_SZ);
}

static uint64_t page_alloc(int fd, Header *h) {
    if (h->freehead != 0) {
        uint64_t fh = h->freehead;
        uint8_t buf[PAGE_SZ];
        page_read(fd, fh, buf);
        memcpy(&h->freehead, buf + FP_NEXT, 8);
        return fh;
    }
    uint64_t num = h->page_count++;
    uint8_t zero[PAGE_SZ] = {0};
    page_write(fd, num, zero);
    return num;
}

static void page_free(int fd, Header *h, uint64_t num) {
    uint8_t buf[PAGE_SZ];
    memset(buf, 0, PAGE_SZ);
    memcpy(buf + FP_NEXT, &h->freehead, 8);
    page_write(fd, num, buf);
    h->freehead = num;
}

int main(void) {
    const char *path = "/tmp/vidya_page_c.bin";
    unlink(path);
    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
    assert(fd >= 0);

    Header h;
    hdr_init(&h);
    uint8_t hbuf[PAGE_SZ];
    hdr_to_bytes(&h, hbuf);
    write(fd, hbuf, PAGE_SZ);

    /* 1-2. header */
    lseek(fd, 0, SEEK_SET);
    uint8_t rh[PAGE_SZ];
    read(fd, rh, PAGE_SZ);
    assert(hdr_verify(rh) && "magic ok");
    Header loaded;
    hdr_load(&loaded, rh);
    assert(loaded.page_count == 1 && "pgcount starts at 1");

    /* 3-4. alloc */
    uint64_t p1 = page_alloc(fd, &h);
    assert(p1 == 1 && "first alloc = 1");
    uint64_t p2 = page_alloc(fd, &h);
    assert(p2 == 2 && "second alloc = 2");

    /* 5. roundtrip */
    uint8_t buf[PAGE_SZ] = {0};
    uint64_t v = 42;
    memcpy(buf, &v, 8);
    page_write(fd, p1, buf);
    uint8_t rb[PAGE_SZ];
    page_read(fd, p1, rb);
    uint64_t got;
    memcpy(&got, rb, 8);
    assert(got == 42 && "read back 42");

    /* 6. free + reuse */
    page_free(fd, &h, p2);
    uint64_t p3 = page_alloc(fd, &h);
    assert(p3 == 2 && "reused freed page");

    close(fd);
    unlink(path);
    printf("page_management: 6/6 ok\n");
    return 0;
}
