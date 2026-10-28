# Vidya — GPU Memory Pooling in Python
#
# Bump allocator over a 1024-byte pool.

POOL_SIZE = 1024


class Pool:
    def __init__(self):
        self.bump = 0

    def reset(self):
        self.bump = 0

    def used(self):
        return self.bump

    def free(self):
        return POOL_SIZE - self.bump

    def alloc(self, size):
        if size == 0:
            return self.bump
        if self.bump + size > POOL_SIZE:
            return -1
        off = self.bump
        self.bump += size
        return off

    def alloc_aligned(self, size, align):
        mask = align - 1
        aligned = (self.bump + mask) & ~mask
        if aligned + size > POOL_SIZE:
            return -1
        self.bump = aligned + size
        return aligned


def main():
    p = Pool()
    assert p.used() == 0
    assert p.free() == 1024

    assert p.alloc(100) == 0
    assert p.used() == 100

    assert p.alloc(200) == 100
    assert p.used() == 300

    assert p.alloc(1000) == -1
    assert p.used() == 300

    p.reset()
    assert p.used() == 0
    assert p.free() == 1024
    assert p.alloc(50) == 0

    assert p.alloc_aligned(32, 16) == 64
    assert p.used() == 96

    assert p.alloc(0) == 96
    assert p.used() == 96

    p.reset()
    for _ in range(10):
        p.alloc(8)
    assert p.used() == 80

    print("gpu_memory_pooling: 16/16 ok")


main()
