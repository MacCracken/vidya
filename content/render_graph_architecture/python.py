# Vidya — Render Graph Architecture in Python
#
# Tiny DAG: passes with reads/writes bitmasks → topo sort + barriers
# + dead-pass culling.

PASS_CAP = 16


class Graph:
    def __init__(self):
        self.pass_id = [0] * PASS_CAP
        self.reads = [0] * PASS_CAP
        self.writes = [0] * PASS_CAP
        self.count = 0
        self.topo_order = [0] * PASS_CAP
        self.topo_len = 0

    def add_pass(self, id, reads, writes):
        if self.count >= PASS_CAP:
            return -1
        idx = self.count
        self.pass_id[idx] = id
        self.reads[idx] = reads
        self.writes[idx] = writes
        self.count += 1
        return idx

    def has_edge(self, producer, consumer):
        return (self.writes[producer] & self.reads[consumer]) != 0

    def topo_sort(self):
        in_degree = [0] * PASS_CAP
        for i in range(self.count):
            for j in range(self.count):
                if i != j and self.has_edge(j, i):
                    in_degree[i] += 1
        self.topo_len = 0
        emitted = 0
        while emitted < self.count:
            picked = -1
            for k in range(self.count):
                if in_degree[k] == 0:
                    picked = k
                    break
            if picked < 0:
                return self.topo_len
            self.topo_order[self.topo_len] = picked
            self.topo_len += 1
            in_degree[picked] = -1
            for c in range(self.count):
                if c != picked and self.has_edge(picked, c) and in_degree[c] > 0:
                    in_degree[c] -= 1
            emitted += 1
        return self.topo_len

    def barrier_count(self):
        count = 0
        for i in range(self.topo_len):
            for j in range(i + 1, self.topo_len):
                if self.has_edge(self.topo_order[i], self.topo_order[j]):
                    count += 1
        return count

    def cull_dead(self):
        culled = 0
        for i in range(self.count):
            w = self.writes[i]
            if w != 0:
                any_reader = any(
                    i != j and (w & self.reads[j]) != 0
                    for j in range(self.count)
                )
                if not any_reader:
                    self.writes[i] = 0
                    self.reads[i] = 0
                    culled += 1
        return culled


def main():
    g = Graph()

    a = g.add_pass(100, 0, 1)
    b = g.add_pass(101, 1, 2)
    c = g.add_pass(102, 2, 0)
    assert a == 0 and b == 1 and c == 2

    assert g.topo_sort() == 3
    assert g.topo_order[0] == 0
    assert g.topo_order[1] == 1
    assert g.topo_order[2] == 2

    assert g.barrier_count() == 2

    d = g.add_pass(103, 0, 4)
    assert d == 3
    assert g.cull_dead() == 1
    assert g.writes[3] == 0
    assert g.topo_sort() == 4
    assert g.barrier_count() == 2

    g2 = Graph()
    g2.add_pass(200, 1, 2)
    g2.add_pass(201, 2, 1)
    assert g2.topo_sort() == 0

    print("render_graph_architecture: 14/14 ok")


main()
