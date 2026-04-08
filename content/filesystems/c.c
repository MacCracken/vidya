/* Filesystems — C Implementation
 *
 * Demonstrates filesystem concepts with an in-memory filesystem:
 *   1. Inode struct layout with direct block pointers
 *   2. Block device with bitmap allocator
 *   3. Directory entries mapping names to inode numbers
 *   4. VFS-like operations: create, write, read, unlink, stat
 *   5. File descriptor table
 *
 * This mirrors how ext4 works internally, simplified to the essentials.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Constants ───────────────────────────────────────────────────────── */

#define BLOCK_SIZE     64      /* small blocks for demo    */
#define TOTAL_BLOCKS   64      /* 64 blocks total          */
#define DIRECT_BLOCKS  4       /* direct block pointers    */
#define MAX_INODES     16
#define MAX_DIR_ENTRIES 16
#define MAX_OPEN_FILES  8
#define NAME_MAX_LEN   32

/* ── Block Device ────────────────────────────────────────────────────── */

typedef struct {
    uint8_t  blocks[TOTAL_BLOCKS][BLOCK_SIZE];
    uint8_t  bitmap[TOTAL_BLOCKS]; /* 1 = allocated */
    unsigned used;
} block_device_t;

static void bdev_init(block_device_t *dev) {
    memset(dev, 0, sizeof(*dev));
}

static int bdev_alloc(block_device_t *dev) {
    for (unsigned i = 0; i < TOTAL_BLOCKS; i++) {
        if (!dev->bitmap[i]) {
            dev->bitmap[i] = 1;
            dev->used++;
            return (int)i;
        }
    }
    return -1; /* disk full */
}

static void bdev_free(block_device_t *dev, unsigned idx) {
    if (dev->bitmap[idx]) {
        dev->bitmap[idx] = 0;
        memset(dev->blocks[idx], 0, BLOCK_SIZE);
        dev->used--;
    }
}

static void bdev_write(block_device_t *dev, unsigned idx,
                        const void *data, size_t len, unsigned offset) {
    size_t end = offset + len;
    if (end > BLOCK_SIZE) end = BLOCK_SIZE;
    size_t to_write = end - offset;
    memcpy(&dev->blocks[idx][offset], data, to_write);
}

static const uint8_t *bdev_read(const block_device_t *dev, unsigned idx) {
    return dev->blocks[idx];
}

/* ── Inode ───────────────────────────────────────────────────────────── */

typedef enum { FT_NONE, FT_REGULAR, FT_DIRECTORY } file_type_t;

typedef struct {
    uint32_t    ino;
    file_type_t file_type;
    uint64_t    size;
    int         blocks[DIRECT_BLOCKS]; /* block indices, -1 = unallocated */
    uint32_t    nlink;
    uint16_t    mode;
    int         active; /* whether this inode slot is in use */
} inode_t;

static void inode_init(inode_t *i, uint32_t ino, file_type_t ft, uint16_t mode) {
    i->ino = ino;
    i->file_type = ft;
    i->size = 0;
    for (int b = 0; b < DIRECT_BLOCKS; b++) i->blocks[b] = -1;
    i->nlink = 1;
    i->mode = mode;
    i->active = 1;
}

static void inode_print(const inode_t *i) {
    const char *kind = (i->file_type == FT_REGULAR) ? "file" : "dir";
    printf("ino=%u %s size=%lu nlink=%u blocks=[",
           i->ino, kind, (unsigned long)i->size, i->nlink);
    int first = 1;
    for (int b = 0; b < DIRECT_BLOCKS; b++) {
        if (i->blocks[b] >= 0) {
            if (!first) printf(",");
            printf("%d", i->blocks[b]);
            first = 0;
        }
    }
    printf("]");
}

/* ── Directory Entry ─────────────────────────────────────────────────── */

typedef struct {
    char     name[NAME_MAX_LEN];
    uint32_t ino;
    int      active;
} dir_entry_t;

/* ── Open File Description ───────────────────────────────────────────── */

typedef struct {
    uint32_t ino;
    uint64_t offset;
    int      active;
} open_file_t;

/* ── Filesystem ──────────────────────────────────────────────────────── */

typedef struct {
    block_device_t dev;
    inode_t        inodes[MAX_INODES];
    unsigned       inode_count;
    uint32_t       next_ino;

    /* Directory storage: flat array (simplified; real FS stores in blocks) */
    dir_entry_t    root_entries[MAX_DIR_ENTRIES];
    unsigned       root_entry_count;

    open_file_t    open_files[MAX_OPEN_FILES];
} simple_fs_t;

static inode_t *fs_find_inode(simple_fs_t *fs, uint32_t ino) {
    for (unsigned i = 0; i < fs->inode_count; i++) {
        if (fs->inodes[i].active && fs->inodes[i].ino == ino)
            return &fs->inodes[i];
    }
    return NULL;
}

static void fs_init(simple_fs_t *fs) {
    memset(fs, 0, sizeof(*fs));
    bdev_init(&fs->dev);
    fs->next_ino = 1;
    /* Root directory (inode 1) */
    inode_init(&fs->inodes[0], 1, FT_DIRECTORY, 0755);
    fs->inode_count = 1;
    fs->next_ino = 2;

    /* . and .. entries */
    strcpy(fs->root_entries[0].name, ".");
    fs->root_entries[0].ino = 1;
    fs->root_entries[0].active = 1;
    strcpy(fs->root_entries[1].name, "..");
    fs->root_entries[1].ino = 1;
    fs->root_entries[1].active = 1;
    fs->root_entry_count = 2;
}

static uint32_t fs_create(simple_fs_t *fs, const char *name) {
    assert(fs->inode_count < MAX_INODES);
    assert(fs->root_entry_count < MAX_DIR_ENTRIES);

    /* Check for duplicate */
    for (unsigned i = 0; i < fs->root_entry_count; i++) {
        assert(!(fs->root_entries[i].active &&
                 strcmp(fs->root_entries[i].name, name) == 0));
    }

    uint32_t ino = fs->next_ino++;
    unsigned idx = fs->inode_count++;
    inode_init(&fs->inodes[idx], ino, FT_REGULAR, 0644);

    unsigned eidx = fs->root_entry_count++;
    strncpy(fs->root_entries[eidx].name, name, NAME_MAX_LEN - 1);
    fs->root_entries[eidx].ino = ino;
    fs->root_entries[eidx].active = 1;

    return ino;
}

static uint32_t fs_open(simple_fs_t *fs, uint32_t ino) {
    assert(fs_find_inode(fs, ino) != NULL);
    for (unsigned i = 0; i < MAX_OPEN_FILES; i++) {
        if (!fs->open_files[i].active) {
            fs->open_files[i].ino = ino;
            fs->open_files[i].offset = 0;
            fs->open_files[i].active = 1;
            /* fd = slot index + 3 (reserve 0=stdin, 1=stdout, 2=stderr) */
            return i + 3;
        }
    }
    assert(0 && "too many open files");
    return 0;
}

/* Locate open file by fd (fd = slot index + 3) */
static open_file_t *fs_get_of(simple_fs_t *fs, uint32_t fd) {
    unsigned idx = fd - 3;
    assert(idx < MAX_OPEN_FILES);
    assert(fs->open_files[idx].active);
    return &fs->open_files[idx];
}

static size_t fs_write(simple_fs_t *fs, uint32_t fd, const void *data, size_t len) {
    open_file_t *of = fs_get_of(fs, fd);
    inode_t *inode = fs_find_inode(fs, of->ino);
    assert(inode != NULL);

    const uint8_t *src = (const uint8_t *)data;
    size_t pos = (size_t)of->offset;
    size_t written = 0;

    while (written < len) {
        unsigned block_idx = (unsigned)(pos / BLOCK_SIZE);
        unsigned block_offset = (unsigned)(pos % BLOCK_SIZE);

        if (block_idx >= DIRECT_BLOCKS) break;

        /* Allocate block on demand */
        if (inode->blocks[block_idx] < 0) {
            int blk = bdev_alloc(&fs->dev);
            assert(blk >= 0); /* disk full */
            inode->blocks[block_idx] = blk;
        }

        size_t chunk = len - written;
        if (chunk > BLOCK_SIZE - block_offset)
            chunk = BLOCK_SIZE - block_offset;

        bdev_write(&fs->dev, (unsigned)inode->blocks[block_idx],
                   src + written, chunk, block_offset);
        pos += chunk;
        written += chunk;
    }

    if (pos > inode->size) inode->size = pos;
    of->offset = pos;
    return written;
}

static size_t fs_read(simple_fs_t *fs, uint32_t fd, void *buf, size_t count) {
    open_file_t *of = fs_get_of(fs, fd);
    inode_t *inode = fs_find_inode(fs, of->ino);
    assert(inode != NULL);

    uint8_t *dst = (uint8_t *)buf;
    size_t pos = (size_t)of->offset;
    size_t nread = 0;

    while (nread < count && pos < inode->size) {
        unsigned block_idx = (unsigned)(pos / BLOCK_SIZE);
        unsigned block_offset = (unsigned)(pos % BLOCK_SIZE);

        if (inode->blocks[block_idx] < 0) break; /* sparse hole */

        size_t avail = inode->size - pos;
        size_t chunk = count - nread;
        if (chunk > avail) chunk = avail;
        if (chunk > BLOCK_SIZE - block_offset)
            chunk = BLOCK_SIZE - block_offset;

        const uint8_t *block_data = bdev_read(&fs->dev,
                                               (unsigned)inode->blocks[block_idx]);
        memcpy(dst + nread, block_data + block_offset, chunk);
        pos += chunk;
        nread += chunk;
    }

    of->offset = pos;
    return nread;
}

static void fs_close(simple_fs_t *fs, uint32_t fd) {
    unsigned idx = fd - 3;
    if (idx < MAX_OPEN_FILES)
        fs->open_files[idx].active = 0;
}

static void fs_unlink(simple_fs_t *fs, const char *name) {
    /* Find and remove directory entry */
    uint32_t ino = 0;
    for (unsigned i = 0; i < fs->root_entry_count; i++) {
        if (fs->root_entries[i].active &&
            strcmp(fs->root_entries[i].name, name) == 0) {
            ino = fs->root_entries[i].ino;
            fs->root_entries[i].active = 0;
            break;
        }
    }
    assert(ino != 0);

    /* Decrement link count */
    inode_t *inode = fs_find_inode(fs, ino);
    assert(inode != NULL);
    inode->nlink--;

    if (inode->nlink == 0) {
        /* Free all blocks */
        for (int b = 0; b < DIRECT_BLOCKS; b++) {
            if (inode->blocks[b] >= 0) {
                bdev_free(&fs->dev, (unsigned)inode->blocks[b]);
            }
        }
        inode->active = 0;
    }
}

static uint32_t fs_lookup(const simple_fs_t *fs, const char *name) {
    for (unsigned i = 0; i < fs->root_entry_count; i++) {
        if (fs->root_entries[i].active &&
            strcmp(fs->root_entries[i].name, name) == 0) {
            return fs->root_entries[i].ino;
        }
    }
    return 0; /* not found */
}

/* ── Main ────────────────────────────────────────────────────────────── */

int main(void) {
    printf("Filesystems — in-memory inode-based filesystem:\n\n");

    simple_fs_t fs;
    fs_init(&fs);

    /* ── 1. Create files ─────────────────────────────────────────────── */
    printf("1. Creating files in root directory:\n");
    uint32_t hello_ino = fs_create(&fs, "hello.txt");
    uint32_t data_ino  = fs_create(&fs, "data.bin");
    printf("   Created hello.txt (ino=%u), data.bin (ino=%u)\n", hello_ino, data_ino);
    assert(hello_ino == 2);
    assert(data_ino == 3);

    /* ── 2. Write data ───────────────────────────────────────────────── */
    printf("\n2. Writing data:\n");
    uint32_t fd1 = fs_open(&fs, hello_ino);
    const char *msg = "Hello, filesystem world! This is inode-based storage.";
    size_t w1 = fs_write(&fs, fd1, msg, strlen(msg));
    printf("   Wrote %zu bytes to hello.txt (fd=%u)\n", w1, fd1);
    assert(w1 == strlen(msg));

    uint32_t fd2 = fs_open(&fs, data_ino);
    uint8_t big_data[200];
    memset(big_data, 0xAB, sizeof(big_data));
    size_t w2 = fs_write(&fs, fd2, big_data, sizeof(big_data));
    unsigned blocks_span = (unsigned)((w2 + BLOCK_SIZE - 1) / BLOCK_SIZE);
    printf("   Wrote %zu bytes to data.bin (fd=%u, spans %u blocks)\n", w2, fd2, blocks_span);

    /* ── 3. Read data back ───────────────────────────────────────────── */
    printf("\n3. Reading data:\n");
    fs_close(&fs, fd1);
    fd1 = fs_open(&fs, hello_ino);
    char readbuf[100];
    memset(readbuf, 0, sizeof(readbuf));
    size_t nread = fs_read(&fs, fd1, readbuf, sizeof(readbuf));
    printf("   Read %zu bytes from hello.txt: \"%s\"\n", nread, readbuf);
    assert(nread == strlen(msg));
    assert(strcmp(readbuf, msg) == 0);

    /* ── 4. stat ─────────────────────────────────────────────────────── */
    printf("\n4. stat (inode metadata):\n");
    inode_t *hi = fs_find_inode(&fs, hello_ino);
    inode_t *di = fs_find_inode(&fs, data_ino);
    assert(hi != NULL && di != NULL);
    printf("   hello.txt -> "); inode_print(hi); printf("\n");
    printf("   data.bin  -> "); inode_print(di); printf("\n");
    assert(hi->size == strlen(msg));
    assert(hi->nlink == 1);

    /* ── 5. Directory listing ────────────────────────────────────────── */
    printf("\n5. readdir (/):\n");
    for (unsigned i = 0; i < fs.root_entry_count; i++) {
        if (!fs.root_entries[i].active) continue;
        inode_t *ino = fs_find_inode(&fs, fs.root_entries[i].ino);
        assert(ino != NULL);
        const char *kind = (ino->file_type == FT_DIRECTORY) ? "d" : "-";
        printf("   %s %5lu %s\n", kind, (unsigned long)ino->size,
               fs.root_entries[i].name);
    }

    /* Verify lookup */
    assert(fs_lookup(&fs, "hello.txt") == hello_ino);
    assert(fs_lookup(&fs, "data.bin") == data_ino);
    assert(fs_lookup(&fs, "nonexistent") == 0);

    /* ── 6. Unlink ───────────────────────────────────────────────────── */
    printf("\n6. Unlink (delete) hello.txt:\n");
    unsigned blocks_before = fs.dev.used;
    fs_unlink(&fs, "hello.txt");
    printf("   Blocks freed: %u -> %u (%u freed)\n",
           blocks_before, fs.dev.used, blocks_before - fs.dev.used);
    printf("   Inode %u exists: %s\n", hello_ino,
           fs_find_inode(&fs, hello_ino) ? "true" : "false");
    assert(fs_find_inode(&fs, hello_ino) == NULL);
    assert(fs_lookup(&fs, "hello.txt") == 0);
    assert(fs.dev.used < blocks_before);

    /* ── 7. Disk usage ───────────────────────────────────────────────── */
    printf("\n7. Disk usage:\n");
    printf("   Total blocks: %d\n", TOTAL_BLOCKS);
    printf("   Used blocks: %u\n", fs.dev.used);
    printf("   Free blocks: %u\n", TOTAL_BLOCKS - fs.dev.used);
    unsigned active_inodes = 0;
    for (unsigned i = 0; i < fs.inode_count; i++) {
        if (fs.inodes[i].active) active_inodes++;
    }
    printf("   Inodes used: %u\n", active_inodes);

    /* ── 8. Inode struct layout ──────────────────────────────────────── */
    printf("\n8. Data structure sizes:\n");
    printf("   inode_t:      %zu bytes\n", sizeof(inode_t));
    printf("   dir_entry_t:  %zu bytes\n", sizeof(dir_entry_t));
    printf("   open_file_t:  %zu bytes\n", sizeof(open_file_t));
    printf("   block_device: %zu bytes (%d blocks x %d bytes)\n",
           sizeof(block_device_t), TOTAL_BLOCKS, BLOCK_SIZE);

    printf("\nAll assertions passed.\n");
    return 0;
}
