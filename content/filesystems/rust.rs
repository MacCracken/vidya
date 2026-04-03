// Filesystems — Rust Implementation
//
// Demonstrates filesystem concepts with an in-memory filesystem:
//   1. Inode-based file storage (metadata + block pointers)
//   2. Directory entries mapping names to inode numbers
//   3. File descriptors and open file descriptions
//   4. Block allocation with a bitmap
//   5. VFS-like operations: create, read, write, unlink, stat
//
// This mirrors how ext4 works internally, simplified to the essentials.

use std::collections::HashMap;
use std::fmt;

// ── Constants ─────────────────────────────────────────────────────────────

const BLOCK_SIZE: usize = 64;      // small blocks for demo
const TOTAL_BLOCKS: usize = 64;    // 64 blocks total
const DIRECT_BLOCKS: usize = 4;    // direct block pointers per inode

// ── Block Device ──────────────────────────────────────────────────────────

struct BlockDevice {
    blocks: Vec<[u8; BLOCK_SIZE]>,
    bitmap: Vec<bool>,  // true = allocated
    used: usize,
}

impl BlockDevice {
    fn new() -> Self {
        Self {
            blocks: vec![[0u8; BLOCK_SIZE]; TOTAL_BLOCKS],
            bitmap: vec![false; TOTAL_BLOCKS],
            used: 0,
        }
    }

    fn alloc_block(&mut self) -> Option<usize> {
        for (i, allocated) in self.bitmap.iter_mut().enumerate() {
            if !*allocated {
                *allocated = true;
                self.used += 1;
                return Some(i);
            }
        }
        None // disk full
    }

    fn free_block(&mut self, idx: usize) {
        if self.bitmap[idx] {
            self.bitmap[idx] = false;
            self.blocks[idx] = [0u8; BLOCK_SIZE];
            self.used -= 1;
        }
    }

    fn read_block(&self, idx: usize) -> &[u8; BLOCK_SIZE] {
        &self.blocks[idx]
    }

    fn write_block(&mut self, idx: usize, data: &[u8], offset: usize) {
        let end = (offset + data.len()).min(BLOCK_SIZE);
        self.blocks[idx][offset..end].copy_from_slice(&data[..end - offset]);
    }
}

// ── Inode ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq)]
enum FileType {
    Regular,
    Directory,
}

#[derive(Debug, Clone)]
struct Inode {
    ino: u32,
    file_type: FileType,
    size: u64,
    /// Direct block pointers
    blocks: [Option<usize>; DIRECT_BLOCKS],
    /// Number of hard links
    nlink: u32,
    /// Permissions (simplified)
    mode: u16,
}

impl Inode {
    fn new(ino: u32, file_type: FileType, mode: u16) -> Self {
        Self {
            ino,
            file_type,
            size: 0,
            blocks: [None; DIRECT_BLOCKS],
            nlink: 1,
            mode,
        }
    }
}

impl fmt::Display for Inode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let kind = match self.file_type {
            FileType::Regular => "file",
            FileType::Directory => "dir",
        };
        let block_list: Vec<String> = self
            .blocks
            .iter()
            .flatten()
            .map(|b| b.to_string())
            .collect();
        write!(
            f,
            "ino={} {} size={} nlink={} blocks=[{}]",
            self.ino,
            kind,
            self.size,
            self.nlink,
            block_list.join(",")
        )
    }
}

// ── Directory Entry ───────────────────────────────────────────────────────

#[derive(Debug, Clone)]
struct DirEntry {
    name: String,
    ino: u32,
}

// ── Open File Description ─────────────────────────────────────────────────

struct OpenFile {
    ino: u32,
    offset: u64,
    flags: u32,
}

// ── Filesystem ────────────────────────────────────────────────────────────

struct SimpleFs {
    device: BlockDevice,
    inodes: HashMap<u32, Inode>,
    /// Directory contents: parent_ino → entries
    directories: HashMap<u32, Vec<DirEntry>>,
    next_ino: u32,
    /// Open file descriptions (simulated file descriptor table)
    open_files: HashMap<u32, OpenFile>,
    next_fd: u32,
}

impl SimpleFs {
    fn new() -> Self {
        let mut fs = Self {
            device: BlockDevice::new(),
            inodes: HashMap::new(),
            directories: HashMap::new(),
            next_ino: 1,
            open_files: HashMap::new(),
            next_fd: 3, // 0=stdin, 1=stdout, 2=stderr
        };

        // Create root directory (inode 1)
        let root = Inode::new(1, FileType::Directory, 0o755);
        fs.inodes.insert(1, root);
        fs.directories.insert(1, vec![
            DirEntry { name: ".".to_string(), ino: 1 },
            DirEntry { name: "..".to_string(), ino: 1 },
        ]);
        fs.next_ino = 2;

        fs
    }

    /// Create a file in a directory. Returns the new inode number.
    fn create(&mut self, parent_ino: u32, name: &str) -> Result<u32, String> {
        // Check for duplicate
        if let Some(entries) = self.directories.get(&parent_ino) {
            if entries.iter().any(|e| e.name == name) {
                return Err(format!("'{}' already exists", name));
            }
        } else {
            return Err(format!("parent inode {} is not a directory", parent_ino));
        }

        let ino = self.next_ino;
        self.next_ino += 1;

        let inode = Inode::new(ino, FileType::Regular, 0o644);
        self.inodes.insert(ino, inode);

        self.directories
            .get_mut(&parent_ino)
            .unwrap()
            .push(DirEntry { name: name.to_string(), ino });

        Ok(ino)
    }

    /// Open a file. Returns a file descriptor.
    fn open(&mut self, ino: u32) -> Result<u32, String> {
        if !self.inodes.contains_key(&ino) {
            return Err(format!("inode {} does not exist", ino));
        }

        let fd = self.next_fd;
        self.next_fd += 1;
        self.open_files.insert(fd, OpenFile { ino, offset: 0, flags: 0 });
        Ok(fd)
    }

    /// Write data to an open file.
    fn write(&mut self, fd: u32, data: &[u8]) -> Result<usize, String> {
        let of = self.open_files.get(&fd).ok_or("bad fd")?;
        let ino = of.ino;
        let offset = of.offset as usize;

        if !self.inodes.contains_key(&ino) {
            return Err("inode gone".into());
        }

        let mut written = 0;
        let mut pos = offset;

        for chunk in data.chunks(BLOCK_SIZE) {
            let block_idx = pos / BLOCK_SIZE;
            let block_offset = pos % BLOCK_SIZE;

            if block_idx >= DIRECT_BLOCKS {
                break; // no indirect blocks in this simple fs
            }

            // Allocate block if needed
            let needs_alloc = self.inodes[&ino].blocks[block_idx].is_none();
            if needs_alloc {
                let blk = self.device.alloc_block().ok_or("disk full")?;
                self.inodes.get_mut(&ino).unwrap().blocks[block_idx] = Some(blk);
            }

            let blk = self.inodes[&ino].blocks[block_idx].unwrap();
            let to_write = chunk.len().min(BLOCK_SIZE - block_offset);
            self.device.write_block(blk, &chunk[..to_write], block_offset);

            pos += to_write;
            written += to_write;
        }

        let inode = self.inodes.get_mut(&ino).unwrap();
        if pos as u64 > inode.size {
            inode.size = pos as u64;
        }

        self.open_files.get_mut(&fd).unwrap().offset = pos as u64;
        Ok(written)
    }

    /// Read data from an open file.
    fn read(&mut self, fd: u32, buf: &mut [u8]) -> Result<usize, String> {
        let of = self.open_files.get(&fd).ok_or("bad fd")?;
        let ino = of.ino;
        let offset = of.offset as usize;
        let inode = &self.inodes[&ino];
        let file_size = inode.size as usize;

        if offset >= file_size {
            return Ok(0); // EOF
        }

        let mut read_count = 0;
        let mut pos = offset;

        while read_count < buf.len() && pos < file_size {
            let block_idx = pos / BLOCK_SIZE;
            let block_offset = pos % BLOCK_SIZE;

            if let Some(blk) = inode.blocks[block_idx] {
                let block_data = self.device.read_block(blk);
                let to_read = buf.len().min(file_size - pos).min(BLOCK_SIZE - block_offset);
                buf[read_count..read_count + to_read]
                    .copy_from_slice(&block_data[block_offset..block_offset + to_read]);
                pos += to_read;
                read_count += to_read;
            } else {
                break; // sparse file — block not allocated
            }
        }

        self.open_files.get_mut(&fd).unwrap().offset = pos as u64;
        Ok(read_count)
    }

    /// Close a file descriptor.
    fn close(&mut self, fd: u32) {
        self.open_files.remove(&fd);
    }

    /// Unlink (delete) a file from a directory.
    fn unlink(&mut self, parent_ino: u32, name: &str) -> Result<(), String> {
        let entries = self.directories.get_mut(&parent_ino).ok_or("not a dir")?;
        let pos = entries.iter().position(|e| e.name == name).ok_or("not found")?;
        let ino = entries[pos].ino;
        entries.remove(pos);

        // Decrement link count
        if let Some(inode) = self.inodes.get_mut(&ino) {
            inode.nlink -= 1;
            if inode.nlink == 0 {
                // Free blocks
                for blk in &inode.blocks {
                    if let Some(b) = blk {
                        self.device.free_block(*b);
                    }
                }
                self.inodes.remove(&ino);
            }
        }

        Ok(())
    }

    /// stat: get inode info
    fn stat(&self, ino: u32) -> Option<&Inode> {
        self.inodes.get(&ino)
    }

    /// List directory contents
    fn readdir(&self, ino: u32) -> Option<&[DirEntry]> {
        self.directories.get(&ino).map(|v| v.as_slice())
    }

    /// Lookup a name in a directory
    fn lookup(&self, parent_ino: u32, name: &str) -> Option<u32> {
        self.directories
            .get(&parent_ino)?
            .iter()
            .find(|e| e.name == name)
            .map(|e| e.ino)
    }
}

fn main() {
    println!("Filesystems — in-memory inode-based filesystem:\n");

    let mut fs = SimpleFs::new();

    // ── Create files ──────────────────────────────────────────────────
    println!("1. Creating files in root directory:");
    let hello_ino = fs.create(1, "hello.txt").unwrap();
    let data_ino = fs.create(1, "data.bin").unwrap();
    println!("   Created hello.txt (ino={}), data.bin (ino={})", hello_ino, data_ino);

    // ── Write data ────────────────────────────────────────────────────
    println!("\n2. Writing data:");
    let fd1 = fs.open(hello_ino).unwrap();
    let written = fs.write(fd1, b"Hello, filesystem world! This is inode-based storage.").unwrap();
    println!("   Wrote {} bytes to hello.txt (fd={})", written, fd1);

    let fd2 = fs.open(data_ino).unwrap();
    let big_data = vec![0xABu8; 200]; // spans multiple blocks
    let written2 = fs.write(fd2, &big_data).unwrap();
    println!("   Wrote {} bytes to data.bin (fd={}, spans {} blocks)", written2, fd2,
        (written2 + BLOCK_SIZE - 1) / BLOCK_SIZE);

    // ── Read data back ────────────────────────────────────────────────
    println!("\n3. Reading data:");
    fs.close(fd1);
    let fd1 = fs.open(hello_ino).unwrap(); // reopen to reset offset
    let mut buf = [0u8; 100];
    let read_count = fs.read(fd1, &mut buf).unwrap();
    println!("   Read {} bytes from hello.txt: \"{}\"",
        read_count, std::str::from_utf8(&buf[..read_count]).unwrap());

    // ── stat ──────────────────────────────────────────────────────────
    println!("\n4. stat (inode metadata):");
    for (name, ino) in [("hello.txt", hello_ino), ("data.bin", data_ino)] {
        let inode = fs.stat(ino).unwrap();
        println!("   {} → {}", name, inode);
    }

    // ── Directory listing ─────────────────────────────────────────────
    println!("\n5. readdir (/):");
    if let Some(entries) = fs.readdir(1) {
        for entry in entries {
            let inode = fs.stat(entry.ino).unwrap();
            let kind = match inode.file_type {
                FileType::Directory => "d",
                FileType::Regular => "-",
            };
            println!("   {} {:>5} {}", kind, inode.size, entry.name);
        }
    }

    // ── Unlink ────────────────────────────────────────────────────────
    println!("\n6. Unlink (delete) hello.txt:");
    let blocks_before = fs.device.used;
    fs.unlink(1, "hello.txt").unwrap();
    println!("   Blocks freed: {} → {} ({} freed)",
        blocks_before, fs.device.used, blocks_before - fs.device.used);
    println!("   Inode {} exists: {}", hello_ino, fs.inodes.contains_key(&hello_ino));

    // ── Disk usage ────────────────────────────────────────────────────
    println!("\n7. Disk usage:");
    println!("   Total blocks: {}", TOTAL_BLOCKS);
    println!("   Used blocks: {}", fs.device.used);
    println!("   Free blocks: {}", TOTAL_BLOCKS - fs.device.used);
    println!("   Inodes used: {}", fs.inodes.len());
}
