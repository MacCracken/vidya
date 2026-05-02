// Vidya — Concurrent File Access (flock) in Rust
//
// Single-process exercise of the file-lock state machine via two
// distinct OPENs of the same path. flock is per-OPEN, so the two fds
// have independent lock state and can contend with each other inside
// one process. We use raw libc::flock (no nix dep) to keep this port
// dependency-free.

use std::ffi::CString;
use std::fs::OpenOptions;
use std::io::{Read, Seek, SeekFrom, Write};
use std::os::unix::io::AsRawFd;

const LOCK_SH: i32 = 1;
const LOCK_EX: i32 = 2;
const LOCK_UN: i32 = 8;
const LOCK_NB: i32 = 4;

unsafe extern "C" {
    fn flock(fd: i32, op: i32) -> i32;
    fn unlink(path: *const u8) -> i32;
}

fn lock(fd: i32, op: i32) -> i32 {
    unsafe { flock(fd, op) }
}

fn main() {
    let path = "/tmp/vidya_cfa_rust.bin";
    let cpath = CString::new(path).unwrap();
    unsafe { unlink(cpath.as_ptr() as *const u8); }

    // --- Test 1: exclusive write ---
    let mut f1 = OpenOptions::new().read(true).write(true).create(true).open(path).unwrap();
    assert_eq!(lock(f1.as_raw_fd(), LOCK_EX), 0, "fd1 LOCK_EX");

    let val: u64 = 0xDEAD_BEEF_1234_5678;
    f1.seek(SeekFrom::Start(0)).unwrap();
    f1.write_all(&val.to_le_bytes()).unwrap();
    assert_eq!(lock(f1.as_raw_fd(), LOCK_UN), 0, "fd1 LOCK_UN after write");

    // --- Test 2: shared read with roundtrip ---
    assert_eq!(lock(f1.as_raw_fd(), LOCK_SH), 0, "fd1 LOCK_SH");
    f1.seek(SeekFrom::Start(0)).unwrap();
    let mut buf = [0u8; 8];
    f1.read_exact(&mut buf).unwrap();
    assert_eq!(u64::from_le_bytes(buf), val, "data roundtrip");
    lock(f1.as_raw_fd(), LOCK_UN);

    // --- Test 3: exclusive contention ---
    let f2 = OpenOptions::new().read(true).write(true).open(path).unwrap();
    assert_eq!(lock(f1.as_raw_fd(), LOCK_EX), 0, "fd1 re-acquires LOCK_EX");
    let nb = lock(f2.as_raw_fd(), LOCK_EX | LOCK_NB);
    assert!(nb < 0, "fd2 non-blocking exclusive blocked while fd1 holds");

    // --- Test 4: release fd1, fd2 can acquire ---
    lock(f1.as_raw_fd(), LOCK_UN);
    let nb2 = lock(f2.as_raw_fd(), LOCK_EX | LOCK_NB);
    assert_eq!(nb2, 0, "fd2 acquires after fd1 releases");
    lock(f2.as_raw_fd(), LOCK_UN);

    // --- Test 5: shared locks coexist ---
    assert_eq!(lock(f1.as_raw_fd(), LOCK_SH | LOCK_NB), 0, "fd1 LOCK_SH non-blocking");
    assert_eq!(lock(f2.as_raw_fd(), LOCK_SH | LOCK_NB), 0, "fd2 LOCK_SH non-blocking coexists");

    lock(f1.as_raw_fd(), LOCK_UN);
    lock(f2.as_raw_fd(), LOCK_UN);
    drop(f1);
    drop(f2);
    unsafe { unlink(cpath.as_ptr() as *const u8); }

    println!("concurrent_file_access: 12/12 ok");
}
