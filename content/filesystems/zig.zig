// Vidya — Filesystems in Zig
//
// A simple in-memory filesystem demonstrating core filesystem concepts:
//   1. Inodes — metadata nodes referencing data blocks
//   2. Block bitmap allocator — tracks free/used data blocks
//   3. Directory entries — name-to-inode mappings
//   4. File operations — create, read, write, delete
//
// Real filesystems (ext4, XFS, ZFS) use these same primitives on disk.
// Zig's packed structs, comptime, and explicit memory control make it
// a natural fit for filesystem implementation work.

const std = @import("std");
const print = std.debug.print;
const assert = std.debug.assert;
const mem = std.mem;

// ── Block Bitmap Allocator ───────────────────────────────────────────
//
// Tracks which data blocks are free/used. One bit per block.
// Same idea as ext2/ext3/ext4 block group bitmaps.

const BLOCK_SIZE: usize = 64;
const NUM_BLOCKS: usize = 64;
const BITMAP_BYTES: usize = NUM_BLOCKS / 8;

const BlockBitmap = struct {
    bits: [BITMAP_BYTES]u8 = [_]u8{0} ** BITMAP_BYTES,
    used_count: usize = 0,

    fn isUsed(self: *const BlockBitmap, block: usize) bool {
        return (self.bits[block / 8] >> @intCast(block % 8)) & 1 != 0;
    }

    fn markUsed(self: *BlockBitmap, block: usize) void {
        self.bits[block / 8] |= @as(u8, 1) << @intCast(block % 8);
        self.used_count += 1;
    }

    fn markFree(self: *BlockBitmap, block: usize) void {
        self.bits[block / 8] &= ~(@as(u8, 1) << @intCast(block % 8));
        self.used_count -= 1;
    }

    /// Allocate one free block. Returns block index or null.
    fn alloc(self: *BlockBitmap) ?usize {
        for (0..NUM_BLOCKS) |i| {
            if (!self.isUsed(i)) {
                self.markUsed(i);
                return i;
            }
        }
        return null;
    }

    fn free(self: *BlockBitmap, block: usize) void {
        self.markFree(block);
    }
};

// ── Inode ────────────────────────────────────────────────────────────
//
// An inode stores file metadata and pointers to data blocks.
// Real inodes have timestamps, permissions, link counts.
// We keep the essentials: type, size, and block pointers.

const MAX_DIRECT_BLOCKS: usize = 4;

const InodeType = enum(u8) {
    free = 0,
    file = 1,
    directory = 2,
};

const Inode = struct {
    itype: InodeType = .free,
    size: usize = 0,
    block_count: usize = 0,
    direct_blocks: [MAX_DIRECT_BLOCKS]?usize = .{null} ** MAX_DIRECT_BLOCKS,

    fn isActive(self: *const Inode) bool {
        return self.itype != .free;
    }

    fn addBlock(self: *Inode, block_idx: usize) bool {
        if (self.block_count >= MAX_DIRECT_BLOCKS) return false;
        self.direct_blocks[self.block_count] = block_idx;
        self.block_count += 1;
        return true;
    }

    fn clear(self: *Inode) void {
        self.* = Inode{};
    }
};

// ── Directory Entry ──────────────────────────────────────────────────
//
// Maps a filename to an inode number. Real directory entries (dentries)
// are cached in memory for fast path lookup. ext4 uses htree (hashed
// B-tree) for large directories.

const MAX_NAME_LEN: usize = 12;

const DirEntry = struct {
    name: [MAX_NAME_LEN]u8 = [_]u8{0} ** MAX_NAME_LEN,
    name_len: usize = 0,
    inode: ?usize = null,

    fn isActive(self: *const DirEntry) bool {
        return self.inode != null;
    }

    fn setName(self: *DirEntry, name: []const u8) void {
        const len = @min(name.len, MAX_NAME_LEN);
        @memcpy(self.name[0..len], name[0..len]);
        self.name_len = len;
    }

    fn nameSlice(self: *const DirEntry) []const u8 {
        return self.name[0..self.name_len];
    }

    fn matchName(self: *const DirEntry, name: []const u8) bool {
        if (self.name_len != name.len) return false;
        return mem.eql(u8, self.nameSlice(), name);
    }
};

// ── Simple Filesystem ────────────────────────────────────────────────
//
// Combines inodes, block bitmap, data blocks, and a root directory.
// Operations: create, write, read, delete, list.

const MAX_INODES: usize = 16;
const MAX_DIR_ENTRIES: usize = 16;

const SimpleFS = struct {
    inodes: [MAX_INODES]Inode = [_]Inode{.{}} ** MAX_INODES,
    bitmap: BlockBitmap = .{},
    data: [NUM_BLOCKS][BLOCK_SIZE]u8 = [_][BLOCK_SIZE]u8{[_]u8{0} ** BLOCK_SIZE} ** NUM_BLOCKS,
    root_entries: [MAX_DIR_ENTRIES]DirEntry = [_]DirEntry{.{}} ** MAX_DIR_ENTRIES,
    root_entry_count: usize = 0,

    /// Allocate a free inode. Returns inode index or null.
    fn allocInode(self: *SimpleFS) ?usize {
        // Skip inode 0 — reserved (like ext4)
        for (1..MAX_INODES) |i| {
            if (!self.inodes[i].isActive()) {
                return i;
            }
        }
        return null;
    }

    /// Create a file in the root directory.
    fn createFile(self: *SimpleFS, name: []const u8) ?usize {
        // Check for duplicate name
        for (self.root_entries[0..self.root_entry_count]) |*entry| {
            if (entry.isActive() and entry.matchName(name)) {
                return null; // already exists
            }
        }

        const ino = self.allocInode() orelse return null;
        self.inodes[ino].itype = .file;
        self.inodes[ino].size = 0;

        if (self.root_entry_count >= MAX_DIR_ENTRIES) return null;
        self.root_entries[self.root_entry_count].setName(name);
        self.root_entries[self.root_entry_count].inode = ino;
        self.root_entry_count += 1;

        return ino;
    }

    /// Write data to a file (replaces contents).
    fn writeFile(self: *SimpleFS, ino: usize, content: []const u8) bool {
        var inode = &self.inodes[ino];
        if (inode.itype != .file) return false;

        // Free existing blocks
        for (0..inode.block_count) |i| {
            if (inode.direct_blocks[i]) |blk| {
                self.bitmap.free(blk);
            }
        }
        inode.block_count = 0;
        inode.direct_blocks = .{null} ** MAX_DIRECT_BLOCKS;

        // Allocate new blocks and copy data
        var offset: usize = 0;
        while (offset < content.len) {
            const blk = self.bitmap.alloc() orelse return false;
            if (!inode.addBlock(blk)) {
                self.bitmap.free(blk);
                return false;
            }

            const chunk = @min(BLOCK_SIZE, content.len - offset);
            @memcpy(self.data[blk][0..chunk], content[offset..][0..chunk]);
            // Zero remainder of block
            if (chunk < BLOCK_SIZE) {
                @memset(self.data[blk][chunk..], 0);
            }
            offset += chunk;
        }
        inode.size = content.len;
        return true;
    }

    /// Read file contents into a buffer. Returns bytes read.
    fn readFile(self: *const SimpleFS, ino: usize, buf: []u8) ?usize {
        const inode = &self.inodes[ino];
        if (inode.itype != .file) return null;

        var offset: usize = 0;
        for (0..inode.block_count) |i| {
            const blk = inode.direct_blocks[i] orelse break;
            const remaining = inode.size - offset;
            const chunk = @min(BLOCK_SIZE, remaining);
            const dest_end = @min(offset + chunk, buf.len);
            if (dest_end <= offset) break;
            @memcpy(buf[offset..dest_end], self.data[blk][0 .. dest_end - offset]);
            offset = dest_end;
        }
        return offset;
    }

    /// Delete a file by name.
    fn deleteFile(self: *SimpleFS, name: []const u8) bool {
        for (self.root_entries[0..self.root_entry_count]) |*entry| {
            if (entry.isActive() and entry.matchName(name)) {
                const ino = entry.inode.?;
                var inode = &self.inodes[ino];

                // Free data blocks
                for (0..inode.block_count) |i| {
                    if (inode.direct_blocks[i]) |blk| {
                        self.bitmap.free(blk);
                    }
                }

                inode.clear();
                entry.inode = null;
                entry.name_len = 0;
                return true;
            }
        }
        return false;
    }

    /// Look up an inode number by filename.
    fn lookup(self: *const SimpleFS, name: []const u8) ?usize {
        for (self.root_entries[0..self.root_entry_count]) |*entry| {
            if (entry.isActive() and entry.matchName(name)) {
                return entry.inode;
            }
        }
        return null;
    }

    /// Count active files in root directory.
    fn fileCount(self: *const SimpleFS) usize {
        var count: usize = 0;
        for (self.root_entries[0..self.root_entry_count]) |*entry| {
            if (entry.isActive()) count += 1;
        }
        return count;
    }
};

// ── Main ─────────────────────────────────────────────────────────────

pub fn main() void {
    print("Filesystems — inode-based in-memory filesystem:\n\n", .{});

    var fs: SimpleFS = .{};

    // ── Create files ─────────────────────────────────────────────
    print("1. Create files:\n", .{});
    const ino_hello = fs.createFile("hello.txt");
    assert(ino_hello != null);
    print("   Created hello.txt -> inode {d}\n", .{ino_hello.?});

    const ino_data = fs.createFile("data.bin");
    assert(ino_data != null);
    print("   Created data.bin  -> inode {d}\n", .{ino_data.?});

    const ino_notes = fs.createFile("notes.txt");
    assert(ino_notes != null);
    print("   Created notes.txt -> inode {d}\n", .{ino_notes.?});

    // Duplicate name fails
    assert(fs.createFile("hello.txt") == null);
    print("   Duplicate hello.txt -> null (correct)\n", .{});

    assert(fs.fileCount() == 3);
    print("   File count: {d}\n\n", .{fs.fileCount()});

    // ── Write data ───────────────────────────────────────────────
    print("2. Write data:\n", .{});
    const hello_data = "Hello from the filesystem!";
    assert(fs.writeFile(ino_hello.?, hello_data));
    print("   Wrote {d} bytes to hello.txt\n", .{hello_data.len});
    assert(fs.inodes[ino_hello.?].size == hello_data.len);
    assert(fs.inodes[ino_hello.?].block_count == 1);
    print("   Inode: size={d}, blocks={d}\n", .{ fs.inodes[ino_hello.?].size, fs.inodes[ino_hello.?].block_count });

    // Multi-block write: data larger than one block
    var big_data: [150]u8 = undefined;
    for (0..150) |i| {
        big_data[i] = @intCast(i % 256);
    }
    assert(fs.writeFile(ino_data.?, &big_data));
    assert(fs.inodes[ino_data.?].block_count == 3); // 150 / 64 = 2.3 -> 3 blocks
    print("   Wrote {d} bytes to data.bin ({d} blocks)\n", .{ big_data.len, fs.inodes[ino_data.?].block_count });

    assert(fs.bitmap.used_count == 4); // 1 + 3 blocks allocated
    print("   Blocks in use: {d}/{d}\n\n", .{ fs.bitmap.used_count, NUM_BLOCKS });

    // ── Read data ────────────────────────────────────────────────
    print("3. Read data:\n", .{});
    var read_buf: [256]u8 = undefined;
    const bytes_read = fs.readFile(ino_hello.?, &read_buf);
    assert(bytes_read != null);
    assert(bytes_read.? == hello_data.len);
    assert(mem.eql(u8, read_buf[0..bytes_read.?], hello_data));
    print("   Read hello.txt: \"{s}\"\n", .{read_buf[0..bytes_read.?]});

    // Read multi-block file and verify contents
    const data_read = fs.readFile(ino_data.?, &read_buf);
    assert(data_read != null);
    assert(data_read.? == 150);
    for (0..150) |i| {
        assert(read_buf[i] == @as(u8, @intCast(i % 256)));
    }
    print("   Read data.bin: {d} bytes verified correct\n\n", .{data_read.?});

    // ── Lookup by name ───────────────────────────────────────────
    print("4. Directory lookup:\n", .{});
    assert(fs.lookup("hello.txt").? == ino_hello.?);
    assert(fs.lookup("data.bin").? == ino_data.?);
    assert(fs.lookup("missing") == null);
    print("   lookup(\"hello.txt\") = inode {d}\n", .{fs.lookup("hello.txt").?});
    print("   lookup(\"missing\")   = null\n\n", .{});

    // ── Overwrite a file ─────────────────────────────────────────
    print("5. Overwrite:\n", .{});
    const old_blocks = fs.bitmap.used_count;
    const new_content = "Updated!";
    assert(fs.writeFile(ino_hello.?, new_content));
    const overwrite_read = fs.readFile(ino_hello.?, &read_buf);
    assert(mem.eql(u8, read_buf[0..overwrite_read.?], new_content));
    print("   hello.txt overwritten: \"{s}\"\n", .{read_buf[0..overwrite_read.?]});
    // Old block was freed, new block allocated — net change is 0
    assert(fs.bitmap.used_count == old_blocks);
    print("   Block count unchanged: {d}\n\n", .{fs.bitmap.used_count});

    // ── Delete a file ────────────────────────────────────────────
    print("6. Delete:\n", .{});
    assert(fs.deleteFile("data.bin"));
    assert(fs.lookup("data.bin") == null);
    assert(fs.fileCount() == 2);
    assert(!fs.inodes[ino_data.?].isActive());
    print("   Deleted data.bin\n", .{});
    print("   File count: {d}\n", .{fs.fileCount()});
    print("   Blocks in use: {d} (3 blocks freed)\n", .{fs.bitmap.used_count});

    // Deleting nonexistent file returns false
    assert(!fs.deleteFile("data.bin"));
    print("   Re-delete data.bin -> false (correct)\n\n", .{});

    // ── Reuse freed inode ────────────────────────────────────────
    print("7. Inode reuse:\n", .{});
    const ino_new = fs.createFile("new.txt");
    assert(ino_new != null);
    assert(ino_new.? == ino_data.?); // reused the freed inode
    print("   Created new.txt -> inode {d} (reused)\n", .{ino_new.?});

    // ── Block bitmap verification ────────────────────────────────
    print("\n8. Block bitmap:\n", .{});
    var bmp = BlockBitmap{};
    const b0 = bmp.alloc();
    const b1 = bmp.alloc();
    const b2 = bmp.alloc();
    assert(b0.? == 0 and b1.? == 1 and b2.? == 2);
    assert(bmp.used_count == 3);
    bmp.free(1);
    assert(bmp.used_count == 2);
    assert(!bmp.isUsed(1));
    const reused = bmp.alloc();
    assert(reused.? == 1); // reused freed block
    print("   Alloc 3, free 1, realloc -> block {d} (reused)\n", .{reused.?});

    print("\nAll tests passed.\n", .{});
}
