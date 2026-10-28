// Vidya — Concurrent File Access (flock) in Rust
//
// Single-process exercise of the file-lock state machine via two
// distinct OPENs of the same path. flock is per-OPEN, so the two fds
// have independent lock state and can contend with each other inside
// one process. Since Rust 1.89, std::fs::File has lock / lock_shared /
// try_lock / try_lock_shared / unlock, which on Unix are flock(2) — so
// this needs no unsafe FFI and no libc/nix dependency.

use std::fs::{OpenOptions, TryLockError};
use std::io::{Read, Seek, SeekFrom, Write};

fn main() {
    let path = "/tmp/vidya_cfa_rust.bin";
    let _ = std::fs::remove_file(path); // ignored on purpose: the file may not exist yet

    // --- Test 1: exclusive write ---
    let mut f1 = OpenOptions::new().read(true).write(true).create(true).open(path).unwrap();
    f1.lock().expect("fd1 LOCK_EX");

    let val: u64 = 0xDEAD_BEEF_1234_5678;
    f1.seek(SeekFrom::Start(0)).unwrap();
    f1.write_all(&val.to_le_bytes()).unwrap();
    f1.unlock().expect("fd1 LOCK_UN after write");

    // --- Test 2: shared read with roundtrip ---
    f1.lock_shared().expect("fd1 LOCK_SH");
    f1.seek(SeekFrom::Start(0)).unwrap();
    let mut buf = [0u8; 8];
    f1.read_exact(&mut buf).unwrap();
    assert_eq!(u64::from_le_bytes(buf), val, "data roundtrip");
    f1.unlock().unwrap();

    // --- Test 3: exclusive contention ---
    let f2 = OpenOptions::new().read(true).write(true).open(path).unwrap();
    f1.lock().expect("fd1 re-acquires LOCK_EX");
    assert!(matches!(f2.try_lock(), Err(TryLockError::WouldBlock)),
            "fd2 non-blocking exclusive blocked while fd1 holds");

    // --- Test 4: release fd1, fd2 can acquire ---
    f1.unlock().unwrap();
    f2.try_lock().expect("fd2 acquires after fd1 releases");
    f2.unlock().unwrap();

    // --- Test 5: shared locks coexist ---
    f1.try_lock_shared().expect("fd1 LOCK_SH non-blocking");
    f2.try_lock_shared().expect("fd2 LOCK_SH non-blocking coexists");

    f1.unlock().unwrap();
    f2.unlock().unwrap();
    drop(f1);
    drop(f2);
    std::fs::remove_file(path).unwrap();

    println!("concurrent_file_access: 12/12 ok");
}
