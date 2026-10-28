// Vidya — Bindless Resources in Rust
//
// In-memory descriptor table — "one global table per frame" pattern.
// Slot 0 reserved as null sentinel; LIFO free list for reuse.
//
// A handle is (generation << 8) | slot. Freeing a slot bumps its
// generation, so a handle kept past free() no longer matches and is
// rejected instead of silently reading whatever reuses the slot. A bare
// slot index cannot tell the two apart, and a double free would put the
// slot on the free list twice (two live allocations, one slot).

const TABLE_CAP: usize = 64;
const IDX_BITS: u32 = 8;
const IDX_MASK: u32 = (1 << IDX_BITS) - 1;
// 24 generation bits fit above the slot in a u32 handle. The counter
// wraps after 2^24 frees of one slot; a handle that old would alias.
const GEN_MASK: u32 = u32::MAX >> IDX_BITS;

struct DescriptorTable {
    slots: [u64; TABLE_CAP],
    free_links: [u32; TABLE_CAP],
    gens: [u32; TABLE_CAP],
    live: [bool; TABLE_CAP],
    next_id: u32,
    free_head: u32,
}

impl DescriptorTable {
    fn new() -> Self {
        DescriptorTable {
            slots: [0; TABLE_CAP],
            free_links: [0; TABLE_CAP],
            gens: [0; TABLE_CAP],
            live: [false; TABLE_CAP],
            next_id: 1,
            free_head: 0,
        }
    }

    fn handle(&self, i: u32) -> u32 {
        (self.gens[i as usize] << IDX_BITS) | i
    }

    /// Slot index for a live, current-generation handle, else None.
    fn live_index(&self, h: u32) -> Option<usize> {
        let i = (h & IDX_MASK) as usize;
        if i == 0 || i >= TABLE_CAP || !self.live[i] { return None; }
        // Stale: the slot was freed (and maybe reused) since h was issued.
        if h >> IDX_BITS != self.gens[i] { return None; }
        Some(i)
    }

    fn alloc(&mut self, desc: u64) -> u32 {
        let id = if self.free_head != 0 {
            let id = self.free_head;
            self.free_head = self.free_links[id as usize];
            id
        } else {
            if self.next_id as usize >= TABLE_CAP { return 0; }
            let id = self.next_id;
            self.next_id += 1;
            id
        };
        self.slots[id as usize] = desc;
        self.live[id as usize] = true;
        self.handle(id)
    }

    fn lookup(&self, h: u32) -> u64 {
        match self.live_index(h) {
            Some(i) => self.slots[i],
            None => 0,
        }
    }

    fn update(&mut self, h: u32, desc: u64) -> bool {
        let Some(i) = self.live_index(h) else { return false };
        self.slots[i] = desc;
        true
    }

    fn free(&mut self, h: u32) -> bool {
        let Some(i) = self.live_index(h) else { return false }; // null, stale or double free
        self.live[i] = false;
        self.gens[i] = (self.gens[i] + 1) & GEN_MASK;
        self.free_links[i] = self.free_head;
        self.free_head = i as u32;
        self.slots[i] = 0;
        true
    }
}

fn main() {
    let mut t = DescriptorTable::new();

    // 1: sequential alloc
    let id1 = t.alloc(0x1111_1111_1111_1111);
    let id2 = t.alloc(0x2222_2222_2222_2222);
    let id3 = t.alloc(0x3333_3333_3333_3333);
    assert_eq!(id1, 1);
    assert_eq!(id2, 2);
    assert_eq!(id3, 3);

    // 2: slot 0 reserved
    assert_eq!(t.lookup(0), 0);

    // 3: lookup
    assert_eq!(t.lookup(id1), 0x1111_1111_1111_1111);
    assert_eq!(t.lookup(id2), 0x2222_2222_2222_2222);
    assert_eq!(t.lookup(id3), 0x3333_3333_3333_3333);

    // 4: update
    assert!(t.update(id2, 0xAAAA_AAAA_AAAA_AAAA));
    assert_eq!(t.lookup(id2), 0xAAAA_AAAA_AAAA_AAAA);
    assert_eq!(t.lookup(id1), 0x1111_1111_1111_1111);
    assert_eq!(t.lookup(id3), 0x3333_3333_3333_3333);

    // 5: free + reuse
    assert!(t.free(id2));
    assert_eq!(t.lookup(id2), 0);
    let id4 = t.alloc(0x4444_4444_4444_4444);
    assert_eq!(id4 & IDX_MASK, id2 & IDX_MASK); // slot reused...
    assert_ne!(id4, id2);                       // ...under a new generation
    assert_eq!(t.lookup(id4), 0x4444_4444_4444_4444);
    assert_eq!(t.lookup(id2), 0);               // stale handle rejected
    assert!(!t.update(id2, 0xBAD));             // stale write rejected
    assert!(!t.free(id2));                      // double/stale free rejected
    assert!(!t.free(50));                       // never-allocated slot rejected

    // 6: exhaustion
    let mut t2 = DescriptorTable::new();
    for i in 1..(TABLE_CAP as u64) {
        t2.alloc(i);
    }
    assert_eq!(t2.alloc(0xDEAD_BEEF), 0);

    println!("bindless_resources: 21/21 ok");
}
