# Vidya — Allocators in Python
#
# Memory allocation strategies: bump (arena), slab (fixed-size free list),
# and bitmap (page-level bit tracking). These patterns are used in kernels,
# compilers, and high-performance systems where general-purpose malloc is
# too slow or too fragmented.
#
# Python doesn't expose raw memory, so we simulate backing storage with
# bytearrays and track offsets/indices manually. The algorithms are real —
# only the underlying memory model is simulated.

# ── Bump Allocator (Arena) ─────────────────────────────────────────────
#
# Maintains a pointer that advances with each allocation. Individual
# frees are impossible — the entire arena resets at once. O(1) alloc.
# Perfect for compiler AST nodes, per-request allocations, parsing.

class BumpAllocator:
    def __init__(self, capacity):
        self.memory = bytearray(capacity)
        self.capacity = capacity
        self.offset = 0
        self.alloc_count = 0

    def alloc(self, size, align=1):
        """Allocate size bytes with given alignment. Returns offset or None."""
        # Round up to alignment boundary
        aligned = (self.offset + align - 1) & ~(align - 1)
        end = aligned + size
        if end > self.capacity:
            return None  # out of memory
        self.offset = end
        self.alloc_count += 1
        return aligned

    def reset(self):
        """Free all allocations at once."""
        self.offset = 0
        self.alloc_count = 0

    def used(self):
        return self.offset

    def __repr__(self):
        return f"Bump[{self.offset}/{self.capacity} bytes, {self.alloc_count} allocs]"


# ── Slab Allocator ─────────────────────────────────────────────────────
#
# Pre-divides memory into fixed-size slots. A free list (stored as
# indices) tracks available slots. Alloc = pop head. Free = push head.
# Both O(1). Zero fragmentation for same-size objects. Used by the
# Linux kernel for task_struct, inode, dentry.

class SlabAllocator:
    def __init__(self, slot_size, count):
        self.slot_size = slot_size
        self.count = count
        self.memory = bytearray(slot_size * count)
        self.allocated = 0

        # Free list as a linked list of indices
        # free_head points to the first free slot index (or None)
        self.free_head = None
        self._next = [None] * count  # next[i] = index of next free slot

        # Initialize: chain all slots into the free list
        for i in range(count - 1, -1, -1):
            self._next[i] = self.free_head
            self.free_head = i

    def alloc(self):
        """Allocate one slot. Returns slot index, or None if full."""
        if self.free_head is None:
            return None
        index = self.free_head
        self.free_head = self._next[index]
        self._next[index] = None
        self.allocated += 1

        # Zero the slot
        offset = index * self.slot_size
        self.memory[offset:offset + self.slot_size] = bytes(self.slot_size)
        return index

    def free(self, index):
        """Return a slot to the free list."""
        self._next[index] = self.free_head
        self.free_head = index
        self.allocated -= 1

    def write(self, index, data):
        """Write bytes into a slot."""
        offset = index * self.slot_size
        length = min(len(data), self.slot_size)
        self.memory[offset:offset + length] = data[:length]

    def read(self, index, length=None):
        """Read bytes from a slot."""
        offset = index * self.slot_size
        if length is None:
            length = self.slot_size
        return bytes(self.memory[offset:offset + length])

    def __repr__(self):
        return f"Slab[{self.allocated}/{self.count} slots, {self.slot_size} bytes/slot]"


# ── Bitmap Allocator ───────────────────────────────────────────────────
#
# Tracks page-level allocation with one bit per page. Set = allocated,
# clear = free. A next_free hint accelerates sequential allocation.
# Used by physical memory managers (PMMs) in kernels.

class BitmapAllocator:
    def __init__(self, num_pages):
        self.num_pages = num_pages
        # One bit per page, packed into a bytearray
        self.bitmap = bytearray((num_pages + 7) // 8)
        self.next_free = 0
        self.allocated = 0

    def _test(self, page):
        byte_idx = page // 8
        bit_idx = page % 8
        return (self.bitmap[byte_idx] >> bit_idx) & 1

    def _set(self, page):
        byte_idx = page // 8
        bit_idx = page % 8
        self.bitmap[byte_idx] |= (1 << bit_idx)

    def _clear(self, page):
        byte_idx = page // 8
        bit_idx = page % 8
        self.bitmap[byte_idx] &= ~(1 << bit_idx) & 0xFF

    def alloc(self):
        """Allocate one page. Returns page index, or None if full."""
        # Search from hint forward
        for i in range(self.next_free, self.num_pages):
            if not self._test(i):
                self._set(i)
                self.next_free = i + 1
                self.allocated += 1
                return i
        # Wrap around
        for i in range(0, self.next_free):
            if not self._test(i):
                self._set(i)
                self.next_free = i + 1
                self.allocated += 1
                return i
        return None

    def free(self, page):
        """Free a page. Retracts the hint if the freed page is earlier."""
        self._clear(page)
        self.allocated -= 1
        if page < self.next_free:
            self.next_free = page

    def __repr__(self):
        return f"Bitmap[{self.allocated}/{self.num_pages} pages]"


# ── Tests ──────────────────────────────────────────────────────────────

def main():
    print("Allocators — three strategies for different patterns:\n")

    # Bump allocator
    print("1. Bump Allocator (arena):")
    bump = BumpAllocator(4096)
    offsets = [bump.alloc(24, align=8) for _ in range(10)]
    assert all(o is not None for o in offsets), "all bump allocs succeed"
    assert all(o % 8 == 0 for o in offsets), "all offsets 8-byte aligned"
    print(f"   Allocated 10 x 24 bytes: first 3 offsets = {offsets[:3]}")
    print(f"   {bump}")

    # Alignment test: 3 bytes then 8-byte-aligned alloc
    bump.alloc(3, align=1)
    aligned_off = bump.alloc(8, align=8)
    assert aligned_off % 8 == 0, "8-byte alignment after odd-size alloc"
    print(f"   After 3-byte + 8-byte: offset {aligned_off} (aligned: {aligned_off % 8 == 0})")

    bump.reset()
    assert bump.used() == 0, "bump reset clears all"
    print(f"   After reset: {bump}")

    # Re-allocate after reset to prove reuse
    reuse = bump.alloc(16, align=8)
    assert reuse == 0, "first alloc after reset starts at 0"
    print(f"   Re-allocated after reset: offset {reuse}\n")

    # Slab allocator
    print("2. Slab Allocator (fixed-size objects):")
    slab = SlabAllocator(64, 16)
    slots = [slab.alloc() for _ in range(5)]
    assert all(s is not None for s in slots), "all slab allocs succeed"
    print(f"   Allocated 5 slots: {slots}")
    print(f"   {slab}")

    slab.free(slots[1])
    slab.free(slots[3])
    print(f"   Freed slots {slots[1]} and {slots[3]}")
    print(f"   {slab}")

    # Reallocate — should reuse freed slots (LIFO free list)
    reused1 = slab.alloc()
    reused2 = slab.alloc()
    assert reused1 == slots[3], "reuses most recently freed slot (LIFO)"
    assert reused2 == slots[1], "reuses second freed slot"
    print(f"   Reallocated: got slots {reused1} and {reused2} (reused)")

    # Write and read back
    slab.write(reused1, b"\xDE\xAD\xBE\xEF")
    data = slab.read(reused1, 4)
    assert data == b"\xDE\xAD\xBE\xEF", "slab read/write roundtrip"
    print(f"   Write/read test: {data.hex()}\n")

    # Bitmap allocator
    print("3. Bitmap Allocator (page frames):")
    bmp = BitmapAllocator(64)
    p0 = bmp.alloc()
    p1 = bmp.alloc()
    p2 = bmp.alloc()
    assert p0 == 0 and p1 == 1 and p2 == 2, "sequential allocation"
    print(f"   Allocated pages: {p0}, {p1}, {p2}")
    print(f"   {bmp}")

    # Free middle page, next alloc should reuse it (hint retracts)
    bmp.free(1)
    print(f"   Freed page 1")
    reused_page = bmp.alloc()
    assert reused_page == 1, "reuses freed page via hint retraction"
    print(f"   Reallocated: page {reused_page} (reused)")

    # Next alloc continues from hint
    p3 = bmp.alloc()
    assert p3 == 3, "continues at next free page"
    print(f"   Next alloc: page {p3}")
    print(f"   {bmp}")

    # Fill and verify exhaustion
    pages = []
    while True:
        p = bmp.alloc()
        if p is None:
            break
        pages.append(p)
    assert bmp.allocated == 64, "all pages allocated"
    print(f"   Filled all 64 pages, alloc returns None: {bmp.alloc() is None}")

    print("\nAll tests passed.")

if __name__ == "__main__":
    main()
