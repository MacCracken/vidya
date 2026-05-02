// Vidya — Render Graph Architecture in Rust
//
// Tiny DAG framework: passes declare reads/writes as bitmasks; the
// graph derives execution order, barrier count, and dead-pass culling.

const PASS_CAP: usize = 16;

struct Graph {
    pass_id: [u64; PASS_CAP],
    reads: [u64; PASS_CAP],
    writes: [u64; PASS_CAP],
    count: usize,
    topo_order: [usize; PASS_CAP],
    topo_len: usize,
}

impl Graph {
    fn new() -> Self {
        Graph {
            pass_id: [0; PASS_CAP],
            reads: [0; PASS_CAP],
            writes: [0; PASS_CAP],
            count: 0,
            topo_order: [0; PASS_CAP],
            topo_len: 0,
        }
    }

    fn add_pass(&mut self, id: u64, reads: u64, writes: u64) -> i32 {
        if self.count >= PASS_CAP { return -1; }
        let idx = self.count;
        self.pass_id[idx] = id;
        self.reads[idx] = reads;
        self.writes[idx] = writes;
        self.count += 1;
        idx as i32
    }

    fn has_edge(&self, producer: usize, consumer: usize) -> bool {
        (self.writes[producer] & self.reads[consumer]) != 0
    }

    fn topo_sort(&mut self) -> usize {
        let mut in_degree = [0i32; PASS_CAP];
        for i in 0..self.count {
            for j in 0..self.count {
                if i != j && self.has_edge(j, i) {
                    in_degree[i] += 1;
                }
            }
        }
        self.topo_len = 0;
        let mut emitted = 0;
        while emitted < self.count {
            let mut picked: Option<usize> = None;
            for k in 0..self.count {
                if in_degree[k] == 0 {
                    picked = Some(k);
                    break;
                }
            }
            let p = match picked {
                Some(p) => p,
                None => return self.topo_len,
            };
            self.topo_order[self.topo_len] = p;
            self.topo_len += 1;
            in_degree[p] = -1;
            for c in 0..self.count {
                if c != p && self.has_edge(p, c) && in_degree[c] > 0 {
                    in_degree[c] -= 1;
                }
            }
            emitted += 1;
        }
        self.topo_len
    }

    fn barrier_count(&self) -> usize {
        let mut count = 0;
        for i in 0..self.topo_len {
            for j in (i + 1)..self.topo_len {
                if self.has_edge(self.topo_order[i], self.topo_order[j]) {
                    count += 1;
                }
            }
        }
        count
    }

    fn cull_dead(&mut self) -> usize {
        let mut culled = 0;
        for i in 0..self.count {
            let w = self.writes[i];
            if w != 0 {
                let mut any_reader = false;
                for j in 0..self.count {
                    if i != j && (w & self.reads[j]) != 0 {
                        any_reader = true;
                    }
                }
                if !any_reader {
                    self.writes[i] = 0;
                    self.reads[i] = 0;
                    culled += 1;
                }
            }
        }
        culled
    }
}

fn main() {
    let mut g = Graph::new();

    // 1: linear A→B→C with R1=bit 0, R2=bit 1
    let a = g.add_pass(100, 0, 1);
    let b = g.add_pass(101, 1, 2);
    let c = g.add_pass(102, 2, 0);
    assert_eq!(a, 0); assert_eq!(b, 1); assert_eq!(c, 2);

    // 2: topo
    let n = g.topo_sort();
    assert_eq!(n, 3);
    assert_eq!(g.topo_order[0], 0);
    assert_eq!(g.topo_order[1], 1);
    assert_eq!(g.topo_order[2], 2);

    // 3: barriers
    assert_eq!(g.barrier_count(), 2);

    // 4: cull dead
    let d = g.add_pass(103, 0, 4);
    assert_eq!(d, 3);
    assert_eq!(g.cull_dead(), 1);
    assert_eq!(g.writes[3], 0);
    let n2 = g.topo_sort();
    assert_eq!(n2, 4);
    assert_eq!(g.barrier_count(), 2);

    // 5: cycle detection
    let mut g2 = Graph::new();
    g2.add_pass(200, 1, 2);
    g2.add_pass(201, 2, 1);
    assert_eq!(g2.topo_sort(), 0);

    println!("render_graph_architecture: 14/14 ok");
}
