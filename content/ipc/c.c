/* Vidya — IPC in C
 *
 * In-memory simulation: shared memory, pipe, named channel.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define SHM_REGION_CAP 4
#define SHM_BYTES 64
#define PIPE_CAP 8
#define CHAN_CAP 4
#define CHAN_QUEUE_CAP 8

typedef struct {
    uint8_t shm[SHM_REGION_CAP][SHM_BYTES];
    uint8_t pipe_buf[PIPE_CAP];
    int pipe_head;
    int pipe_count;
    int chan_open[CHAN_CAP];
    uint64_t chan_queue[CHAN_CAP][CHAN_QUEUE_CAP];
    int chan_count[CHAN_CAP];
} Ipc;

static void ipc_init(Ipc *i) { memset(i, 0, sizeof *i); }

static int shm_write(Ipc *i, int region, int offset, uint8_t byte) {
    if (region < 0 || region >= SHM_REGION_CAP) return 0;
    if (offset < 0 || offset >= SHM_BYTES) return 0;
    i->shm[region][offset] = byte;
    return 1;
}

static int shm_read(const Ipc *i, int region, int offset) {
    if (region < 0 || region >= SHM_REGION_CAP) return -1;
    if (offset < 0 || offset >= SHM_BYTES) return -1;
    return i->shm[region][offset];
}

static int pipe_write(Ipc *i, uint8_t byte) {
    if (i->pipe_count >= PIPE_CAP) return 0;
    int tail = (i->pipe_head + i->pipe_count) % PIPE_CAP;
    i->pipe_buf[tail] = byte;
    i->pipe_count++;
    return 1;
}

static int pipe_read(Ipc *i) {
    if (i->pipe_count == 0) return -1;
    uint8_t b = i->pipe_buf[i->pipe_head];
    i->pipe_head = (i->pipe_head + 1) % PIPE_CAP;
    i->pipe_count--;
    return b;
}

static int chan_listen(Ipc *i, int endpoint) {
    if (endpoint < 0 || endpoint >= CHAN_CAP) return 0;
    i->chan_open[endpoint] = 1;
    return 1;
}

static int chan_send(Ipc *i, int dst, uint64_t msg) {
    if (dst < 0 || dst >= CHAN_CAP) return 0;
    if (!i->chan_open[dst]) return 0;
    if (i->chan_count[dst] >= CHAN_QUEUE_CAP) return 0;
    i->chan_queue[dst][i->chan_count[dst]++] = msg;
    return 1;
}

static int64_t chan_recv(Ipc *i, int endpoint) {
    if (endpoint < 0 || endpoint >= CHAN_CAP) return -1;
    if (!i->chan_open[endpoint]) return -1;
    if (i->chan_count[endpoint] == 0) return -1;
    int64_t msg = (int64_t)i->chan_queue[endpoint][0];
    for (int k = 0; k < i->chan_count[endpoint] - 1; k++) {
        i->chan_queue[endpoint][k] = i->chan_queue[endpoint][k + 1];
    }
    i->chan_count[endpoint]--;
    return msg;
}

int main(void) {
    Ipc ipc; ipc_init(&ipc);

    // Each operation runs OUTSIDE assert() and its saved result is checked:
    // under -DNDEBUG assert's expression is not evaluated, so
    // assert(shm_write(...)) would compile the write itself out.
    int r = shm_write(&ipc, 1, 5, 0xA1);
    assert(r);
    assert(shm_read(&ipc, 1, 5) == 0xA1);
    assert(shm_read(&ipc, 2, 5) == 0);
    r = shm_write(&ipc, 1, 99, 0xFF);
    assert(!r);
    assert(shm_read(&ipc, 1, 99) == -1);

    pipe_write(&ipc, 65); pipe_write(&ipc, 66); pipe_write(&ipc, 67);
    r = pipe_read(&ipc);
    assert(r == 65);
    r = pipe_read(&ipc);
    assert(r == 66);
    r = pipe_read(&ipc);
    assert(r == 67);
    r = pipe_read(&ipc);
    assert(r == -1);

    Ipc ipc2; ipc_init(&ipc2);
    for (int k = 0; k < PIPE_CAP; k++) pipe_write(&ipc2, (uint8_t)(k + 100));
    r = pipe_write(&ipc2, 99);
    assert(!r);
    pipe_read(&ipc2);
    r = pipe_write(&ipc2, 99);
    assert(r);

    Ipc ipc3; ipc_init(&ipc3);
    r = chan_send(&ipc3, 1, 0xDEADBEEFULL);
    assert(!r);
    chan_listen(&ipc3, 1);
    r = chan_send(&ipc3, 1, 0xCAFE);
    assert(r);
    r = chan_send(&ipc3, 1, 0xBABE);
    assert(r);
    int64_t msg = chan_recv(&ipc3, 1);
    assert(msg == 0xCAFE);
    msg = chan_recv(&ipc3, 1);
    assert(msg == 0xBABE);
    msg = chan_recv(&ipc3, 1);
    assert(msg == -1);
    msg = chan_recv(&ipc3, 2);
    assert(msg == -1);

    printf("ipc: 18/18 ok\n");
    return 0;
}
