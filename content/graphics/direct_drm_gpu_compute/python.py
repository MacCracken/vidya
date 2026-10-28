# Vidya — Direct DRM GPU Compute in Python
#
# In-memory simulation of GEM BO + VA-map + submit + syncobj-wait flow.

BO_CAP = 32
VA_CAP = 32


class Device:
    def __init__(self):
        self.fd = 0
        self.bo_size = [0] * BO_CAP
        self.next_bo = 1
        self.va_addr = [0] * VA_CAP
        self.va_bo = [0] * VA_CAP
        self.va_count = 0
        self.next_seq = 1
        self.completed_seq = 0

    def open_render_node(self):
        self.fd = 42
        return self.fd

    def gem_create(self, size):
        if self.next_bo >= BO_CAP:
            return 0
        h = self.next_bo
        self.next_bo += 1
        self.bo_size[h] = size
        return h

    def gem_destroy(self, handle):
        if handle == 0 or handle >= BO_CAP:
            return False
        if self.bo_size[handle] == 0:
            return False
        self.bo_size[handle] = 0
        for i in range(self.va_count):
            if self.va_bo[i] == handle:
                self.va_bo[i] = 0
        return True

    def gem_va_map(self, handle, va):
        if handle == 0 or handle >= BO_CAP:
            return False
        if self.bo_size[handle] == 0:
            return False
        if self.va_count >= VA_CAP:
            return False
        self.va_addr[self.va_count] = va
        self.va_bo[self.va_count] = handle
        self.va_count += 1
        return True

    def va_lookup(self, va):
        for i in range(self.va_count):
            if self.va_addr[i] == va and self.va_bo[i] != 0:
                return self.va_bo[i]
        return 0

    def submit(self, handle):
        if handle == 0 or handle >= BO_CAP:
            return 0
        if self.bo_size[handle] == 0:
            return 0
        seq = self.next_seq
        self.next_seq += 1
        self.completed_seq = seq
        return seq

    def syncobj_wait(self, seq):
        return self.completed_seq >= seq


def main():
    d = Device()

    assert d.open_render_node() != 0

    b1 = d.gem_create(4096)
    b2 = d.gem_create(8192)
    b3 = d.gem_create(16384)
    assert b1 == 1
    assert b2 == 2
    assert b3 == 3

    assert d.gem_va_map(b1, 0x1000)
    assert d.gem_va_map(b2, 0x2000)

    assert d.va_lookup(0x1000) == b1
    assert d.va_lookup(0x2000) == b2
    assert d.va_lookup(0x9000) == 0

    assert not d.gem_va_map(99, 0x3000)
    assert not d.gem_va_map(0, 0x3000)

    assert d.submit(b1) == 1
    assert d.submit(b2) == 2
    assert d.submit(b3) == 3

    assert d.syncobj_wait(1)
    assert d.syncobj_wait(3)
    assert not d.syncobj_wait(99)

    d.gem_destroy(b1)
    assert d.va_lookup(0x1000) == 0

    assert d.submit(b1) == 0
    assert d.submit(b2) == 4

    print("direct_drm_gpu_compute: 20/20 ok")


main()
