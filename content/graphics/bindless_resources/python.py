# Vidya — Bindless Resources in Python
#
# In-memory descriptor table — "one global table per frame" pattern.
#
# A handle is (generation << 8) | slot. Freeing a slot bumps its
# generation, so a handle kept past free() no longer matches and is
# rejected instead of silently reading whatever reuses the slot. A bare
# slot index cannot tell the two apart, and a double free would put the
# slot on the free list twice (two live allocations, one slot).

TABLE_CAP = 64
IDX_BITS = 8
IDX_MASK = (1 << IDX_BITS) - 1


class DescriptorTable:
    def __init__(self):
        self.slots = [0] * TABLE_CAP
        self.free_links = [0] * TABLE_CAP
        self.gens = [0] * TABLE_CAP
        self.live = [False] * TABLE_CAP
        self.next_id = 1
        self.free_head = 0

    def _handle(self, i):
        return (self.gens[i] << IDX_BITS) | i

    def _live_index(self, h):
        """Slot index for a live, current-generation handle, else 0."""
        i = h & IDX_MASK
        if i == 0 or i >= TABLE_CAP or not self.live[i]:
            return 0
        if (h >> IDX_BITS) != self.gens[i]:
            return 0  # stale: the slot was freed (and maybe reused) since
        return i

    def alloc(self, desc):
        if self.free_head != 0:
            i = self.free_head
            self.free_head = self.free_links[i]
        elif self.next_id >= TABLE_CAP:
            return 0
        else:
            i = self.next_id
            self.next_id += 1
        self.slots[i] = desc
        self.live[i] = True
        return self._handle(i)

    def lookup(self, h):
        i = self._live_index(h)
        return self.slots[i] if i else 0

    def update(self, h, desc):
        i = self._live_index(h)
        if not i:
            return False
        self.slots[i] = desc
        return True

    def free(self, h):
        i = self._live_index(h)
        if not i:
            return False  # null, stale or double free
        self.live[i] = False
        self.gens[i] += 1
        self.free_links[i] = self.free_head
        self.free_head = i
        self.slots[i] = 0
        return True


def main():
    t = DescriptorTable()

    id1 = t.alloc(0x1111111111111111)
    id2 = t.alloc(0x2222222222222222)
    id3 = t.alloc(0x3333333333333333)
    assert id1 == 1
    assert id2 == 2
    assert id3 == 3

    assert t.lookup(0) == 0

    assert t.lookup(id1) == 0x1111111111111111
    assert t.lookup(id2) == 0x2222222222222222
    assert t.lookup(id3) == 0x3333333333333333

    assert t.update(id2, 0xAAAAAAAAAAAAAAAA)
    assert t.lookup(id2) == 0xAAAAAAAAAAAAAAAA
    assert t.lookup(id1) == 0x1111111111111111
    assert t.lookup(id3) == 0x3333333333333333

    assert t.free(id2)
    assert t.lookup(id2) == 0
    id4 = t.alloc(0x4444444444444444)
    assert id4 & IDX_MASK == id2 & IDX_MASK   # slot reused...
    assert id4 != id2                         # ...under a new generation
    assert t.lookup(id4) == 0x4444444444444444
    assert t.lookup(id2) == 0                 # stale handle rejected
    assert not t.free(id2)                    # double/stale free rejected

    t2 = DescriptorTable()
    for i in range(1, TABLE_CAP):
        t2.alloc(i)
    assert t2.alloc(0xDEADBEEF) == 0

    print("bindless_resources: 19/19 ok")


main()
