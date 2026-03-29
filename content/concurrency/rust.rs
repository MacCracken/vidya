// Vidya — Concurrency in Rust
//
// Rust prevents data races at compile time through Send/Sync traits
// and the ownership system. Threads, channels, mutexes, and atomics
// are all available — but the compiler ensures you use them correctly.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;

fn main() {
    // ── Spawning threads ───────────────────────────────────────────
    let handle = thread::spawn(|| {
        let mut sum = 0u64;
        for i in 0..100 {
            sum += i;
        }
        sum
    });

    let result = handle.join().expect("thread panicked");
    assert_eq!(result, 4950);

    // ── Scoped threads: borrow from the parent stack ───────────────
    let data = vec![1, 2, 3, 4, 5, 6, 7, 8];

    // No Arc needed — scoped threads can borrow &data directly
    let sum = thread::scope(|s| {
        let (left, right) = data.split_at(data.len() / 2);

        let handle_l = s.spawn(|| left.iter().sum::<i32>());
        let handle_r = s.spawn(|| right.iter().sum::<i32>());

        handle_l.join().unwrap() + handle_r.join().unwrap()
    });
    assert_eq!(sum, 36);

    // ── Channels: message passing ──────────────────────────────────
    let (tx, rx) = mpsc::channel();

    thread::spawn(move || {
        for i in 0..5 {
            tx.send(i * i).expect("receiver dropped");
        }
    });

    let squares: Vec<i32> = rx.iter().collect();
    assert_eq!(squares, vec![0, 1, 4, 9, 16]);

    // ── Multiple producers ─────────────────────────────────────────
    let (tx, rx) = mpsc::channel();

    for id in 0..3 {
        let tx = tx.clone();
        thread::spawn(move || {
            tx.send(id).expect("receiver dropped");
        });
    }
    drop(tx); // drop original sender so rx.iter() terminates

    let mut received: Vec<i32> = rx.iter().collect();
    received.sort();
    assert_eq!(received, vec![0, 1, 2]);

    // ── Mutex: shared mutable state ────────────────────────────────
    let counter = Arc::new(Mutex::new(0u64));

    thread::scope(|s| {
        for _ in 0..4 {
            let counter = Arc::clone(&counter);
            s.spawn(move || {
                for _ in 0..1000 {
                    let mut guard = counter.lock().unwrap();
                    *guard += 1;
                    // guard is dropped here — lock released
                }
            });
        }
    });

    assert_eq!(*counter.lock().unwrap(), 4000);

    // ── Atomics: lock-free shared state ────────────────────────────
    let counter = Arc::new(AtomicU64::new(0));

    thread::scope(|s| {
        for _ in 0..4 {
            let counter = Arc::clone(&counter);
            s.spawn(move || {
                for _ in 0..1000 {
                    counter.fetch_add(1, Ordering::Relaxed);
                }
            });
        }
    });

    assert_eq!(counter.load(Ordering::Relaxed), 4000);

    // ── Best practice: hold locks briefly ──────────────────────────
    let shared = Arc::new(Mutex::new(vec![1, 2, 3]));

    // GOOD: lock, copy what you need, unlock
    let snapshot = {
        let guard = shared.lock().unwrap();
        guard.clone() // clone under lock, then drop guard
    };
    // Now work with snapshot without holding the lock
    assert_eq!(snapshot.iter().sum::<i32>(), 6);

    // ── Thread-safe types: Send + Sync ─────────────────────────────
    // These compile because the types are Send:
    fn assert_send<T: Send>() {}
    fn assert_sync<T: Sync>() {}

    assert_send::<Arc<Mutex<Vec<i32>>>>();
    assert_sync::<Arc<Mutex<Vec<i32>>>>();
    assert_send::<String>();
    assert_sync::<String>();

    // Rc is NOT Send — this wouldn't compile:
    // assert_send::<std::rc::Rc<i32>>(); // error!

    println!("All concurrency examples passed.");
}
