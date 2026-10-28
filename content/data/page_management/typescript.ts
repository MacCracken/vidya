// Vidya — Page Management in TypeScript
//
// Fixed-size 4KB pages, single file. Header at offset 0; page 0 reserved
// as null sentinel; data pages at PAGE_SZ + num * PAGE_SZ. Free list is
// a stack with `next` pointer at byte offset 8 of each freed page.
// Mirrors the cyrius reference's test surface, plus check 7: the header is
// written back after every alloc/free, and short page reads are errors.

import * as fs from "fs";

const PAGE_SZ = 4096;
const MAGIC = 0x50415452;
const H_PGCOUNT = 8;
const H_FREEHEAD = 16;
const FP_NEXT = 8;

function pageOffset(num: bigint): number {
  return Number(BigInt(PAGE_SZ) + num * BigInt(PAGE_SZ));
}

interface Header {
  pageCount: bigint;
  freeHead: bigint;
}

function hdrInit(): Header {
  return { pageCount: 1n, freeHead: 0n };
}

function hdrToBytes(h: Header): Buffer {
  const buf = Buffer.alloc(PAGE_SZ);
  buf.writeUInt32LE(MAGIC, 0);
  buf.writeBigUInt64LE(h.pageCount, H_PGCOUNT);
  buf.writeBigUInt64LE(h.freeHead, H_FREEHEAD);
  return buf;
}

function hdrVerify(buf: Buffer): boolean {
  return buf.readUInt32LE(0) === MAGIC;
}

function hdrLoad(buf: Buffer): Header {
  return {
    pageCount: buf.readBigUInt64LE(H_PGCOUNT),
    freeHead: buf.readBigUInt64LE(H_FREEHEAD),
  };
}

function pageRead(fd: number, num: bigint): Buffer {
  const buf = Buffer.alloc(PAGE_SZ);
  // A short read (truncated file, page past EOF) leaves zeros in buf — and a
  // zero `next` silently ends the free list. Treat it as corruption.
  const n = fs.readSync(fd, buf, 0, PAGE_SZ, pageOffset(num));
  if (n !== PAGE_SZ) throw new Error(`short read of page ${num}: ${n}/${PAGE_SZ} bytes`);
  return buf;
}

function hdrStore(fd: number, h: Header): void {
  fs.writeSync(fd, hdrToBytes(h), 0, PAGE_SZ, 0);
}

function pageWrite(fd: number, num: bigint, buf: Buffer): void {
  fs.writeSync(fd, buf, 0, PAGE_SZ, pageOffset(num));
}

function pageAlloc(fd: number, h: Header): bigint {
  if (h.freeHead !== 0n) {
    const fh = h.freeHead;
    const buf = pageRead(fd, fh);
    h.freeHead = buf.readBigUInt64LE(FP_NEXT);
    hdrStore(fd, h);
    return fh;
  }
  const num = h.pageCount;
  h.pageCount = h.pageCount + 1n;
  pageWrite(fd, num, Buffer.alloc(PAGE_SZ));
  hdrStore(fd, h); // header follows every page_count change (else: orphaned pages)
  return num;
}

function pageFree(fd: number, h: Header, num: bigint): void {
  const buf = Buffer.alloc(PAGE_SZ);
  buf.writeBigUInt64LE(h.freeHead, FP_NEXT);
  pageWrite(fd, num, buf);
  h.freeHead = num;
  hdrStore(fd, h);
}

function assertEq(got: bigint, want: bigint, label: string): void {
  if (got !== want) {
    throw new Error(`${label}: got ${got} want ${want}`);
  }
}

function main(): void {
  const path = "/tmp/vidya_page_ts.bin";
  try { fs.unlinkSync(path); } catch {}

  const fd = fs.openSync(path, "w+");
  const h = hdrInit();
  hdrStore(fd, h);

  // 1-2. header
  const rh = Buffer.alloc(PAGE_SZ);
  fs.readSync(fd, rh, 0, PAGE_SZ, 0);
  if (!hdrVerify(rh)) throw new Error("magic ok failed");
  const loaded = hdrLoad(rh);
  assertEq(loaded.pageCount, 1n, "pgcount starts at 1");

  // 3-4. alloc
  const p1 = pageAlloc(fd, h);
  assertEq(p1, 1n, "first alloc = 1");
  const p2 = pageAlloc(fd, h);
  assertEq(p2, 2n, "second alloc = 2");

  // 5. roundtrip
  const buf = Buffer.alloc(PAGE_SZ);
  buf.writeBigUInt64LE(42n, 0);
  pageWrite(fd, p1, buf);
  const rb = pageRead(fd, p1);
  const got = rb.readBigUInt64LE(0);
  assertEq(got, 42n, "read back 42");

  // 6. free + reuse
  pageFree(fd, h, p2);
  const p3 = pageAlloc(fd, h);
  assertEq(p3, 2n, "reused freed page");

  // 7. the on-disk header tracks every alloc/free
  const dh = Buffer.alloc(PAGE_SZ);
  fs.readSync(fd, dh, 0, PAGE_SZ, 0);
  assertEq(hdrLoad(dh).pageCount, h.pageCount, "on-disk pgcount = in-memory");

  fs.closeSync(fd);
  fs.unlinkSync(path);
  console.log("page_management: 7/7 ok");
}

main();
