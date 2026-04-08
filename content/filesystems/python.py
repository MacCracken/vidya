# Filesystems — Python Implementation
#
# Demonstrates filesystem concepts with an in-memory filesystem:
#   1. Inode-based file storage (metadata + block pointers)
#   2. Directory entries mapping names to inode numbers
#   3. Block allocation with a bitmap
#   4. VFS-like operations: create, read, write, unlink, stat
#   5. File descriptors and seek offsets
#
# This mirrors how ext4 works internally, simplified to the essentials.

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional

# ── Constants ─────────────────────────────────────────────────────────────

BLOCK_SIZE = 64        # small blocks for demo
TOTAL_BLOCKS = 64      # 64 blocks total
DIRECT_BLOCKS = 4      # direct block pointers per inode


# ── Block Device ──────────────────────────────────────────────────────────

class BlockDevice:
    """Simulated block device with bitmap allocator.

    A real block device is a disk. The bitmap tracks which blocks are
    in use — this is how ext4 manages free space (one bit per block).
    """

    def __init__(self):
        self.blocks: list[bytearray] = [bytearray(BLOCK_SIZE) for _ in range(TOTAL_BLOCKS)]
        self.bitmap: list[bool] = [False] * TOTAL_BLOCKS
        self.used: int = 0

    def alloc_block(self) -> Optional[int]:
        """Allocate a free block. Returns block index or None if full."""
        for i, allocated in enumerate(self.bitmap):
            if not allocated:
                self.bitmap[i] = True
                self.used += 1
                return i
        return None  # disk full

    def free_block(self, idx: int) -> None:
        """Free a block and zero its contents."""
        if self.bitmap[idx]:
            self.bitmap[idx] = False
            self.blocks[idx] = bytearray(BLOCK_SIZE)
            self.used -= 1

    def read_block(self, idx: int) -> bytes:
        return bytes(self.blocks[idx])

    def write_block(self, idx: int, data: bytes, offset: int = 0) -> None:
        end = min(offset + len(data), BLOCK_SIZE)
        self.blocks[idx][offset:end] = data[:end - offset]


# ── Inode ─────────────────────────────────────────────────────────────────

class FileType(Enum):
    REGULAR = auto()
    DIRECTORY = auto()


@dataclass
class Inode:
    """An inode stores file metadata and block pointers.

    The inode does NOT contain the filename — that lives in the directory
    entry. This is why hard links work: multiple directory entries can
    point to the same inode.

    Fields mirror real inode structure:
      - ino: unique inode number
      - file_type: regular file or directory
      - size: file size in bytes
      - blocks: direct block pointers (indices into the block device)
      - nlink: number of hard links (unlink decrements; 0 = delete)
      - mode: permissions (simplified)
    """
    ino: int
    file_type: FileType
    size: int = 0
    blocks: list[Optional[int]] = field(default_factory=lambda: [None] * DIRECT_BLOCKS)
    nlink: int = 1
    mode: int = 0o644

    def __str__(self) -> str:
        kind = "file" if self.file_type == FileType.REGULAR else "dir"
        block_list = [str(b) for b in self.blocks if b is not None]
        return f"ino={self.ino} {kind} size={self.size} nlink={self.nlink} blocks=[{','.join(block_list)}]"


# ── Directory Entry ───────────────────────────────────────────────────────

@dataclass
class DirEntry:
    """Maps a filename to an inode number.

    A directory is just a list of (name, inode) pairs. The VFS layer
    looks up names by scanning these entries.
    """
    name: str
    ino: int


# ── Open File Description ────────────────────────────────────────────────

@dataclass
class OpenFile:
    """Per-fd state: which inode and current seek offset.

    In a real kernel, the file descriptor table is per-process.
    Multiple fds can point to the same open file description (via dup()).
    """
    ino: int
    offset: int = 0


# ── Filesystem ────────────────────────────────────────────────────────────

class SimpleFs:
    """An in-memory inode-based filesystem.

    Implements the core VFS operations:
      - create: allocate inode, add directory entry
      - open: create file descriptor
      - write: allocate blocks, copy data
      - read: follow block pointers, return data
      - unlink: remove directory entry, free blocks when nlink=0
      - stat: return inode metadata
      - readdir: list directory entries
    """

    def __init__(self):
        self.device = BlockDevice()
        self.inodes: dict[int, Inode] = {}
        self.directories: dict[int, list[DirEntry]] = {}
        self.next_ino = 1
        self.open_files: dict[int, OpenFile] = {}
        self.next_fd = 3  # 0=stdin, 1=stdout, 2=stderr

        # Create root directory (inode 1)
        root = Inode(ino=1, file_type=FileType.DIRECTORY, mode=0o755)
        self.inodes[1] = root
        self.directories[1] = [
            DirEntry(".", 1),
            DirEntry("..", 1),
        ]
        self.next_ino = 2

    def create(self, parent_ino: int, name: str) -> int:
        """Create a regular file in a directory. Returns the new inode number."""
        entries = self.directories.get(parent_ino)
        assert entries is not None, f"parent inode {parent_ino} is not a directory"
        assert not any(e.name == name for e in entries), f"'{name}' already exists"

        ino = self.next_ino
        self.next_ino += 1

        self.inodes[ino] = Inode(ino=ino, file_type=FileType.REGULAR, mode=0o644)
        entries.append(DirEntry(name, ino))
        return ino

    def open(self, ino: int) -> int:
        """Open a file. Returns a file descriptor."""
        assert ino in self.inodes, f"inode {ino} does not exist"
        fd = self.next_fd
        self.next_fd += 1
        self.open_files[fd] = OpenFile(ino=ino)
        return fd

    def write(self, fd: int, data: bytes) -> int:
        """Write data to an open file. Returns bytes written."""
        of = self.open_files[fd]
        inode = self.inodes[of.ino]
        pos = of.offset
        written = 0

        i = 0
        while i < len(data):
            block_idx = pos // BLOCK_SIZE
            block_offset = pos % BLOCK_SIZE

            if block_idx >= DIRECT_BLOCKS:
                break  # no indirect blocks in this simple fs

            # Allocate block on first write (demand allocation)
            if inode.blocks[block_idx] is None:
                blk = self.device.alloc_block()
                assert blk is not None, "disk full"
                inode.blocks[block_idx] = blk

            chunk_size = min(len(data) - i, BLOCK_SIZE - block_offset)
            self.device.write_block(inode.blocks[block_idx],
                                     data[i:i + chunk_size], block_offset)
            pos += chunk_size
            written += chunk_size
            i += chunk_size

        if pos > inode.size:
            inode.size = pos
        of.offset = pos
        return written

    def read(self, fd: int, count: int) -> bytes:
        """Read up to count bytes from an open file."""
        of = self.open_files[fd]
        inode = self.inodes[of.ino]
        pos = of.offset
        result = bytearray()

        while len(result) < count and pos < inode.size:
            block_idx = pos // BLOCK_SIZE
            block_offset = pos % BLOCK_SIZE

            blk = inode.blocks[block_idx]
            if blk is None:
                break  # sparse file hole

            to_read = min(count - len(result), inode.size - pos,
                          BLOCK_SIZE - block_offset)
            block_data = self.device.read_block(blk)
            result.extend(block_data[block_offset:block_offset + to_read])
            pos += to_read

        of.offset = pos
        return bytes(result)

    def close(self, fd: int) -> None:
        """Close a file descriptor."""
        del self.open_files[fd]

    def unlink(self, parent_ino: int, name: str) -> None:
        """Remove a directory entry. Frees inode when nlink reaches 0."""
        entries = self.directories[parent_ino]
        idx = next(i for i, e in enumerate(entries) if e.name == name)
        ino = entries[idx].ino
        del entries[idx]

        inode = self.inodes[ino]
        inode.nlink -= 1
        if inode.nlink == 0:
            # Free all allocated blocks
            for blk in inode.blocks:
                if blk is not None:
                    self.device.free_block(blk)
            del self.inodes[ino]

    def stat(self, ino: int) -> Optional[Inode]:
        """Get inode metadata (like stat(2))."""
        return self.inodes.get(ino)

    def readdir(self, ino: int) -> Optional[list[DirEntry]]:
        """List directory contents."""
        return self.directories.get(ino)

    def lookup(self, parent_ino: int, name: str) -> Optional[int]:
        """Lookup a name in a directory. Returns inode number or None."""
        entries = self.directories.get(parent_ino)
        if entries is None:
            return None
        for e in entries:
            if e.name == name:
                return e.ino
        return None


# ── Main ──────────────────────────────────────────────────────────────────

def main() -> None:
    print("Filesystems — in-memory inode-based filesystem:\n")

    fs = SimpleFs()

    # ── 1. Create files ───────────────────────────────────────────────
    print("1. Creating files in root directory:")
    hello_ino = fs.create(1, "hello.txt")
    data_ino = fs.create(1, "data.bin")
    print(f"   Created hello.txt (ino={hello_ino}), data.bin (ino={data_ino})")
    assert hello_ino == 2
    assert data_ino == 3

    # ── 2. Write data ─────────────────────────────────────────────────
    print("\n2. Writing data:")
    fd1 = fs.open(hello_ino)
    written = fs.write(fd1, b"Hello, filesystem world! This is inode-based storage.")
    print(f"   Wrote {written} bytes to hello.txt (fd={fd1})")
    assert written == 53

    fd2 = fs.open(data_ino)
    big_data = bytes([0xAB] * 200)  # spans multiple blocks
    written2 = fs.write(fd2, big_data)
    blocks_used = (written2 + BLOCK_SIZE - 1) // BLOCK_SIZE
    print(f"   Wrote {written2} bytes to data.bin (fd={fd2}, spans {blocks_used} blocks)")
    assert written2 == 200 or written2 == DIRECT_BLOCKS * BLOCK_SIZE  # may be capped

    # ── 3. Read data back ─────────────────────────────────────────────
    print("\n3. Reading data:")
    fs.close(fd1)
    fd1 = fs.open(hello_ino)  # reopen to reset offset
    content = fs.read(fd1, 100)
    print(f"   Read {len(content)} bytes from hello.txt: \"{content.decode()}\"")
    assert content == b"Hello, filesystem world! This is inode-based storage."

    # ── 4. stat ───────────────────────────────────────────────────────
    print("\n4. stat (inode metadata):")
    for name, ino in [("hello.txt", hello_ino), ("data.bin", data_ino)]:
        inode = fs.stat(ino)
        assert inode is not None
        print(f"   {name} -> {inode}")

    assert fs.stat(hello_ino).size == 53
    assert fs.stat(hello_ino).nlink == 1

    # ── 5. Directory listing ──────────────────────────────────────────
    print("\n5. readdir (/):")
    entries = fs.readdir(1)
    assert entries is not None
    for entry in entries:
        inode = fs.stat(entry.ino)
        assert inode is not None
        kind = "d" if inode.file_type == FileType.DIRECTORY else "-"
        print(f"   {kind} {inode.size:>5} {entry.name}")

    # Verify lookup
    assert fs.lookup(1, "hello.txt") == hello_ino
    assert fs.lookup(1, "data.bin") == data_ino
    assert fs.lookup(1, "nonexistent") is None

    # ── 6. Unlink ─────────────────────────────────────────────────────
    print("\n6. Unlink (delete) hello.txt:")
    blocks_before = fs.device.used
    fs.unlink(1, "hello.txt")
    blocks_after = fs.device.used
    print(f"   Blocks freed: {blocks_before} -> {blocks_after} ({blocks_before - blocks_after} freed)")
    print(f"   Inode {hello_ino} exists: {hello_ino in fs.inodes}")

    assert hello_ino not in fs.inodes  # inode freed (nlink was 1)
    assert fs.lookup(1, "hello.txt") is None
    assert blocks_after < blocks_before

    # ── 7. Disk usage ─────────────────────────────────────────────────
    print(f"\n7. Disk usage:")
    print(f"   Total blocks: {TOTAL_BLOCKS}")
    print(f"   Used blocks: {fs.device.used}")
    print(f"   Free blocks: {TOTAL_BLOCKS - fs.device.used}")
    print(f"   Inodes used: {len(fs.inodes)}")

    assert fs.device.used > 0
    assert fs.device.used < TOTAL_BLOCKS

    print("\nAll assertions passed.")


if __name__ == "__main__":
    main()
