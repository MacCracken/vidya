// Vidya — Page Management in Rust
//
// Fixed-size 4KB pages within a single file: header at offset 0, page 0
// reserved as the null sentinel, data pages live at PAGE_SZ + num *
// PAGE_SZ exactly as the cyrius reference does. Free list is a stack —
// `next` pointer at byte offset 8 of each freed page, head in the
// header. Tests cover header round-trip, sequential alloc, write/read,
// and free-list reuse.

use std::fs::{File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};

const PAGE_SZ: u64 = 4096;
const MAGIC: u32 = 0x5041_5452;
const H_PGCOUNT: usize = 8;
const H_FREEHEAD: usize = 16;
const FP_NEXT: usize = 8;

fn page_offset(num: u64) -> u64 {
    PAGE_SZ + num * PAGE_SZ
}

struct Header {
    page_count: u64,
    freehead: u64,
}

impl Header {
    fn new() -> Self {
        Header { page_count: 1, freehead: 0 }
    }
    fn to_bytes(&self) -> [u8; PAGE_SZ as usize] {
        let mut buf = [0u8; PAGE_SZ as usize];
        buf[..4].copy_from_slice(&MAGIC.to_le_bytes());
        buf[H_PGCOUNT..H_PGCOUNT + 8].copy_from_slice(&self.page_count.to_le_bytes());
        buf[H_FREEHEAD..H_FREEHEAD + 8].copy_from_slice(&self.freehead.to_le_bytes());
        buf
    }
    fn verify(buf: &[u8]) -> bool {
        u32::from_le_bytes(buf[..4].try_into().unwrap()) == MAGIC
    }
    fn load(buf: &[u8]) -> Self {
        Header {
            page_count: u64::from_le_bytes(buf[H_PGCOUNT..H_PGCOUNT + 8].try_into().unwrap()),
            freehead: u64::from_le_bytes(buf[H_FREEHEAD..H_FREEHEAD + 8].try_into().unwrap()),
        }
    }
}

fn page_read(f: &mut File, num: u64, buf: &mut [u8]) -> std::io::Result<()> {
    f.seek(SeekFrom::Start(page_offset(num)))?;
    f.read_exact(buf)
}

fn page_write(f: &mut File, num: u64, buf: &[u8]) -> std::io::Result<()> {
    f.seek(SeekFrom::Start(page_offset(num)))?;
    f.write_all(buf)
}

fn page_alloc(f: &mut File, hdr: &mut Header) -> std::io::Result<u64> {
    if hdr.freehead != 0 {
        let fh = hdr.freehead;
        let mut buf = vec![0u8; PAGE_SZ as usize];
        page_read(f, fh, &mut buf)?;
        hdr.freehead = u64::from_le_bytes(buf[FP_NEXT..FP_NEXT + 8].try_into().unwrap());
        return Ok(fh);
    }
    let num = hdr.page_count;
    hdr.page_count += 1;
    let zero = vec![0u8; PAGE_SZ as usize];
    page_write(f, num, &zero)?;
    Ok(num)
}

fn page_free(f: &mut File, hdr: &mut Header, num: u64) -> std::io::Result<()> {
    let mut buf = vec![0u8; PAGE_SZ as usize];
    buf[FP_NEXT..FP_NEXT + 8].copy_from_slice(&hdr.freehead.to_le_bytes());
    page_write(f, num, &buf)?;
    hdr.freehead = num;
    Ok(())
}

fn main() -> std::io::Result<()> {
    let path = "/tmp/vidya_page_rust.bin";
    let _ = std::fs::remove_file(path);

    let mut f = OpenOptions::new().read(true).write(true).create(true).truncate(true).open(path)?;
    let mut hdr = Header::new();
    f.write_all(&hdr.to_bytes())?;

    // 1. magic ok
    f.seek(SeekFrom::Start(0))?;
    let mut hbuf = vec![0u8; PAGE_SZ as usize];
    f.read_exact(&mut hbuf)?;
    assert!(Header::verify(&hbuf), "magic ok");

    let loaded = Header::load(&hbuf);
    assert_eq!(loaded.page_count, 1, "pgcount starts at 1");

    // 2-3. sequential alloc
    let p1 = page_alloc(&mut f, &mut hdr)?;
    assert_eq!(p1, 1, "first alloc = 1");
    let p2 = page_alloc(&mut f, &mut hdr)?;
    assert_eq!(p2, 2, "second alloc = 2");

    // 4. write/read roundtrip
    let mut buf = vec![0u8; PAGE_SZ as usize];
    buf[..8].copy_from_slice(&42u64.to_le_bytes());
    page_write(&mut f, p1, &buf)?;
    let mut rb = vec![0u8; PAGE_SZ as usize];
    page_read(&mut f, p1, &mut rb)?;
    let got = u64::from_le_bytes(rb[..8].try_into().unwrap());
    assert_eq!(got, 42, "read back 42");

    // 5. free + reuse
    page_free(&mut f, &mut hdr, p2)?;
    let p3 = page_alloc(&mut f, &mut hdr)?;
    assert_eq!(p3, 2, "reused freed page");

    drop(f);
    let _ = std::fs::remove_file(path);
    println!("page_management: 6/6 ok");
    Ok(())
}
