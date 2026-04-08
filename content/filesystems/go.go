// Vidya — Filesystems in Go
//
// Simulates a Unix-style filesystem from scratch:
//   1. VFS (Virtual Filesystem Switch) layer — abstract interface
//   2. Inode structure — metadata for files and directories
//   3. Block allocation bitmap — track free/used disk blocks
//   4. Directory entries — name-to-inode mapping
//   5. File operations — create, read, write, delete
//   6. Path resolution — traversing directory tree
//
// Real filesystems (ext4, XFS, btrfs) implement these concepts in
// the kernel. Here we model the data structures and algorithms that
// underpin all Unix filesystems.

package main

import (
	"fmt"
	"strings"
	"time"
)

func main() {
	testBlockBitmap()
	testInodeStructure()
	testDirectoryEntries()
	testFileOperations()
	testPathResolution()
	testVFSInterface()

	fmt.Println("All filesystem examples passed.")
}

// ── Block Allocation Bitmap ──────────────────────────────────────────
// Each bit represents one disk block. 1=allocated, 0=free.
// A 4KB bitmap tracks 32768 blocks = 128 MB with 4KB blocks.

const (
	BlockSize   = 4096
	TotalBlocks = 256 // small for demonstration
)

type BlockBitmap struct {
	bits      [TotalBlocks / 8]byte // 32 bytes for 256 blocks
	freeCount int
}

func NewBlockBitmap() *BlockBitmap {
	bm := &BlockBitmap{freeCount: TotalBlocks}
	// Reserve block 0 (superblock) and block 1 (bitmap itself)
	bm.Alloc() // block 0
	bm.Alloc() // block 1
	return bm
}

func (bm *BlockBitmap) IsAllocated(block int) bool {
	return bm.bits[block/8]&(1<<uint(block%8)) != 0
}

func (bm *BlockBitmap) Alloc() int {
	for i := 0; i < TotalBlocks; i++ {
		if !bm.IsAllocated(i) {
			bm.bits[i/8] |= 1 << uint(i%8)
			bm.freeCount--
			return i
		}
	}
	return -1 // no free blocks
}

func (bm *BlockBitmap) Free(block int) {
	if bm.IsAllocated(block) {
		bm.bits[block/8] &^= 1 << uint(block%8)
		bm.freeCount++
	}
}

func (bm *BlockBitmap) FreeCount() int { return bm.freeCount }

func testBlockBitmap() {
	fmt.Println("1. Block allocation bitmap:")

	bm := NewBlockBitmap()

	// Blocks 0 and 1 are reserved
	assert(bm.IsAllocated(0), "block 0 reserved (superblock)")
	assert(bm.IsAllocated(1), "block 1 reserved (bitmap)")
	assert(!bm.IsAllocated(2), "block 2 free")
	assert(bm.FreeCount() == TotalBlocks-2, "254 free blocks")

	// Allocate some blocks
	b1 := bm.Alloc()
	b2 := bm.Alloc()
	b3 := bm.Alloc()
	assert(b1 == 2, "first alloc = block 2")
	assert(b2 == 3, "second alloc = block 3")
	assert(b3 == 4, "third alloc = block 4")
	assert(bm.FreeCount() == TotalBlocks-5, "251 free")

	// Free a block and reallocate — fills the gap
	bm.Free(3)
	assert(!bm.IsAllocated(3), "block 3 freed")
	assert(bm.FreeCount() == TotalBlocks-4, "252 free")

	b4 := bm.Alloc()
	assert(b4 == 3, "realloc fills gap at block 3")

	fmt.Printf("   Total blocks: %d (%d KB)\n", TotalBlocks, TotalBlocks*BlockSize/1024)
	fmt.Printf("   Bitmap size:  %d bytes (%d bits)\n", len(bm.bits), len(bm.bits)*8)
	fmt.Printf("   Free:  %d blocks\n", bm.FreeCount())
	fmt.Printf("   Used:  %d blocks (0=super, 1=bitmap, 2-4=data)\n", TotalBlocks-bm.FreeCount())
}

// ── Inode ────────────────────────────────────────────────────────────
// An inode stores all metadata about a file except its name.
// The name lives in the parent directory's entries.

type FileType int

const (
	TypeRegular   FileType = iota
	TypeDirectory
	TypeSymlink
	TypeBlockDev
	TypeCharDev
)

func (ft FileType) String() string {
	switch ft {
	case TypeRegular:
		return "regular"
	case TypeDirectory:
		return "directory"
	case TypeSymlink:
		return "symlink"
	case TypeBlockDev:
		return "block device"
	case TypeCharDev:
		return "char device"
	default:
		return "unknown"
	}
}

// Permission bits — standard Unix rwxrwxrwx
const (
	PERM_OWNER_R uint16 = 0o400
	PERM_OWNER_W uint16 = 0o200
	PERM_OWNER_X uint16 = 0o100
	PERM_GROUP_R uint16 = 0o040
	PERM_GROUP_W uint16 = 0o020
	PERM_GROUP_X uint16 = 0o010
	PERM_OTHER_R uint16 = 0o004
	PERM_OTHER_W uint16 = 0o002
	PERM_OTHER_X uint16 = 0o001
	PERM_SUID    uint16 = 0o4000
	PERM_SGID    uint16 = 0o2000
	PERM_STICKY  uint16 = 0o1000
)

type Inode struct {
	Number     uint32
	Type       FileType
	Mode       uint16 // permission bits
	UID        uint32
	GID        uint32
	Size       uint64
	Links      uint16   // hard link count
	Blocks     []int    // data block numbers (direct pointers)
	CreateTime time.Time
	ModifyTime time.Time
	AccessTime time.Time
}

func (i *Inode) PermString() string {
	var buf [9]byte
	perms := []struct {
		bit  uint16
		char byte
	}{
		{PERM_OWNER_R, 'r'}, {PERM_OWNER_W, 'w'}, {PERM_OWNER_X, 'x'},
		{PERM_GROUP_R, 'r'}, {PERM_GROUP_W, 'w'}, {PERM_GROUP_X, 'x'},
		{PERM_OTHER_R, 'r'}, {PERM_OTHER_W, 'w'}, {PERM_OTHER_X, 'x'},
	}
	for j, p := range perms {
		if i.Mode&p.bit != 0 {
			buf[j] = p.char
		} else {
			buf[j] = '-'
		}
	}
	return string(buf[:])
}

func testInodeStructure() {
	fmt.Println("\n2. Inode structure:")

	now := time.Date(2025, 1, 15, 10, 30, 0, 0, time.UTC)

	// Regular file inode
	file := Inode{
		Number:     42,
		Type:       TypeRegular,
		Mode:       PERM_OWNER_R | PERM_OWNER_W | PERM_GROUP_R | PERM_OTHER_R, // 644
		UID:        1000,
		GID:        1000,
		Size:       8192,
		Links:      1,
		Blocks:     []int{10, 11},
		CreateTime: now,
		ModifyTime: now,
		AccessTime: now,
	}
	assert(file.Type == TypeRegular, "regular file")
	assert(file.Mode == 0o644, "mode 644")
	assert(file.PermString() == "rw-r--r--", "perm string 644")
	assert(file.Links == 1, "one hard link")
	assert(len(file.Blocks) == 2, "two data blocks")

	// Directory inode — always has at least 2 links (. and parent's entry)
	dir := Inode{
		Number: 2,
		Type:   TypeDirectory,
		Mode:   PERM_OWNER_R | PERM_OWNER_W | PERM_OWNER_X | PERM_GROUP_R | PERM_GROUP_X | PERM_OTHER_R | PERM_OTHER_X, // 755
		Links:  3, // . + parent + one subdirectory
		Blocks: []int{5},
	}
	assert(dir.Type == TypeDirectory, "directory")
	assert(dir.Mode == 0o755, "mode 755")
	assert(dir.PermString() == "rwxr-xr-x", "perm string 755")
	assert(dir.Links >= 2, "dir has at least 2 links")

	fmt.Printf("   File:  inode=%d type=%s mode=%s (%04o) size=%d links=%d\n",
		file.Number, file.Type, file.PermString(), file.Mode, file.Size, file.Links)
	fmt.Printf("   Dir:   inode=%d type=%s mode=%s (%04o) links=%d\n",
		dir.Number, dir.Type, dir.PermString(), dir.Mode, dir.Links)
	fmt.Printf("   Blocks: file uses blocks %v (%d bytes data)\n",
		file.Blocks, len(file.Blocks)*BlockSize)
}

// ── Directory Entries ────────────────────────────────────────────────
// A directory is a file whose data blocks contain name-to-inode mappings.
// Every directory has "." (self) and ".." (parent) entries.

type DirEntry struct {
	Name  string
	Inode uint32
	Type  FileType
}

type Directory struct {
	inode   *Inode
	entries []DirEntry
}

func NewDirectory(inode *Inode, parentInode uint32) *Directory {
	inode.Type = TypeDirectory
	return &Directory{
		inode: inode,
		entries: []DirEntry{
			{".", inode.Number, TypeDirectory},
			{"..", parentInode, TypeDirectory},
		},
	}
}

func (d *Directory) AddEntry(name string, ino uint32, ft FileType) {
	d.entries = append(d.entries, DirEntry{name, ino, ft})
	if ft == TypeDirectory {
		d.inode.Links++ // subdirectory's ".." points here
	}
}

func (d *Directory) Lookup(name string) (uint32, bool) {
	for _, e := range d.entries {
		if e.Name == name {
			return e.Inode, true
		}
	}
	return 0, false
}

func (d *Directory) RemoveEntry(name string) bool {
	for i, e := range d.entries {
		if e.Name == name {
			if e.Type == TypeDirectory {
				d.inode.Links--
			}
			d.entries = append(d.entries[:i], d.entries[i+1:]...)
			return true
		}
	}
	return false
}

func testDirectoryEntries() {
	fmt.Println("\n3. Directory entries:")

	rootInode := &Inode{Number: 1, Links: 2, Mode: 0o755}
	root := NewDirectory(rootInode, 1) // root's parent is itself

	// Verify . and ..
	dotIno, ok := root.Lookup(".")
	assert(ok && dotIno == 1, ". points to self")
	dotdotIno, ok := root.Lookup("..")
	assert(ok && dotdotIno == 1, "root's .. points to self")

	// Add some entries
	root.AddEntry("etc", 3, TypeDirectory)
	root.AddEntry("bin", 4, TypeDirectory)
	root.AddEntry("README.md", 5, TypeRegular)

	etcIno, ok := root.Lookup("etc")
	assert(ok && etcIno == 3, "etc lookup")

	readmeIno, ok := root.Lookup("README.md")
	assert(ok && readmeIno == 5, "README.md lookup")

	_, ok = root.Lookup("nonexistent")
	assert(!ok, "nonexistent fails lookup")

	// Directory link count: . + parent's entry + 2 subdirs = 4
	assert(rootInode.Links == 4, "root links = 2 base + 2 subdirs")

	// Remove an entry
	removed := root.RemoveEntry("etc")
	assert(removed, "etc removed")
	assert(rootInode.Links == 3, "link count decremented")
	_, ok = root.Lookup("etc")
	assert(!ok, "etc gone after remove")

	fmt.Printf("   Root directory (inode %d):\n", rootInode.Number)
	for _, e := range root.entries {
		fmt.Printf("      %-12s -> inode %d (%s)\n", e.Name, e.Inode, e.Type)
	}
	fmt.Printf("   Link count: %d (. + parent + %d subdirs)\n",
		rootInode.Links, rootInode.Links-2)
}

// ── Simple Filesystem ────────────────────────────────────────────────
// Combines bitmap, inodes, and directories into a working filesystem.

type SimpleFS struct {
	bitmap    *BlockBitmap
	inodes    map[uint32]*Inode
	dirs      map[uint32]*Directory
	data      map[uint32][]byte // inode -> file data
	nextInode uint32
}

func NewSimpleFS() *SimpleFS {
	fs := &SimpleFS{
		bitmap:    NewBlockBitmap(),
		inodes:    make(map[uint32]*Inode),
		dirs:      make(map[uint32]*Directory),
		data:      make(map[uint32][]byte),
		nextInode: 1,
	}

	// Create root directory
	rootInode := fs.allocInode(TypeDirectory, 0o755)
	rootDir := NewDirectory(rootInode, rootInode.Number)
	fs.dirs[rootInode.Number] = rootDir
	return fs
}

func (fs *SimpleFS) allocInode(ft FileType, mode uint16) *Inode {
	ino := fs.nextInode
	fs.nextInode++
	now := time.Now()
	inode := &Inode{
		Number:     ino,
		Type:       ft,
		Mode:       mode,
		Links:      1,
		CreateTime: now,
		ModifyTime: now,
		AccessTime: now,
	}
	fs.inodes[ino] = inode
	return inode
}

func (fs *SimpleFS) CreateFile(parentIno uint32, name string, mode uint16) (uint32, bool) {
	dir, ok := fs.dirs[parentIno]
	if !ok {
		return 0, false
	}
	// Check for duplicate
	if _, exists := dir.Lookup(name); exists {
		return 0, false
	}

	inode := fs.allocInode(TypeRegular, mode)
	dir.AddEntry(name, inode.Number, TypeRegular)
	fs.data[inode.Number] = nil
	return inode.Number, true
}

func (fs *SimpleFS) CreateDir(parentIno uint32, name string, mode uint16) (uint32, bool) {
	dir, ok := fs.dirs[parentIno]
	if !ok {
		return 0, false
	}
	if _, exists := dir.Lookup(name); exists {
		return 0, false
	}

	inode := fs.allocInode(TypeDirectory, mode)
	inode.Links = 2 // . and parent's entry
	newDir := NewDirectory(inode, parentIno)
	fs.dirs[inode.Number] = newDir
	dir.AddEntry(name, inode.Number, TypeDirectory)
	return inode.Number, true
}

func (fs *SimpleFS) WriteFile(ino uint32, content []byte) bool {
	inode, ok := fs.inodes[ino]
	if !ok || inode.Type != TypeRegular {
		return false
	}

	// Free old blocks
	for _, b := range inode.Blocks {
		fs.bitmap.Free(b)
	}
	inode.Blocks = nil

	// Allocate new blocks
	blocksNeeded := (len(content) + BlockSize - 1) / BlockSize
	if blocksNeeded == 0 {
		blocksNeeded = 0
	}
	for i := 0; i < blocksNeeded; i++ {
		b := fs.bitmap.Alloc()
		if b < 0 {
			return false // disk full
		}
		inode.Blocks = append(inode.Blocks, b)
	}

	inode.Size = uint64(len(content))
	inode.ModifyTime = time.Now()
	fs.data[ino] = make([]byte, len(content))
	copy(fs.data[ino], content)
	return true
}

func (fs *SimpleFS) ReadFile(ino uint32) ([]byte, bool) {
	inode, ok := fs.inodes[ino]
	if !ok || inode.Type != TypeRegular {
		return nil, false
	}
	inode.AccessTime = time.Now()
	data := fs.data[ino]
	if data == nil {
		return []byte{}, true
	}
	result := make([]byte, len(data))
	copy(result, data)
	return result, true
}

func (fs *SimpleFS) DeleteFile(parentIno uint32, name string) bool {
	dir, ok := fs.dirs[parentIno]
	if !ok {
		return false
	}
	ino, ok := dir.Lookup(name)
	if !ok {
		return false
	}
	inode := fs.inodes[ino]
	if inode.Type == TypeDirectory {
		return false // use rmdir for directories
	}

	dir.RemoveEntry(name)
	inode.Links--
	if inode.Links == 0 {
		// Free blocks
		for _, b := range inode.Blocks {
			fs.bitmap.Free(b)
		}
		delete(fs.data, ino)
		delete(fs.inodes, ino)
	}
	return true
}

// ResolvePath walks the directory tree from root to find an inode.
func (fs *SimpleFS) ResolvePath(path string) (uint32, bool) {
	if path == "/" {
		return 1, true
	}

	parts := strings.Split(strings.Trim(path, "/"), "/")
	current := uint32(1) // root inode

	for _, part := range parts {
		dir, ok := fs.dirs[current]
		if !ok {
			return 0, false
		}
		ino, ok := dir.Lookup(part)
		if !ok {
			return 0, false
		}
		current = ino
	}
	return current, true
}

func testFileOperations() {
	fmt.Println("\n4. File operations (create/read/write/delete):")

	fs := NewSimpleFS()

	// Create files in root
	helloIno, ok := fs.CreateFile(1, "hello.txt", 0o644)
	assert(ok, "create hello.txt")

	readmeIno, ok := fs.CreateFile(1, "README.md", 0o644)
	assert(ok, "create README.md")

	// Duplicate should fail
	_, ok = fs.CreateFile(1, "hello.txt", 0o644)
	assert(!ok, "duplicate create fails")

	// Write content
	content := []byte("Hello, filesystem!")
	ok = fs.WriteFile(helloIno, content)
	assert(ok, "write hello.txt")

	inode := fs.inodes[helloIno]
	assert(inode.Size == uint64(len(content)), "size matches")
	assert(len(inode.Blocks) == 1, "one block for small file")

	// Read back
	data, ok := fs.ReadFile(helloIno)
	assert(ok, "read hello.txt")
	assert(string(data) == "Hello, filesystem!", "content matches")

	// Write larger content (needs multiple blocks)
	bigContent := make([]byte, BlockSize*2+100) // 8292 bytes
	for i := range bigContent {
		bigContent[i] = byte('A' + i%26)
	}
	ok = fs.WriteFile(readmeIno, bigContent)
	assert(ok, "write large file")
	assert(fs.inodes[readmeIno].Size == uint64(len(bigContent)), "large size")
	assert(len(fs.inodes[readmeIno].Blocks) == 3, "3 blocks for 8292 bytes")

	// Delete file
	freesBefore := fs.bitmap.FreeCount()
	ok = fs.DeleteFile(1, "hello.txt")
	assert(ok, "delete hello.txt")
	assert(fs.bitmap.FreeCount() == freesBefore+1, "block freed on delete")

	// Deleted file is gone
	_, ok = fs.ReadFile(helloIno)
	assert(!ok, "deleted file unreadable")

	fmt.Printf("   Created hello.txt (inode %d) and README.md (inode %d)\n", helloIno, readmeIno)
	fmt.Printf("   hello.txt: %d bytes, %d block\n", len(content), 1)
	fmt.Printf("   README.md: %d bytes, %d blocks\n", len(bigContent), 3)
	fmt.Printf("   Deleted hello.txt: block freed, inode removed\n")
	fmt.Printf("   Free blocks: %d / %d\n", fs.bitmap.FreeCount(), TotalBlocks)
}

func testPathResolution() {
	fmt.Println("\n5. Path resolution:")

	fs := NewSimpleFS()

	// Build directory tree: /usr/bin/ and /etc/
	usrIno, ok := fs.CreateDir(1, "usr", 0o755)
	assert(ok, "create /usr")
	binIno, ok := fs.CreateDir(usrIno, "bin", 0o755)
	assert(ok, "create /usr/bin")
	etcIno, ok := fs.CreateDir(1, "etc", 0o755)
	assert(ok, "create /etc")

	// Create files
	bashIno, ok := fs.CreateFile(binIno, "bash", 0o755)
	assert(ok, "create /usr/bin/bash")
	confIno, ok := fs.CreateFile(etcIno, "hosts", 0o644)
	assert(ok, "create /etc/hosts")

	// Resolve paths
	ino, ok := fs.ResolvePath("/")
	assert(ok && ino == 1, "resolve /")

	ino, ok = fs.ResolvePath("/usr")
	assert(ok && ino == usrIno, "resolve /usr")

	ino, ok = fs.ResolvePath("/usr/bin")
	assert(ok && ino == binIno, "resolve /usr/bin")

	ino, ok = fs.ResolvePath("/usr/bin/bash")
	assert(ok && ino == bashIno, "resolve /usr/bin/bash")

	ino, ok = fs.ResolvePath("/etc/hosts")
	assert(ok && ino == confIno, "resolve /etc/hosts")

	_, ok = fs.ResolvePath("/usr/lib")
	assert(!ok, "resolve /usr/lib fails")

	_, ok = fs.ResolvePath("/nonexistent/path")
	assert(!ok, "resolve nonexistent fails")

	fmt.Printf("   /              -> inode %d\n", uint32(1))
	fmt.Printf("   /usr           -> inode %d\n", usrIno)
	fmt.Printf("   /usr/bin       -> inode %d\n", binIno)
	fmt.Printf("   /usr/bin/bash  -> inode %d\n", bashIno)
	fmt.Printf("   /etc/hosts     -> inode %d\n", confIno)
	fmt.Println("   /usr/lib       -> NOT FOUND")
}

// ── VFS Interface ────────────────────────────────────────────────────
// The Virtual Filesystem Switch is the kernel's abstraction layer.
// All filesystem types implement the same interface. This allows
// the kernel to handle ext4, XFS, NFS, etc. uniformly.

type VFSOps interface {
	Name() string
	Lookup(parentIno uint32, name string) (uint32, bool)
	Create(parentIno uint32, name string, mode uint16) (uint32, bool)
	Read(ino uint32) ([]byte, bool)
	Write(ino uint32, data []byte) bool
	Unlink(parentIno uint32, name string) bool
}

// SimpleFS implements VFSOps
func (fs *SimpleFS) Name() string { return "simplefs" }
func (fs *SimpleFS) Lookup(parentIno uint32, name string) (uint32, bool) {
	dir, ok := fs.dirs[parentIno]
	if !ok {
		return 0, false
	}
	return dir.Lookup(name)
}
func (fs *SimpleFS) Create(parentIno uint32, name string, mode uint16) (uint32, bool) {
	return fs.CreateFile(parentIno, name, mode)
}
func (fs *SimpleFS) Read(ino uint32) ([]byte, bool) {
	return fs.ReadFile(ino)
}
func (fs *SimpleFS) Write(ino uint32, data []byte) bool {
	return fs.WriteFile(ino, data)
}
func (fs *SimpleFS) Unlink(parentIno uint32, name string) bool {
	return fs.DeleteFile(parentIno, name)
}

func testVFSInterface() {
	fmt.Println("\n6. VFS (Virtual Filesystem Switch) interface:")

	// Use VFS interface — the caller doesn't know the underlying FS type
	var vfs VFSOps = NewSimpleFS()

	assert(vfs.Name() == "simplefs", "VFS name")

	// Create through VFS
	ino, ok := vfs.Create(1, "test.txt", 0o644)
	assert(ok, "VFS create")

	// Write through VFS
	ok = vfs.Write(ino, []byte("VFS layer works"))
	assert(ok, "VFS write")

	// Read through VFS
	data, ok := vfs.Read(ino)
	assert(ok && string(data) == "VFS layer works", "VFS read")

	// Lookup through VFS
	foundIno, ok := vfs.Lookup(1, "test.txt")
	assert(ok && foundIno == ino, "VFS lookup")

	// Delete through VFS
	ok = vfs.Unlink(1, "test.txt")
	assert(ok, "VFS unlink")

	_, ok = vfs.Lookup(1, "test.txt")
	assert(!ok, "VFS: deleted file gone")

	fmt.Println("   VFS abstracts filesystem type behind a common interface:")
	fmt.Println("   - Lookup(parent, name) -> inode")
	fmt.Println("   - Create(parent, name, mode) -> inode")
	fmt.Println("   - Read(inode) -> data")
	fmt.Println("   - Write(inode, data)")
	fmt.Println("   - Unlink(parent, name)")
	fmt.Println("   Real VFS also handles: mount, stat, readdir, fsync, ioctl")
	fmt.Println("   All of ext4, XFS, btrfs, NFS, tmpfs implement this interface")
}

// ── Helpers ──────────────────────────────────────────────────────────

func assert(cond bool, msg string) {
	if !cond {
		panic("FAIL: " + msg)
	}
}
