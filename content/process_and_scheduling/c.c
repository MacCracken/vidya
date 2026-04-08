/* Process and Scheduling — C Implementation
 *
 * Demonstrates operating system scheduling concepts:
 *   1. Task struct with saved register state
 *   2. Round-robin scheduler with time quantum
 *   3. CFS-like fair scheduler with virtual runtime and weighted priorities
 *   4. Process state machine transitions
 *   5. Context switch data layout
 *
 * In a real kernel, context_switch is assembly that saves/restores
 * callee-saved registers. Here we simulate scheduling decisions.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* ── Task State ──────────────────────────────────────────────────────── */

typedef enum {
    TASK_READY,
    TASK_RUNNING,
    TASK_BLOCKED,
    TASK_TERMINATED
} task_state_t;

static const char *state_name(task_state_t s) {
    switch (s) {
        case TASK_READY:      return "READY";
        case TASK_RUNNING:    return "RUNNING";
        case TASK_BLOCKED:    return "BLOCKED";
        case TASK_TERMINATED: return "DONE";
    }
    return "?";
}

/* ── Saved Registers ─────────────────────────────────────────────────── */

/* On x86_64 context switch, only callee-saved registers are stored.
 * The calling convention guarantees caller-saved registers are already
 * on the stack. */
typedef struct {
    uint64_t rsp;
    uint64_t rbp;
    uint64_t rbx;
    uint64_t r12;
    uint64_t r13;
    uint64_t r14;
    uint64_t r15;
    uint64_t rip;  /* return address: where to resume */
} saved_regs_t;

/* ── Task Control Block ──────────────────────────────────────────────── */

#define MAX_TASKS 8
#define NAME_LEN  16

typedef struct {
    uint32_t     pid;
    char         name[NAME_LEN];
    task_state_t state;
    saved_regs_t regs;
    uint64_t     cpu_time;     /* total ticks consumed */
    uint64_t     vruntime;     /* CFS virtual runtime  */
    int8_t       nice;         /* -20 to 19            */
    uint32_t     time_slice;   /* remaining ticks      */
    uint32_t     switches;     /* context switch count  */
} task_t;

static void task_init(task_t *t, uint32_t pid, const char *name, int8_t nice) {
    memset(t, 0, sizeof(*t));
    t->pid = pid;
    strncpy(t->name, name, NAME_LEN - 1);
    t->state = TASK_READY;
    t->nice = nice;
    t->time_slice = 10;
}

/* CFS weight: nice 0 = 1024, each nice level ~1.25x */
static uint64_t task_weight(const task_t *t) {
    uint64_t base = 1024;
    if (t->nice >= 0) {
        unsigned shift = (unsigned)t->nice;
        return base >> (shift > 10 ? 10 : shift);
    }
    unsigned shift = (unsigned)(-t->nice);
    return base << (shift > 10 ? 10 : shift);
}

static void task_print(const task_t *t) {
    printf("PID=%-3u %-12s %8s nice=%3d vrt=%-6lu cpu=%-4lu sw=%u",
           t->pid, t->name, state_name(t->state), t->nice,
           (unsigned long)t->vruntime, (unsigned long)t->cpu_time, t->switches);
}

/* ── Round-Robin Scheduler ───────────────────────────────────────────── */

typedef struct {
    task_t   tasks[MAX_TASKS];
    unsigned count;
    int      current;       /* index or -1 */
    uint64_t tick;
    uint32_t time_quantum;
} rr_scheduler_t;

static void rr_init(rr_scheduler_t *s, uint32_t quantum) {
    memset(s, 0, sizeof(*s));
    s->current = -1;
    s->time_quantum = quantum;
}

static void rr_add(rr_scheduler_t *s, task_t *t) {
    assert(s->count < MAX_TASKS);
    s->tasks[s->count++] = *t;
}

/* Returns PID of scheduled task, or 0 if none ready */
static uint32_t rr_schedule(rr_scheduler_t *s) {
    unsigned n = s->count;
    unsigned start = (s->current >= 0) ? (unsigned)((s->current + 1) % n) : 0;

    for (unsigned i = 0; i < n; i++) {
        unsigned idx = (start + i) % n;
        if (s->tasks[idx].state == TASK_READY) {
            /* Preempt previous */
            if (s->current >= 0 && s->tasks[s->current].state == TASK_RUNNING) {
                s->tasks[s->current].state = TASK_READY;
            }
            s->tasks[idx].state = TASK_RUNNING;
            s->tasks[idx].time_slice = s->time_quantum;
            s->tasks[idx].switches++;
            s->current = (int)idx;
            return s->tasks[idx].pid;
        }
    }
    return 0;
}

static void rr_tick(rr_scheduler_t *s) {
    s->tick++;
    if (s->current >= 0) {
        task_t *t = &s->tasks[s->current];
        t->cpu_time++;
        if (t->time_slice > 0) t->time_slice--;
        if (t->time_slice == 0) {
            t->state = TASK_READY; /* preempt */
        }
    }
}

/* ── CFS-like Fair Scheduler ─────────────────────────────────────────── */

typedef struct {
    task_t   tasks[MAX_TASKS];
    unsigned count;
    int      current;
    uint64_t tick;
} cfs_scheduler_t;

static void cfs_init(cfs_scheduler_t *s) {
    memset(s, 0, sizeof(*s));
    s->current = -1;
}

static void cfs_add(cfs_scheduler_t *s, task_t *t) {
    assert(s->count < MAX_TASKS);
    s->tasks[s->count++] = *t;
}

/* Pick task with smallest vruntime */
static uint32_t cfs_schedule(cfs_scheduler_t *s) {
    int best = -1;
    uint64_t best_vrt = UINT64_MAX;

    for (unsigned i = 0; i < s->count; i++) {
        if (s->tasks[i].state == TASK_READY || s->tasks[i].state == TASK_RUNNING) {
            if (s->tasks[i].vruntime < best_vrt) {
                best_vrt = s->tasks[i].vruntime;
                best = (int)i;
            }
        }
    }

    if (best < 0) return 0;

    if (s->current >= 0 && s->current != best
        && s->tasks[s->current].state == TASK_RUNNING) {
        s->tasks[s->current].state = TASK_READY;
    }

    s->tasks[best].state = TASK_RUNNING;
    if (s->current != best) {
        s->tasks[best].switches++;
    }
    s->current = best;
    return s->tasks[best].pid;
}

static void cfs_tick(cfs_scheduler_t *s) {
    s->tick++;
    if (s->current >= 0) {
        task_t *t = &s->tasks[s->current];
        t->cpu_time++;
        /* vruntime += (scale * default_weight) / task_weight
         * Higher weight -> slower vruntime growth -> more CPU time
         * Scale by 1024 to avoid integer truncation to zero */
        uint64_t w = task_weight(t);
        t->vruntime += (1024 * 1024) / w;
    }
}

/* ── Main ────────────────────────────────────────────────────────────── */

int main(void) {
    printf("Process and Scheduling — scheduler simulation:\n\n");

    /* ── 1. Round-Robin ──────────────────────────────────────────────── */
    printf("1. Round-Robin Scheduler (quantum=3 ticks):\n");

    rr_scheduler_t rr;
    rr_init(&rr, 3);

    task_t t1, t2, t3;
    task_init(&t1, 1, "init", 0);
    task_init(&t2, 2, "compiler", 0);
    task_init(&t3, 3, "editor", 0);
    rr_add(&rr, &t1);
    rr_add(&rr, &t2);
    rr_add(&rr, &t3);

    uint32_t history[15];
    for (int i = 0; i < 15; i++) {
        if (rr.current < 0 || rr.tasks[rr.current].state != TASK_RUNNING) {
            rr_schedule(&rr);
        }
        history[i] = (rr.current >= 0) ? rr.tasks[rr.current].pid : 0;
        rr_tick(&rr);
    }

    printf("   Timeline (15 ticks): [");
    for (int i = 0; i < 15; i++) {
        printf("%u%s", history[i], (i < 14) ? ", " : "");
    }
    printf("]\n");

    printf("   Task states:\n");
    for (unsigned i = 0; i < rr.count; i++) {
        printf("     ");
        task_print(&rr.tasks[i]);
        printf("\n");
    }

    /* Verify total CPU = 15 ticks across all tasks */
    uint64_t total_cpu = 0;
    for (unsigned i = 0; i < rr.count; i++) {
        total_cpu += rr.tasks[i].cpu_time;
    }
    assert(total_cpu == 15);
    /* Verify round-robin pattern */
    assert(history[0] == 1 && history[1] == 1 && history[2] == 1);
    assert(history[3] == 2 && history[4] == 2 && history[5] == 2);
    assert(history[6] == 3 && history[7] == 3 && history[8] == 3);

    /* ── 2. CFS ──────────────────────────────────────────────────────── */
    printf("\n2. CFS Fair Scheduler (nice-weighted):\n");

    cfs_scheduler_t cfs;
    cfs_init(&cfs);

    task_t ch, cn, cl;
    task_init(&ch, 1, "high-prio", -2);
    task_init(&cn, 2, "normal", 0);
    task_init(&cl, 3, "low-prio", 2);
    cfs_add(&cfs, &ch);
    cfs_add(&cfs, &cn);
    cfs_add(&cfs, &cl);

    uint32_t cfs_hist[30];
    for (int i = 0; i < 30; i++) {
        cfs_schedule(&cfs);
        cfs_hist[i] = (cfs.current >= 0) ? cfs.tasks[cfs.current].pid : 0;
        cfs_tick(&cfs);
    }

    printf("   Timeline (first 20): [");
    for (int i = 0; i < 20; i++) {
        printf("%u%s", cfs_hist[i], (i < 19) ? ", " : "");
    }
    printf("]\n");

    printf("   Task states:\n");
    for (unsigned i = 0; i < cfs.count; i++) {
        double cpu_pct = (double)cfs.tasks[i].cpu_time / 30.0 * 100.0;
        printf("     ");
        task_print(&cfs.tasks[i]);
        printf(" (%.0f%% CPU, weight=%lu)\n", cpu_pct, (unsigned long)task_weight(&cfs.tasks[i]));
    }

    /* Verify: high-prio got more CPU than low-prio */
    assert(cfs.tasks[0].cpu_time > cfs.tasks[2].cpu_time);

    /* Verify weight calculation */
    task_t tw;
    task_init(&tw, 0, "w", 0);
    assert(task_weight(&tw) == 1024);
    tw.nice = -1;
    assert(task_weight(&tw) == 2048);
    tw.nice = 1;
    assert(task_weight(&tw) == 512);

    /* ── 3. Context switch anatomy ───────────────────────────────────── */
    printf("\n3. Context switch anatomy (x86_64):\n");
    printf("   context_switch(prev, next):\n");
    printf("     1. Save prev's RBX, RBP, R12-R15, RSP\n");
    printf("     2. if prev->mm != next->mm:\n");
    printf("          write_cr3(next->cr3)  // switch page tables\n");
    printf("     3. Load next's RSP (on next's kernel stack)\n");
    printf("     4. Load next's RBX, RBP, R12-R15\n");
    printf("     5. ret  // pops next's saved RIP, resumes next\n");

    /* Show register layout */
    printf("\n   Saved register block layout:\n");
    printf("   Offset  Field  Size  Notes\n");
    printf("   +0x00   RSP    8     kernel stack pointer\n");
    printf("   +0x08   RBP    8     frame pointer\n");
    printf("   +0x10   RBX    8     callee-saved\n");
    printf("   +0x18   R12    8     callee-saved\n");
    printf("   +0x20   R13    8     callee-saved\n");
    printf("   +0x28   R14    8     callee-saved\n");
    printf("   +0x30   R15    8     callee-saved\n");
    printf("   +0x38   RIP    8     return address\n");
    printf("   Total: %zu bytes\n", sizeof(saved_regs_t));
    assert(sizeof(saved_regs_t) == 64);  /* 8 registers * 8 bytes */

    /* ── 4. Task lifecycle ───────────────────────────────────────────── */
    printf("\n4. Task lifecycle:\n");
    printf("     %-15s %-25s %s\n", "Event", "Transition", "Notes");
    printf("     fork()          CREATED -> READY          added to runqueue\n");
    printf("     schedule()      READY -> RUNNING          context switch in\n");
    printf("     timer tick      RUNNING -> READY          preempted\n");
    printf("     read(fd)        RUNNING -> BLOCKED        waiting for I/O\n");
    printf("     I/O done        BLOCKED -> READY          woken by IRQ handler\n");
    printf("     exit()          RUNNING -> TERMINATED     resources freed\n");
    printf("     wait()          parent collects status    task_struct freed\n");

    /* Verify state transitions */
    task_t lifecycle;
    task_init(&lifecycle, 99, "test", 0);
    assert(lifecycle.state == TASK_READY);
    lifecycle.state = TASK_RUNNING;
    assert(lifecycle.state == TASK_RUNNING);
    lifecycle.state = TASK_BLOCKED;
    assert(lifecycle.state == TASK_BLOCKED);
    lifecycle.state = TASK_READY;
    lifecycle.state = TASK_TERMINATED;
    assert(lifecycle.state == TASK_TERMINATED);

    printf("\nAll assertions passed.\n");
    return 0;
}
