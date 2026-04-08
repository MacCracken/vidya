// Vidya — Filesystems in TypeScript
//
// TypeScript runs on a GC'd runtime, not bare metal — you don't implement
// real filesystems in it. But modeling filesystem concepts in TypeScript
// builds understanding: inodes, block bitmaps, directory entries, and CRUD
// operations. Strong types make the data structures explicit.
//
// Compare to Rust: Rust would use #[repr(C)] packed structs, raw pointers,
// and unsafe block device I/O. TypeScript models the logic, not the layout.

// ── Block: fixed-size storage unit ────────────────────────────────

const BLOCK_SIZE = 64; // bytes per block (tiny for demo)
const TOTAL_BLOCKS = 32;

type BlockIndex = number & { __brand: "BlockIndex" };

function blockIndex(n: number): BlockIndex {
    if (n < 0 || n >= TOTAL_BLOCKS) throw new Error(`Invalid block index: ${n}`);
    return n as BlockIndex;
}

// ── Block bitmap: tracks free/used blocks ─────────────────────────

class BlockBitmap {
    private bits: boolean[];

    constructor(size: number) {
        this.bits = new Array(size).fill(false);
    }

    allocate(): BlockIndex | undefined {
        const idx = this.bits.indexOf(false);
        if (idx === -1) return undefined;
        this.bits[idx] = true;
        return blockIndex(idx);
    }

    free(block: BlockIndex): void {
        this.bits[block] = false;
    }

    isUsed(block: BlockIndex): boolean {
        return this.bits[block];
    }

    freeCount(): number {
        return this.bits.filter((b) => !b).length;
    }
}

// ── Inode: file metadata (NOT the filename) ───────────────────────
// Key insight: the inode holds everything about a file EXCEPT its name.
// Names live in directory entries. This enables hard links.

interface InodeData {
    readonly ino: number;
    size: number;
    permissions: number; // e.g., 0o755
    readonly createdAt: number;
    modifiedAt: number;
    linkCount: number; // how many directory entries point here
    blocks: BlockIndex[]; // which blocks hold the data
    isDirectory: boolean;
}

class Inode {
    private data: InodeData;

    constructor(ino: number, isDirectory: boolean) {
        this.data = {
            ino,
            size: 0,
            permissions: isDirectory ? 0o755 : 0o644,
            createdAt: Date.now(),
            modifiedAt: Date.now(),
            linkCount: 0,
            blocks: [],
            isDirectory,
        };
    }

    get ino(): number { return this.data.ino; }
    get size(): number { return this.data.size; }
    get isDirectory(): boolean { return this.data.isDirectory; }
    get linkCount(): number { return this.data.linkCount; }
    get blocks(): readonly BlockIndex[] { return this.data.blocks; }

    addBlock(block: BlockIndex): void {
        this.data.blocks.push(block);
        this.data.modifiedAt = Date.now();
    }

    clearBlocks(): void {
        this.data.blocks.length = 0;
    }

    setSize(size: number): void {
        this.data.size = size;
        this.data.modifiedAt = Date.now();
    }

    incrementLinks(): void { this.data.linkCount++; }
    decrementLinks(): void { this.data.linkCount--; }
}

// ── Directory entry: maps name → inode number ─────────────────────
// This is the dentry — the link between a human-readable name and an inode.

interface DirectoryEntry {
    name: string;
    ino: number;
}

// ── SimpleFS: in-memory filesystem with CRUD ──────────────────────

class SimpleFS {
    private inodes: Map<number, Inode> = new Map();
    private blockBitmap: BlockBitmap;
    private blockStorage: Map<number, Uint8Array> = new Map();
    private directories: Map<number, DirectoryEntry[]> = new Map();
    private nextIno = 0;

    constructor() {
        this.blockBitmap = new BlockBitmap(TOTAL_BLOCKS);

        // Create root directory (inode 0)
        const root = this.allocateInode(true);
        this.directories.set(root.ino, []);
    }

    private allocateInode(isDirectory: boolean): Inode {
        const ino = this.nextIno++;
        const inode = new Inode(ino, isDirectory);
        this.inodes.set(ino, inode);
        return inode;
    }

    // ── CREATE: write a new file ──────────────────────────────────
    createFile(dirIno: number, name: string, content: string): number {
        const dirEntries = this.directories.get(dirIno);
        if (dirEntries === undefined) throw new Error(`Not a directory: inode ${dirIno}`);

        // Check for duplicate name
        if (dirEntries.some((e) => e.name === name)) {
            throw new Error(`File already exists: ${name}`);
        }

        // Allocate inode for the new file
        const inode = this.allocateInode(false);

        // Write content to blocks
        const data = new TextEncoder().encode(content);
        const blocksNeeded = Math.ceil(data.length / BLOCK_SIZE) || 1;

        for (let i = 0; i < blocksNeeded; i++) {
            const block = this.blockBitmap.allocate();
            if (block === undefined) throw new Error("No free blocks");

            const chunk = data.slice(i * BLOCK_SIZE, (i + 1) * BLOCK_SIZE);
            const blockData = new Uint8Array(BLOCK_SIZE);
            blockData.set(chunk);
            this.blockStorage.set(block, blockData);
            inode.addBlock(block);
        }

        inode.setSize(data.length);
        inode.incrementLinks();

        // Add directory entry: name → inode number
        dirEntries.push({ name, ino: inode.ino });

        return inode.ino;
    }

    // ── READ: retrieve file content ───────────────────────────────
    readFile(ino: number): string {
        const inode = this.inodes.get(ino);
        if (inode === undefined) throw new Error(`Inode not found: ${ino}`);
        if (inode.isDirectory) throw new Error(`Is a directory: inode ${ino}`);

        // Reassemble content from blocks
        const data = new Uint8Array(inode.size);
        let offset = 0;

        for (const block of inode.blocks) {
            const blockData = this.blockStorage.get(block);
            if (blockData === undefined) throw new Error(`Block missing: ${block}`);

            const remaining = inode.size - offset;
            const toCopy = Math.min(BLOCK_SIZE, remaining);
            data.set(blockData.slice(0, toCopy), offset);
            offset += toCopy;
        }

        return new TextDecoder().decode(data);
    }

    // ── UPDATE: overwrite file content ────────────────────────────
    updateFile(ino: number, content: string): void {
        const inode = this.inodes.get(ino);
        if (inode === undefined) throw new Error(`Inode not found: ${ino}`);
        if (inode.isDirectory) throw new Error(`Is a directory: inode ${ino}`);

        // Free old blocks
        for (const block of inode.blocks) {
            this.blockBitmap.free(block);
            this.blockStorage.delete(block);
        }

        // Write new content
        const data = new TextEncoder().encode(content);
        const newBlocks: BlockIndex[] = [];
        const blocksNeeded = Math.ceil(data.length / BLOCK_SIZE) || 1;

        for (let i = 0; i < blocksNeeded; i++) {
            const block = this.blockBitmap.allocate();
            if (block === undefined) throw new Error("No free blocks");

            const chunk = data.slice(i * BLOCK_SIZE, (i + 1) * BLOCK_SIZE);
            const blockData = new Uint8Array(BLOCK_SIZE);
            blockData.set(chunk);
            this.blockStorage.set(block, blockData);
            newBlocks.push(block);
        }

        // Replace inode's block list
        inode.clearBlocks();
        for (const b of newBlocks) inode.addBlock(b);
        inode.setSize(data.length);
    }

    // ── DELETE: unlink a file ─────────────────────────────────────
    // unlink removes the directory entry. The inode is freed only when
    // linkCount reaches 0 (supporting hard links).
    unlinkFile(dirIno: number, name: string): void {
        const dirEntries = this.directories.get(dirIno);
        if (dirEntries === undefined) throw new Error(`Not a directory: inode ${dirIno}`);

        const idx = dirEntries.findIndex((e) => e.name === name);
        if (idx === -1) throw new Error(`File not found: ${name}`);

        const entry = dirEntries[idx];
        const inode = this.inodes.get(entry.ino);
        if (inode === undefined) throw new Error(`Inode not found: ${entry.ino}`);

        // Remove directory entry
        dirEntries.splice(idx, 1);
        inode.decrementLinks();

        // Free inode and blocks if no more links
        if (inode.linkCount <= 0) {
            for (const block of inode.blocks) {
                this.blockBitmap.free(block);
                this.blockStorage.delete(block);
            }
            this.inodes.delete(inode.ino);
        }
    }

    // ── LOOKUP: find inode by name in a directory ─────────────────
    lookup(dirIno: number, name: string): number | undefined {
        const dirEntries = this.directories.get(dirIno);
        if (dirEntries === undefined) return undefined;
        return dirEntries.find((e) => e.name === name)?.ino;
    }

    // ── LIST: directory listing ───────────────────────────────────
    listDir(dirIno: number): DirectoryEntry[] {
        const entries = this.directories.get(dirIno);
        if (entries === undefined) throw new Error(`Not a directory: inode ${dirIno}`);
        return [...entries]; // defensive copy
    }

    // ── STAT: inode metadata ──────────────────────────────────────
    stat(ino: number): { size: number; isDirectory: boolean; links: number; blocks: number } {
        const inode = this.inodes.get(ino);
        if (inode === undefined) throw new Error(`Inode not found: ${ino}`);
        return {
            size: inode.size,
            isDirectory: inode.isDirectory,
            links: inode.linkCount,
            blocks: inode.blocks.length,
        };
    }

    // ── MKDIR: create a subdirectory ──────────────────────────────
    mkdir(parentIno: number, name: string): number {
        const parentEntries = this.directories.get(parentIno);
        if (parentEntries === undefined) throw new Error(`Not a directory: inode ${parentIno}`);

        if (parentEntries.some((e) => e.name === name)) {
            throw new Error(`Already exists: ${name}`);
        }

        const inode = this.allocateInode(true);
        inode.incrementLinks();
        this.directories.set(inode.ino, []);
        parentEntries.push({ name, ino: inode.ino });

        return inode.ino;
    }

    freeBlocks(): number {
        return this.blockBitmap.freeCount();
    }
}

// ── Tests ─────────────────────────────────────────────────────────

function main(): void {
    const fs = new SimpleFS();
    const ROOT = 0;

    // ── Block bitmap ──────────────────────────────────────────────
    const bitmap = new BlockBitmap(8);
    assert(bitmap.freeCount() === 8, "bitmap starts empty");
    const b0 = bitmap.allocate()!;
    assert(bitmap.isUsed(b0), "allocated block is used");
    assert(bitmap.freeCount() === 7, "one block used");
    bitmap.free(b0);
    assert(bitmap.freeCount() === 8, "block freed");

    // ── Create file ───────────────────────────────────────────────
    const freeBeforeCreate = fs.freeBlocks();
    const ino = fs.createFile(ROOT, "hello.txt", "Hello, filesystem!");
    assert(ino > 0, "file inode allocated");
    assert(fs.freeBlocks() < freeBeforeCreate, "blocks consumed");

    // ── Read file ─────────────────────────────────────────────────
    const content = fs.readFile(ino);
    assert(content === "Hello, filesystem!", "read matches write");

    // ── Lookup by name ────────────────────────────────────────────
    const found = fs.lookup(ROOT, "hello.txt");
    assert(found === ino, "lookup finds correct inode");
    assert(fs.lookup(ROOT, "missing.txt") === undefined, "lookup returns undefined for missing");

    // ── Directory listing ─────────────────────────────────────────
    const listing = fs.listDir(ROOT);
    assert(listing.length === 1, "one file in root");
    assert(listing[0].name === "hello.txt", "listing has correct name");

    // ── Stat ──────────────────────────────────────────────────────
    const info = fs.stat(ino);
    assert(info.size === 18, "stat size");
    assert(info.isDirectory === false, "stat not directory");
    assert(info.links === 1, "stat link count");
    assert(info.blocks >= 1, "stat has blocks");

    // ── Update file ───────────────────────────────────────────────
    fs.updateFile(ino, "Updated content here");
    assert(fs.readFile(ino) === "Updated content here", "update works");
    assert(fs.stat(ino).size === 20, "updated size");

    // ── Large file spanning multiple blocks ───────────────────────
    const longContent = "A".repeat(BLOCK_SIZE * 3 + 10); // spans 4 blocks
    const bigIno = fs.createFile(ROOT, "big.txt", longContent);
    assert(fs.readFile(bigIno) === longContent, "multi-block read");
    assert(fs.stat(bigIno).blocks === 4, "multi-block allocation");

    // ── Mkdir and nested files ────────────────────────────────────
    const subdir = fs.mkdir(ROOT, "docs");
    assert(fs.stat(subdir).isDirectory === true, "mkdir creates directory");
    const nestedIno = fs.createFile(subdir, "readme.md", "# Readme");
    assert(fs.readFile(nestedIno) === "# Readme", "nested file");
    assert(fs.listDir(subdir).length === 1, "subdir has one entry");

    // ── Delete file ───────────────────────────────────────────────
    const freeBeforeDelete = fs.freeBlocks();
    fs.unlinkFile(ROOT, "hello.txt");
    assert(fs.lookup(ROOT, "hello.txt") === undefined, "deleted file gone");
    assert(fs.freeBlocks() > freeBeforeDelete, "blocks freed on delete");

    // ── Duplicate name rejected ───────────────────────────────────
    fs.createFile(ROOT, "dup.txt", "first");
    let dupError = false;
    try { fs.createFile(ROOT, "dup.txt", "second"); } catch { dupError = true; }
    assert(dupError, "duplicate name rejected");

    // ── Inode/dentry separation: key filesystem insight ───────────
    // The name "big.txt" lives in the directory entry (dentry).
    // The file metadata (size, blocks) lives in the inode.
    // This separation enables hard links: multiple names → one inode.
    // In Rust, you'd model this with distinct types and Arc for shared ownership.
    // In TypeScript, Map<number, Inode> is the inode table, and
    // DirectoryEntry[] are the dentries.

    console.log("All filesystem examples passed.");
}

function assert(condition: boolean, msg: string): void {
    if (!condition) throw new Error(`Assertion failed: ${msg}`);
}

main();
