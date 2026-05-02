/* Vidya — Direct DRM GPU Compute in C
 *
 * In-memory simulation of GEM BO + VA-map + submit + syncobj-wait flow.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define BO_CAP 32
#define VA_CAP 32

typedef struct {
    int64_t fd;
    uint64_t bo_size[BO_CAP];
    uint32_t next_bo;
    uint64_t va_addr[VA_CAP];
    uint32_t va_bo[VA_CAP];
    int va_count;
    uint64_t next_seq;
    uint64_t completed_seq;
} Device;

static void dev_init(Device *d) {
    memset(d, 0, sizeof *d);
    d->next_bo = 1;
    d->next_seq = 1;
}

static int64_t open_render_node(Device *d) { d->fd = 42; return d->fd; }

static uint32_t gem_create(Device *d, uint64_t size) {
    if (d->next_bo >= BO_CAP) return 0;
    uint32_t h = d->next_bo++;
    d->bo_size[h] = size;
    return h;
}

static int gem_destroy(Device *d, uint32_t handle) {
    if (handle == 0 || handle >= BO_CAP) return 0;
    if (d->bo_size[handle] == 0) return 0;
    d->bo_size[handle] = 0;
    for (int i = 0; i < d->va_count; i++)
        if (d->va_bo[i] == handle) d->va_bo[i] = 0;
    return 1;
}

static int gem_va_map(Device *d, uint32_t handle, uint64_t va) {
    if (handle == 0 || handle >= BO_CAP) return 0;
    if (d->bo_size[handle] == 0) return 0;
    if (d->va_count >= VA_CAP) return 0;
    d->va_addr[d->va_count] = va;
    d->va_bo[d->va_count] = handle;
    d->va_count++;
    return 1;
}

static uint32_t va_lookup(const Device *d, uint64_t va) {
    for (int i = 0; i < d->va_count; i++)
        if (d->va_addr[i] == va && d->va_bo[i] != 0) return d->va_bo[i];
    return 0;
}

static uint64_t submit_dispatch(Device *d, uint32_t handle) {
    if (handle == 0 || handle >= BO_CAP) return 0;
    if (d->bo_size[handle] == 0) return 0;
    uint64_t seq = d->next_seq++;
    d->completed_seq = seq;
    return seq;
}

static int syncobj_wait(const Device *d, uint64_t seq) {
    return d->completed_seq >= seq;
}

int main(void) {
    Device d;
    dev_init(&d);

    assert(open_render_node(&d) != 0);

    uint32_t b1 = gem_create(&d, 4096);
    uint32_t b2 = gem_create(&d, 8192);
    uint32_t b3 = gem_create(&d, 16384);
    assert(b1 == 1 && b2 == 2 && b3 == 3);

    assert(gem_va_map(&d, b1, 0x1000));
    assert(gem_va_map(&d, b2, 0x2000));

    assert(va_lookup(&d, 0x1000) == b1);
    assert(va_lookup(&d, 0x2000) == b2);
    assert(va_lookup(&d, 0x9000) == 0);

    assert(!gem_va_map(&d, 99, 0x3000));
    assert(!gem_va_map(&d, 0, 0x3000));

    assert(submit_dispatch(&d, b1) == 1);
    assert(submit_dispatch(&d, b2) == 2);
    assert(submit_dispatch(&d, b3) == 3);

    assert(syncobj_wait(&d, 1));
    assert(syncobj_wait(&d, 3));
    assert(!syncobj_wait(&d, 99));

    gem_destroy(&d, b1);
    assert(va_lookup(&d, 0x1000) == 0);

    assert(submit_dispatch(&d, b1) == 0);
    assert(submit_dispatch(&d, b2) == 4);

    printf("direct_drm_gpu_compute: 20/20 ok\n");
    return 0;
}
