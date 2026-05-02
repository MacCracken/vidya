# Vidya — IPC in Python
#
# In-memory simulation of three IPC primitives: shared memory,
# bounded pipe, named-endpoint message channel.

SHM_REGION_CAP = 4
SHM_BYTES = 64
PIPE_CAP = 8
CHAN_CAP = 4
CHAN_QUEUE_CAP = 8


class Ipc:
    def __init__(self):
        self.shm = [bytearray(SHM_BYTES) for _ in range(SHM_REGION_CAP)]
        self.pipe = bytearray(PIPE_CAP)
        self.pipe_head = 0
        self.pipe_count = 0
        self.chan_open = [False] * CHAN_CAP
        self.chan_queue = [[0] * CHAN_QUEUE_CAP for _ in range(CHAN_CAP)]
        self.chan_count = [0] * CHAN_CAP

    def shm_write(self, region, offset, byte):
        if region < 0 or region >= SHM_REGION_CAP: return False
        if offset < 0 or offset >= SHM_BYTES: return False
        self.shm[region][offset] = byte
        return True

    def shm_read(self, region, offset):
        if region < 0 or region >= SHM_REGION_CAP: return -1
        if offset < 0 or offset >= SHM_BYTES: return -1
        return self.shm[region][offset]

    def pipe_write(self, byte):
        if self.pipe_count >= PIPE_CAP: return False
        tail = (self.pipe_head + self.pipe_count) % PIPE_CAP
        self.pipe[tail] = byte
        self.pipe_count += 1
        return True

    def pipe_read(self):
        if self.pipe_count == 0: return -1
        b = self.pipe[self.pipe_head]
        self.pipe_head = (self.pipe_head + 1) % PIPE_CAP
        self.pipe_count -= 1
        return b

    def chan_listen(self, endpoint):
        if endpoint < 0 or endpoint >= CHAN_CAP: return False
        self.chan_open[endpoint] = True
        return True

    def chan_send(self, dst, msg):
        if dst < 0 or dst >= CHAN_CAP: return False
        if not self.chan_open[dst]: return False
        if self.chan_count[dst] >= CHAN_QUEUE_CAP: return False
        self.chan_queue[dst][self.chan_count[dst]] = msg
        self.chan_count[dst] += 1
        return True

    def chan_recv(self, endpoint):
        if endpoint < 0 or endpoint >= CHAN_CAP: return -1
        if not self.chan_open[endpoint]: return -1
        if self.chan_count[endpoint] == 0: return -1
        msg = self.chan_queue[endpoint][0]
        for i in range(self.chan_count[endpoint] - 1):
            self.chan_queue[endpoint][i] = self.chan_queue[endpoint][i + 1]
        self.chan_count[endpoint] -= 1
        return msg


def main():
    ipc = Ipc()

    assert ipc.shm_write(1, 5, 0xA1)
    assert ipc.shm_read(1, 5) == 0xA1
    assert ipc.shm_read(2, 5) == 0
    assert not ipc.shm_write(1, 99, 0xFF)
    assert ipc.shm_read(1, 99) == -1

    ipc.pipe_write(65); ipc.pipe_write(66); ipc.pipe_write(67)
    assert ipc.pipe_read() == 65
    assert ipc.pipe_read() == 66
    assert ipc.pipe_read() == 67
    assert ipc.pipe_read() == -1

    ipc2 = Ipc()
    for i in range(PIPE_CAP): ipc2.pipe_write(i + 100)
    assert not ipc2.pipe_write(99)
    ipc2.pipe_read()
    assert ipc2.pipe_write(99)

    ipc3 = Ipc()
    assert not ipc3.chan_send(1, 0xDEADBEEF)
    ipc3.chan_listen(1)
    assert ipc3.chan_send(1, 0xCAFE)
    assert ipc3.chan_send(1, 0xBABE)
    assert ipc3.chan_recv(1) == 0xCAFE
    assert ipc3.chan_recv(1) == 0xBABE
    assert ipc3.chan_recv(1) == -1
    assert ipc3.chan_recv(2) == -1

    print("ipc: 18/18 ok")


main()
