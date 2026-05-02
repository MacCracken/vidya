// Vidya — Serialization in TypeScript
//
// Varint (LEB128) + length-prefix framing + stream parser + DoS guards.

const MAX_VARINT_BYTES = 10;
const MAX_MSG_SIZE = 1024n;

function encodeVarint(value: bigint): Uint8Array {
  const out: number[] = [];
  while (value >= 128n) {
    out.push(Number((value & 0x7Fn) | 0x80n));
    value >>= 7n;
  }
  out.push(Number(value & 0x7Fn));
  return new Uint8Array(out);
}

function decodeVarint(buf: Uint8Array): { value: bigint; consumed: number } | null {
  let value = 0n;
  let shift = 0n;
  for (let i = 0; i < MAX_VARINT_BYTES; i++) {
    if (i >= buf.length) return null;
    const b = buf[i];
    value += BigInt(b & 0x7F) << shift;
    if ((b & 0x80) === 0) return { value, consumed: i + 1 };
    shift += 7n;
  }
  return null;
}

function encodeFrame(payload: Uint8Array): Uint8Array {
  const hdr = encodeVarint(BigInt(payload.length));
  const out = new Uint8Array(hdr.length + payload.length);
  out.set(hdr, 0);
  out.set(payload, hdr.length);
  return out;
}

function decodeFrame(buf: Uint8Array, maxMsg: bigint): { payload: Uint8Array; consumed: number } | null {
  const r = decodeVarint(buf);
  if (!r) return null;
  if (r.value > maxMsg) return null;
  const total = r.consumed + Number(r.value);
  if (total > buf.length) return null;
  return { payload: buf.subarray(r.consumed, total), consumed: total };
}

function bytesEq(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function main(): void {
  let e = encodeVarint(0n);
  if (e.length !== 1 || e[0] !== 0) throw new Error("v0");
  e = encodeVarint(127n);
  if (e.length !== 1 || e[0] !== 0x7F) throw new Error("v127");
  e = encodeVarint(128n);
  if (e.length !== 2 || e[0] !== 0x80 || e[1] !== 0x01) throw new Error("v128");
  if (encodeVarint(16383n).length !== 2) throw new Error("v16383");
  if (encodeVarint(16384n).length !== 3) throw new Error("v16384");

  const enc = encodeVarint(1234567890n);
  const r = decodeVarint(enc);
  if (!r || r.value !== 1234567890n || r.consumed !== enc.length) throw new Error("roundtrip");

  const bomb = new Uint8Array(11).fill(0xFF);
  if (decodeVarint(bomb) !== null) throw new Error("overflow");

  const payload = new Uint8Array(Buffer.from("hello, world"));
  const frame = encodeFrame(payload);
  if (frame.length !== 13 || frame[0] !== 12) throw new Error("frame");
  const fr = decodeFrame(frame, MAX_MSG_SIZE);
  if (!fr || fr.consumed !== 13 || !bytesEq(fr.payload, payload)) throw new Error("frame rt");

  const parts = [
    encodeFrame(new Uint8Array(Buffer.from("AAA"))),
    encodeFrame(new Uint8Array(Buffer.from("BBBB"))),
    encodeFrame(new Uint8Array(Buffer.from("CCCCC"))),
  ];
  const total = parts.reduce((n, p) => n + p.length, 0);
  const stream = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { stream.set(p, off); off += p.length; }
  let pos = 0, msgs = 0;
  while (pos < stream.length) {
    const dr = decodeFrame(stream.subarray(pos), MAX_MSG_SIZE);
    if (!dr) break;
    msgs++;
    pos += dr.consumed;
  }
  if (msgs !== 3) throw new Error("stream");

  const trunc = new Uint8Array([100, 0x42, 0x43, 0x44, 0x45, 0x46]);
  if (decodeFrame(trunc, MAX_MSG_SIZE) !== null) throw new Error("trunc");

  const over = encodeVarint(9999n);
  if (decodeFrame(over, MAX_MSG_SIZE) !== null) throw new Error("oversize");

  console.log("serialization: 19/19 ok");
}

main();
