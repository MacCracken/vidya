// Vidya — Compression (LZ77-shaped) in TypeScript
//
// Two-byte token stream matching cyrius.cyr:
//   [0, BYTE]      literal
//   [OFFSET, LEN]  match: copy LEN bytes from out[pos - OFFSET..]
// Greedy brute-force match-finder, 255-byte window: O(n·W·L) for window W
// and max match L (both 255 here), so linear in n with a large constant —
// it would be O(n^2) only with an unbounded window. Decoder enforces an
// output-cap and rejects back-references before the start of output.
// Match copy is byte-by-byte so offset=1 acts as RLE.

const MIN_MATCH = 3;
const MAX_MATCH = 255;
const WIN_SIZE = 255;

function matchLenAt(src: Uint8Array, hist: number, pos: number): number {
  let n = 0;
  const max = Math.min(src.length - pos, MAX_MATCH);
  while (n < max && src[hist + n] === src[pos + n]) n++;
  return n;
}

function bestMatch(src: Uint8Array, pos: number): { off: number; len: number } | null {
  const winStart = Math.max(0, pos - WIN_SIZE);
  let bestOff = 0;
  let bestLen = 0;
  for (let i = winStart; i < pos; i++) {
    const n = matchLenAt(src, i, pos);
    if (n > bestLen) { bestLen = n; bestOff = pos - i; }
  }
  if (bestLen >= MIN_MATCH) return { off: bestOff, len: bestLen };
  return null;
}

function encode(src: Uint8Array): Uint8Array {
  const tok: number[] = [];
  let pos = 0;
  while (pos < src.length) {
    const m = bestMatch(src, pos);
    if (m) {
      tok.push(m.off, m.len);
      pos += m.len;
    } else {
      tok.push(0, src[pos]);
      pos++;
    }
  }
  return new Uint8Array(tok);
}

// Returns null on bomb-guard trigger or a bad back-reference, else output.
function decode(tok: Uint8Array, outCap: number): Uint8Array | null {
  const out: number[] = [];
  for (let i = 0; i + 1 < tok.length; i += 2) {
    const b0 = tok[i];
    const b1 = tok[i + 1];
    if (b0 === 0) {
      if (out.length + 1 > outCap) return null;
      out.push(b1);
    } else {
      if (out.length + b1 > outCap) return null;
      // Offset reaching before the first output byte: out[negative] is
      // undefined, which a Uint8Array silently stores as 0. Reject it.
      if (b0 > out.length) return null;
      for (let k = 0; k < b1; k++) out.push(out[out.length - b0]);
    }
  }
  return new Uint8Array(out);
}

function eq(a: Uint8Array, b: Uint8Array, label: string): void {
  if (a.length !== b.length) throw new Error(`${label}: length ${a.length} vs ${b.length}`);
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) throw new Error(`${label}: diff at ${i}`);
  }
}

function str(s: string): Uint8Array {
  return new Uint8Array(Buffer.from(s, "utf-8"));
}

function main(): void {
  // 1. Round-trip with substring match
  const s1 = str("ABCABCABC");
  const t1 = encode(s1);
  if (t1.length === 0) throw new Error("encoded length > 0");
  eq(decode(t1, 512)!, s1, "ABCABCABC roundtrip");

  // 2. Overlapping (RLE)
  const s2 = str("AAAAAAAA");
  const t2 = encode(s2);
  eq(decode(t2, 512)!, s2, "AAAAAAAA roundtrip");
  if (t2.length >= s2.length) throw new Error("AAAAAAAA actually compresses");

  // 3. Mostly literals
  const s3 = str("Hello, World!");
  const t3 = encode(s3);
  eq(decode(t3, 512)!, s3, "Hello roundtrip");

  // 4. Bomb guard
  const bomb = new Uint8Array([1, 200]);
  if (decode(bomb, 10) !== null) throw new Error("bomb guard rejects oversize");

  // 4b. Back-reference before the start of output
  if (decode(new Uint8Array([5, 4]), 512) !== null) throw new Error("offset past start rejected");
  if (decode(new Uint8Array([0, 65, 2, 3]), 512) !== null) throw new Error("offset 2 with 1 byte of history rejected");

  // 5. Empty input
  const t5 = encode(new Uint8Array(0));
  if (t5.length !== 0) throw new Error("empty input → zero tokens");
  const d5 = decode(new Uint8Array(0), 512);
  if (d5 === null || d5.length !== 0) throw new Error("empty tokens → zero output");

  console.log("compression: 10/10 ok");
}

main();
