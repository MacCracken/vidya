/* Vidya — Render Graph Architecture in C
 *
 * Tiny DAG: reads/writes bitmasks → topo sort + barriers + cull.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define PASS_CAP 16

typedef struct {
    uint64_t pass_id[PASS_CAP];
    uint64_t reads[PASS_CAP];
    uint64_t writes[PASS_CAP];
    int count;
    int topo_order[PASS_CAP];
    int topo_len;
} Graph;

static void graph_init(Graph *g) { memset(g, 0, sizeof *g); }

static int add_pass(Graph *g, uint64_t id, uint64_t r, uint64_t w) {
    if (g->count >= PASS_CAP) return -1;
    int idx = g->count++;
    g->pass_id[idx] = id;
    g->reads[idx] = r;
    g->writes[idx] = w;
    return idx;
}

static int has_edge(const Graph *g, int p, int c) {
    return (g->writes[p] & g->reads[c]) != 0;
}

static int topo_sort(Graph *g) {
    int in_degree[PASS_CAP] = {0};
    for (int i = 0; i < g->count; i++)
        for (int j = 0; j < g->count; j++)
            if (i != j && has_edge(g, j, i)) in_degree[i]++;
    g->topo_len = 0;
    int emitted = 0;
    while (emitted < g->count) {
        int picked = -1;
        for (int k = 0; k < g->count; k++) {
            if (in_degree[k] == 0) { picked = k; break; }
        }
        if (picked < 0) return g->topo_len;
        g->topo_order[g->topo_len++] = picked;
        in_degree[picked] = -1;
        for (int c = 0; c < g->count; c++) {
            if (c != picked && has_edge(g, picked, c) && in_degree[c] > 0) {
                in_degree[c]--;
            }
        }
        emitted++;
    }
    return g->topo_len;
}

static int barrier_count(const Graph *g) {
    int count = 0;
    for (int i = 0; i < g->topo_len; i++)
        for (int j = i + 1; j < g->topo_len; j++)
            if (has_edge(g, g->topo_order[i], g->topo_order[j])) count++;
    return count;
}

static int cull_dead(Graph *g) {
    int culled = 0;
    for (int i = 0; i < g->count; i++) {
        uint64_t w = g->writes[i];
        if (w == 0) continue;
        int any_reader = 0;
        for (int j = 0; j < g->count; j++) {
            if (i != j && (w & g->reads[j]) != 0) { any_reader = 1; break; }
        }
        if (!any_reader) {
            g->writes[i] = 0;
            g->reads[i] = 0;
            culled++;
        }
    }
    return culled;
}

int main(void) {
    Graph g;
    graph_init(&g);

    int a = add_pass(&g, 100, 0, 1);
    int b = add_pass(&g, 101, 1, 2);
    int c = add_pass(&g, 102, 2, 0);
    assert(a == 0 && b == 1 && c == 2);

    assert(topo_sort(&g) == 3);
    assert(g.topo_order[0] == 0);
    assert(g.topo_order[1] == 1);
    assert(g.topo_order[2] == 2);

    assert(barrier_count(&g) == 2);

    int d = add_pass(&g, 103, 0, 4);
    assert(d == 3);
    assert(cull_dead(&g) == 1);
    assert(g.writes[3] == 0);
    assert(topo_sort(&g) == 4);
    assert(barrier_count(&g) == 2);

    Graph g2;
    graph_init(&g2);
    add_pass(&g2, 200, 1, 2);
    add_pass(&g2, 201, 2, 1);
    assert(topo_sort(&g2) == 0);

    printf("render_graph_architecture: 14/14 ok\n");
    return 0;
}
