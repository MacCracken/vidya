# Vidya — Bindless Resources in Python
#
# In-memory descriptor table — "one global table per frame" pattern.

TABLE_CAP = 64


class DescriptorTable:
    def __init__(self):
        self.slots = [0] * TABLE_CAP
        self.free_links = [0] * TABLE_CAP
        self.next_id = 1
        self.free_head = 0

    def alloc(self, desc):
        if self.free_head != 0:
            i = self.free_head
            self.free_head = self.free_links[i]
            self.slots[i] = desc
            return i
        if self.next_id >= TABLE_CAP:
            return 0
        i = self.next_id
        self.next_id += 1
        self.slots[i] = desc
        return i

    def lookup(self, i):
        if i == 0 or i >= TABLE_CAP:
            return 0
        return self.slots[i]

    def update(self, i, desc):
        if i == 0 or i >= TABLE_CAP:
            return False
        self.slots[i] = desc
        return True

    def free(self, i):
        if i == 0 or i >= TABLE_CAP:
            return False
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

    t.free(id2)
    assert t.lookup(id2) == 0
    id4 = t.alloc(0x4444444444444444)
    assert id4 == id2
    assert t.lookup(id4) == 0x4444444444444444

    t2 = DescriptorTable()
    for i in range(1, TABLE_CAP):
        t2.alloc(i)
    assert t2.alloc(0xDEADBEEF) == 0

    print("bindless_resources: 15/15 ok")


main()
