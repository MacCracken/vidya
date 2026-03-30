// Vidya — Concurrency in C
//
// C concurrency uses POSIX threads (pthreads). You manage thread
// creation, mutexes, condition variables, and atomic operations
// manually. No runtime, no garbage collector — you control everything.

#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ── Thread function: computes sum of a range ───────────────────────

typedef struct {
    int start;
    int end;
    long result;
} SumTask;

void *sum_range(void *arg) {
    SumTask *task = (SumTask *)arg;
    long sum = 0;
    for (int i = task->start; i < task->end; i++) {
        sum += i;
    }
    task->result = sum;
    return NULL;
}

// ── Mutex-protected shared counter ─────────────────────────────────

typedef struct {
    pthread_mutex_t lock;
    int count;
} Counter;

void counter_init(Counter *c) {
    pthread_mutex_init(&c->lock, NULL);
    c->count = 0;
}

void counter_increment(Counter *c, int times) {
    for (int i = 0; i < times; i++) {
        pthread_mutex_lock(&c->lock);
        c->count++;
        pthread_mutex_unlock(&c->lock);
    }
}

void counter_destroy(Counter *c) {
    pthread_mutex_destroy(&c->lock);
}

typedef struct {
    Counter *counter;
    int times;
} CounterTask;

void *counter_worker(void *arg) {
    CounterTask *task = (CounterTask *)arg;
    counter_increment(task->counter, task->times);
    return NULL;
}

// ── Producer-consumer with condition variable ──────────────────────

#define QUEUE_SIZE 8

typedef struct {
    int data[QUEUE_SIZE];
    int head;
    int tail;
    int count;
    pthread_mutex_t lock;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
} Queue;

void queue_init(Queue *q) {
    q->head = 0;
    q->tail = 0;
    q->count = 0;
    pthread_mutex_init(&q->lock, NULL);
    pthread_cond_init(&q->not_empty, NULL);
    pthread_cond_init(&q->not_full, NULL);
}

void queue_push(Queue *q, int value) {
    pthread_mutex_lock(&q->lock);
    while (q->count == QUEUE_SIZE) {
        pthread_cond_wait(&q->not_full, &q->lock);
    }
    q->data[q->tail] = value;
    q->tail = (q->tail + 1) % QUEUE_SIZE;
    q->count++;
    pthread_cond_signal(&q->not_empty);
    pthread_mutex_unlock(&q->lock);
}

int queue_pop(Queue *q) {
    pthread_mutex_lock(&q->lock);
    while (q->count == 0) {
        pthread_cond_wait(&q->not_empty, &q->lock);
    }
    int value = q->data[q->head];
    q->head = (q->head + 1) % QUEUE_SIZE;
    q->count--;
    pthread_cond_signal(&q->not_full);
    pthread_mutex_unlock(&q->lock);
    return value;
}

void queue_destroy(Queue *q) {
    pthread_mutex_destroy(&q->lock);
    pthread_cond_destroy(&q->not_empty);
    pthread_cond_destroy(&q->not_full);
}

typedef struct {
    Queue *queue;
    int count;
} ProducerTask;

void *producer(void *arg) {
    ProducerTask *task = (ProducerTask *)arg;
    for (int i = 0; i < task->count; i++) {
        queue_push(task->queue, i * i);
    }
    return NULL;
}

int main(void) {
    // ── Basic thread creation and join ──────────────────────────────
    SumTask task = {.start = 0, .end = 100};
    pthread_t thread;
    int rc = pthread_create(&thread, NULL, sum_range, &task);
    assert(rc == 0);

    rc = pthread_join(thread, NULL);
    assert(rc == 0);
    assert(task.result == 4950);

    // ── Parallel computation with multiple threads ─────────────────
    #define NUM_THREADS 4
    SumTask tasks[NUM_THREADS];
    pthread_t threads[NUM_THREADS];
    int per_thread = 10000 / NUM_THREADS;

    for (int i = 0; i < NUM_THREADS; i++) {
        tasks[i].start = i * per_thread;
        tasks[i].end = (i + 1) * per_thread;
        pthread_create(&threads[i], NULL, sum_range, &tasks[i]);
    }

    long total = 0;
    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
        total += tasks[i].result;
    }
    assert(total == 49995000); // sum of 0..9999

    // ── Mutex: protecting shared state ─────────────────────────────
    Counter counter;
    counter_init(&counter);

    CounterTask ctasks[4];
    pthread_t cthreads[4];
    for (int i = 0; i < 4; i++) {
        ctasks[i].counter = &counter;
        ctasks[i].times = 1000;
        pthread_create(&cthreads[i], NULL, counter_worker, &ctasks[i]);
    }
    for (int i = 0; i < 4; i++) {
        pthread_join(cthreads[i], NULL);
    }
    assert(counter.count == 4000);
    counter_destroy(&counter);

    // ── Atomic operations: lock-free counter ───────────────────────
    atomic_int atom_counter = 0;

    // In a real program, you'd use atomics from multiple threads.
    // Here we demonstrate the API:
    atomic_fetch_add(&atom_counter, 10);
    assert(atomic_load(&atom_counter) == 10);
    atomic_fetch_sub(&atom_counter, 3);
    assert(atomic_load(&atom_counter) == 7);

    // ── Producer-consumer queue ────────────────────────────────────
    Queue queue;
    queue_init(&queue);

    ProducerTask ptask = {.queue = &queue, .count = 5};
    pthread_t prod_thread;
    pthread_create(&prod_thread, NULL, producer, &ptask);

    int results[5];
    for (int i = 0; i < 5; i++) {
        results[i] = queue_pop(&queue);
    }
    pthread_join(prod_thread, NULL);

    assert(results[0] == 0);
    assert(results[1] == 1);
    assert(results[2] == 4);
    assert(results[3] == 9);
    assert(results[4] == 16);
    queue_destroy(&queue);

    printf("All concurrency examples passed.\n");
    return 0;
}
