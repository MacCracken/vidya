// Vidya — IPC in TypeScript
//
// In-memory simulation: shared memory, pipe, named channel.

const SHM_REGION_CAP = 4;
const SHM_BYTES = 64;
const PIPE_CAP = 8;
const CHAN_CAP = 4;
const CHAN_QUEUE_CAP = 8;

// Uint8Array storage wraps silently (300 → 44, -1 → 255): reject non-bytes.
const isByte = (v: number): boolean => Number.isInteger(v) && v >= 0 && v <= 0xFF;

class Ipc {
  shm: Uint8Array[] = Array.from({ length: SHM_REGION_CAP }, () => new Uint8Array(SHM_BYTES));
  pipe = new Uint8Array(PIPE_CAP);
  pipeHead = 0;
  pipeCount = 0;
  chanOpen = new Array<boolean>(CHAN_CAP).fill(false);
  chanQueue: bigint[][] = Array.from({ length: CHAN_CAP }, () => new Array<bigint>(CHAN_QUEUE_CAP).fill(0n));
  chanCount = new Array<number>(CHAN_CAP).fill(0);

  shmWrite(region: number, offset: number, byte: number): boolean {
    if (region < 0 || region >= SHM_REGION_CAP || offset < 0 || offset >= SHM_BYTES) return false;
    if (!isByte(byte)) return false;
    this.shm[region][offset] = byte;
    return true;
  }

  shmRead(region: number, offset: number): number {
    if (region < 0 || region >= SHM_REGION_CAP || offset < 0 || offset >= SHM_BYTES) return -1;
    return this.shm[region][offset];
  }

  pipeWrite(byte: number): boolean {
    if (this.pipeCount >= PIPE_CAP || !isByte(byte)) return false;
    const tail = (this.pipeHead + this.pipeCount) % PIPE_CAP;
    this.pipe[tail] = byte;
    this.pipeCount++;
    return true;
  }

  pipeRead(): number {
    if (this.pipeCount === 0) return -1;
    const b = this.pipe[this.pipeHead];
    this.pipeHead = (this.pipeHead + 1) % PIPE_CAP;
    this.pipeCount--;
    return b;
  }

  chanListen(endpoint: number): boolean {
    if (endpoint < 0 || endpoint >= CHAN_CAP) return false;
    this.chanOpen[endpoint] = true;
    return true;
  }

  chanSend(dst: number, msg: bigint): boolean {
    if (dst < 0 || dst >= CHAN_CAP || !this.chanOpen[dst]) return false;
    if (this.chanCount[dst] >= CHAN_QUEUE_CAP) return false;
    this.chanQueue[dst][this.chanCount[dst]] = msg;
    this.chanCount[dst]++;
    return true;
  }

  // undefined, not an in-band sentinel: every bigint is a valid message,
  // so a -1n "empty" marker would be indistinguishable from sending -1n.
  chanRecv(endpoint: number): bigint | undefined {
    if (endpoint < 0 || endpoint >= CHAN_CAP || !this.chanOpen[endpoint]) return undefined;
    if (this.chanCount[endpoint] === 0) return undefined;
    const msg = this.chanQueue[endpoint][0];
    for (let k = 0; k < this.chanCount[endpoint] - 1; k++) {
      this.chanQueue[endpoint][k] = this.chanQueue[endpoint][k + 1];
    }
    this.chanCount[endpoint]--;
    return msg;
  }
}

function main(): void {
  const ipc = new Ipc();

  if (!ipc.shmWrite(1, 5, 0xA1)) throw new Error("shm write");
  if (ipc.shmRead(1, 5) !== 0xA1) throw new Error("shm read");
  if (ipc.shmRead(2, 5) !== 0) throw new Error("other region");
  if (ipc.shmWrite(1, 99, 0xFF)) throw new Error("oob write");
  if (ipc.shmRead(1, 99) !== -1) throw new Error("oob read");

  ipc.pipeWrite(65); ipc.pipeWrite(66); ipc.pipeWrite(67);
  if (ipc.pipeRead() !== 65) throw new Error("pipe1");
  if (ipc.pipeRead() !== 66) throw new Error("pipe2");
  if (ipc.pipeRead() !== 67) throw new Error("pipe3");
  if (ipc.pipeRead() !== -1) throw new Error("pipe empty");

  const ipc2 = new Ipc();
  for (let k = 0; k < PIPE_CAP; k++) ipc2.pipeWrite(k + 100);
  if (ipc2.pipeWrite(99)) throw new Error("pipe full not rejected");
  ipc2.pipeRead();
  if (!ipc2.pipeWrite(99)) throw new Error("post-drain failed");

  const ipc3 = new Ipc();
  if (ipc3.chanSend(1, 0xDEADBEEFn)) throw new Error("send to closed");
  ipc3.chanListen(1);
  if (!ipc3.chanSend(1, 0xCAFEn)) throw new Error("send 1");
  if (!ipc3.chanSend(1, 0xBABEn)) throw new Error("send 2");
  if (ipc3.chanRecv(1) !== 0xCAFEn) throw new Error("recv 1");
  if (ipc3.chanRecv(1) !== 0xBABEn) throw new Error("recv 2");
  if (ipc3.chanRecv(1) !== undefined) throw new Error("recv empty");
  if (ipc3.chanRecv(2) !== undefined) throw new Error("recv unopened");
  if (!ipc3.chanSend(1, -1n) || ipc3.chanRecv(1) !== -1n) throw new Error("-1n is a message");
  if (ipc3.pipeWrite(300) || ipc3.shmWrite(0, 0, -1)) throw new Error("non-byte accepted");

  console.log("ipc: 20/20 ok");
}

main();
