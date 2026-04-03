// Allocators — Rust Implementation
//
// Demonstrates four allocation strategies:
//   1. Bump allocator (arena) — O(1) alloc, batch free
//   2. Slab allocator — O(1) alloc/free for fixed-size objects
//   3. Buddy allocator — O(log n) alloc/free with coalescing
//   4. Pool allocator — fixed-count object reuse
//
// Each allocator is purpose-built for a specific usage pattern.
// A compiler needs bump (AST nodes), a kernel needs buddy (page frames),
// and a network stack needs pool (packet buffers).

use std::alloc::Layout;
use std::fmt;

// ── Bump Allocator (Arena) ────────────────────────────────────────────────

struct BumpAllocator {
    memory: Vec<u8>,
    offset: usize,
    alloc_count: usize,
}

impl BumpAllocator {
    fn new(capacity: usize) -> Self {
        Self {
            memory: vec![0u8; capacity],
            offset: 0,
            alloc_count: 0,
        }
    }

    /// Allocate `size` bytes with the given alignment. Returns offset into memory.
    fn alloc(&mut self, layout: Layout) -> Option<usize> {
        // Round up to alignment
        let aligned = (self.offset + layout.align() - 1) & !(layout.align() - 1);
        let end = aligned + layout.size();

        if end > self.memory.len() {
            return None; // out of memory
        }

        self.offset = end;
        self.alloc_count += 1;
        Some(aligned)
    }

    /// Reset the arena — frees all allocations at once.
    fn reset(&mut self) {
        self.offset = 0;
        self.alloc_count = 0;
    }

    fn used(&self) -> usize {
        self.offset
    }

    fn capacity(&self) -> usize {
        self.memory.len()
    }
}

impl fmt::Display for BumpAllocator {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Bump[{}/{} bytes, {} allocs]",
            self.used(),
            self.capacity(),
            self.alloc_count
        )
    }
}

// ── Slab Allocator ────────────────────────────────────────────────────────

struct SlabAllocator {
    memory: Vec<u8>,
    slot_size: usize,
    capacity: usize,
    /// Free list: each free slot stores the index of the next free slot
    free_head: Option<usize>,
    allocated: usize,
}

impl SlabAllocator {
    fn new(slot_size: usize, count: usize) -> Self {
        let slot_size = slot_size.max(std::mem::size_of::<usize>()); // must fit a pointer
        let memory = vec![0u8; slot_size * count];

        let mut slab = Self {
            memory,
            slot_size,
            capacity: count,
            free_head: None,
            allocated: 0,
        };

        // Initialize free list: each slot points to the next
        for i in (0..count).rev() {
            let offset = i * slot_size;
            // Store next free index in the slot itself
            let next = slab.free_head;
            let next_val = next.unwrap_or(usize::MAX);
            slab.memory[offset..offset + std::mem::size_of::<usize>()]
                .copy_from_slice(&next_val.to_ne_bytes());
            slab.free_head = Some(i);
        }

        slab
    }

    /// Allocate one slot. Returns slot index.
    fn alloc(&mut self) -> Option<usize> {
        let index = self.free_head?;
        let offset = index * self.slot_size;

        // Read next free from the slot
        let mut next_bytes = [0u8; std::mem::size_of::<usize>()];
        next_bytes.copy_from_slice(&self.memory[offset..offset + std::mem::size_of::<usize>()]);
        let next = usize::from_ne_bytes(next_bytes);

        self.free_head = if next == usize::MAX { None } else { Some(next) };
        self.allocated += 1;

        // Zero the slot for the user
        self.memory[offset..offset + self.slot_size].fill(0);
        Some(index)
    }

    /// Free a slot by index.
    fn free(&mut self, index: usize) {
        let offset = index * self.slot_size;
        // Store current free head in the slot
        let next_val = self.free_head.unwrap_or(usize::MAX);
        self.memory[offset..offset + std::mem::size_of::<usize>()]
            .copy_from_slice(&next_val.to_ne_bytes());
        self.free_head = Some(index);
        self.allocated -= 1;
    }
}

impl fmt::Display for SlabAllocator {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "Slab[{}/{} slots, {} bytes/slot]",
            self.allocated, self.capacity, self.slot_size
        )
    }
}

// ── Buddy Allocator ──────────────────────────────────────────────────────

struct BuddyAllocator {
    /// Total size (must be power of 2)
    size: usize,
    /// Minimum block size
    min_block: usize,
    /// Free lists indexed by order (order 0 = min_block, order k = min_block * 2^k)
    free_lists: Vec<Vec<usize>>,
    /// Track allocated blocks: offset → order
    allocated: std::collections::HashMap<usize, usize>,
    num_allocs: usize,
}

impl BuddyAllocator {
    fn new(size: usize, min_block: usize) -> Self {
        assert!(size.is_power_of_two());
        assert!(min_block.is_power_of_two());
        assert!(size >= min_block);

        let max_order = (size / min_block).trailing_zeros() as usize;
        let mut free_lists = vec![Vec::new(); max_order + 1];

        // Start with one block of maximum order
        free_lists[max_order].push(0);

        Self {
            size,
            min_block,
            free_lists,
            allocated: std::collections::HashMap::new(),
            num_allocs: 0,
        }
    }

    fn order_for_size(&self, size: usize) -> usize {
        let blocks_needed = (size + self.min_block - 1) / self.min_block;
        let order = if blocks_needed <= 1 {
            0
        } else {
            (blocks_needed - 1).next_power_of_two().trailing_zeros() as usize + 1
        };
        // Clamp: use next power of two's order
        let adjusted = blocks_needed.next_power_of_two().trailing_zeros() as usize;
        adjusted
    }

    fn alloc(&mut self, size: usize) -> Option<usize> {
        let target_order = self.order_for_size(size);

        // Find the smallest available block >= target order
        let mut found_order = None;
        for order in target_order..self.free_lists.len() {
            if !self.free_lists[order].is_empty() {
                found_order = Some(order);
                break;
            }
        }

        let found_order = found_order?;
        let offset = self.free_lists[found_order].pop().unwrap();

        // Split down to target order
        let mut current_order = found_order;
        while current_order > target_order {
            current_order -= 1;
            let buddy_offset = offset + (self.min_block << current_order);
            self.free_lists[current_order].push(buddy_offset);
        }

        self.allocated.insert(offset, target_order);
        self.num_allocs += 1;
        Some(offset)
    }

    fn free(&mut self, offset: usize) {
        let Some(order) = self.allocated.remove(&offset) else {
            panic!("double free at offset {}", offset);
        };

        let mut current_offset = offset;
        let mut current_order = order;

        // Try to coalesce with buddy
        while current_order < self.free_lists.len() - 1 {
            let block_size = self.min_block << current_order;
            let buddy_offset = current_offset ^ block_size;

            // Check if buddy is in the free list at this order
            if let Some(pos) = self.free_lists[current_order]
                .iter()
                .position(|&o| o == buddy_offset)
            {
                self.free_lists[current_order].swap_remove(pos);
                current_offset = current_offset.min(buddy_offset);
                current_order += 1;
            } else {
                break;
            }
        }

        self.free_lists[current_order].push(current_offset);
        self.num_allocs -= 1;
    }

    fn block_size_at_order(&self, order: usize) -> usize {
        self.min_block << order
    }
}

impl fmt::Display for BuddyAllocator {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Buddy[{} bytes, {} allocs, free:", self.size, self.num_allocs)?;
        for (order, list) in self.free_lists.iter().enumerate() {
            if !list.is_empty() {
                write!(f, " {}x{}B", list.len(), self.block_size_at_order(order))?;
            }
        }
        write!(f, "]")
    }
}

// ── Pool Allocator ────────────────────────────────────────────────────────

struct PoolAllocator<T: Default + Clone> {
    objects: Vec<T>,
    free_indices: Vec<usize>,
    active: usize,
}

impl<T: Default + Clone> PoolAllocator<T> {
    fn new(capacity: usize) -> Self {
        let objects = vec![T::default(); capacity];
        let free_indices: Vec<usize> = (0..capacity).rev().collect();
        Self {
            objects,
            free_indices,
            active: 0,
        }
    }

    fn alloc(&mut self) -> Option<usize> {
        let index = self.free_indices.pop()?;
        self.active += 1;
        Some(index)
    }

    fn free(&mut self, index: usize) {
        self.objects[index] = T::default();
        self.free_indices.push(index);
        self.active -= 1;
    }

    fn get(&self, index: usize) -> &T {
        &self.objects[index]
    }

    fn get_mut(&mut self, index: usize) -> &mut T {
        &mut self.objects[index]
    }
}

fn main() {
    println!("Allocators — four strategies for different patterns:\n");

    // ── Bump allocator demo ───────────────────────────────────────────
    println!("1. Bump Allocator (arena) — compiler AST nodes:");
    let mut bump = BumpAllocator::new(4096);

    let layout8 = Layout::from_size_align(8, 8).unwrap();
    let layout24 = Layout::from_size_align(24, 8).unwrap();

    let offsets: Vec<usize> = (0..10)
        .map(|_| bump.alloc(layout24).unwrap())
        .collect();
    println!("   Allocated 10 AST nodes (24 bytes each): offsets {:?}", &offsets[..3]);
    println!("   {}", bump);

    // Allocate some more with different alignment
    let _ = bump.alloc(Layout::from_size_align(3, 1).unwrap());
    let aligned = bump.alloc(layout8).unwrap();
    println!("   After 3-byte + 8-byte alloc: 8-byte at offset {} (aligned: {})", aligned, aligned % 8 == 0);

    bump.reset();
    println!("   After reset: {}\n", bump);

    // ── Slab allocator demo ───────────────────────────────────────────
    println!("2. Slab Allocator — fixed-size kernel objects:");
    let mut slab = SlabAllocator::new(64, 16); // 64-byte slots, 16 slots

    let slots: Vec<usize> = (0..5).map(|_| slab.alloc().unwrap()).collect();
    println!("   Allocated 5 slots: {:?}", slots);
    println!("   {}", slab);

    // Free some slots
    slab.free(slots[1]);
    slab.free(slots[3]);
    println!("   Freed slots 1 and 3");
    println!("   {}", slab);

    // Reallocate — should reuse freed slots
    let reused1 = slab.alloc().unwrap();
    let reused2 = slab.alloc().unwrap();
    println!("   Reallocated: got slots {} and {} (reused)", reused1, reused2);
    println!("   {}\n", slab);

    // ── Buddy allocator demo ──────────────────────────────────────────
    println!("3. Buddy Allocator — page frame allocation:");
    let mut buddy = BuddyAllocator::new(1024, 64); // 1KB total, 64-byte min block
    println!("   Initial: {}", buddy);

    let a = buddy.alloc(100).unwrap(); // needs 128 bytes (order 1)
    println!("   alloc(100) → offset {} (128B block), {}", a, buddy);

    let b = buddy.alloc(64).unwrap(); // needs 64 bytes (order 0)
    println!("   alloc(64)  → offset {} (64B block), {}", b, buddy);

    let c = buddy.alloc(200).unwrap(); // needs 256 bytes (order 2)
    println!("   alloc(200) → offset {} (256B block), {}", c, buddy);

    buddy.free(a);
    println!("   free({})   → {}", a, buddy);

    buddy.free(b);
    println!("   free({})   → {} (coalesced!)", b, buddy);

    buddy.free(c);
    println!("   free({})   → {} (fully coalesced)", c, buddy);

    // ── Pool allocator demo ───────────────────────────────────────────
    println!("\n4. Pool Allocator — connection objects:");
    let mut pool = PoolAllocator::<[u8; 32]>::new(8);

    let c1 = pool.alloc().unwrap();
    let c2 = pool.alloc().unwrap();
    pool.get_mut(c1)[0] = 0xAA;
    pool.get_mut(c2)[0] = 0xBB;
    println!("   conn1[0] = 0x{:02X}, conn2[0] = 0x{:02X}", pool.get(c1)[0], pool.get(c2)[0]);
    println!("   Active: {}", pool.active);

    pool.free(c1);
    let c3 = pool.alloc().unwrap(); // reuses c1's slot
    println!("   After free+realloc: new slot {} (reused), value = 0x{:02X} (zeroed)",
        c3, pool.get(c3)[0]);

    println!("\nAllocator selection guide:");
    println!("  Batch alloc, batch free → Bump/Arena");
    println!("  Fixed-size objects      → Slab");
    println!("  Variable-size, coalesce → Buddy");
    println!("  Known max count, reuse  → Pool");
}
