// Vidya — Bindless Resources in Rust
//
// In-memory descriptor table — "one global table per frame" pattern.
// Slot 0 reserved as null sentinel; LIFO free list for reuse.

const TABLE_CAP: usize = 64;

struct DescriptorTable {
    slots: [u64; TABLE_CAP],
    free_links: [u32; TABLE_CAP],
    next_id: u32,
    free_head: u32,
}

impl DescriptorTable {
    fn new() -> Self {
        DescriptorTable {
            slots: [0; TABLE_CAP],
            free_links: [0; TABLE_CAP],
            next_id: 1,
            free_head: 0,
        }
    }

    fn alloc(&mut self, desc: u64) -> u32 {
        if self.free_head != 0 {
            let id = self.free_head;
            self.free_head = self.free_links[id as usize];
            self.slots[id as usize] = desc;
            return id;
        }
        if self.next_id as usize >= TABLE_CAP { return 0; }
        let id = self.next_id;
        self.next_id += 1;
        self.slots[id as usize] = desc;
        id
    }

    fn lookup(&self, id: u32) -> u64 {
        if id == 0 || id as usize >= TABLE_CAP { return 0; }
        self.slots[id as usize]
    }

    fn update(&mut self, id: u32, desc: u64) -> bool {
        if id == 0 || id as usize >= TABLE_CAP { return false; }
        self.slots[id as usize] = desc;
        true
    }

    fn free(&mut self, id: u32) -> bool {
        if id == 0 || id as usize >= TABLE_CAP { return false; }
        self.free_links[id as usize] = self.free_head;
        self.free_head = id;
        self.slots[id as usize] = 0;
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
    t.free(id2);
    assert_eq!(t.lookup(id2), 0);
    let id4 = t.alloc(0x4444_4444_4444_4444);
    assert_eq!(id4, id2);
    assert_eq!(t.lookup(id4), 0x4444_4444_4444_4444);

    // 6: exhaustion
    let mut t2 = DescriptorTable::new();
    for i in 1..(TABLE_CAP as u64) {
        t2.alloc(i);
    }
    assert_eq!(t2.alloc(0xDEAD_BEEF), 0);

    println!("bindless_resources: 15/15 ok");
}
