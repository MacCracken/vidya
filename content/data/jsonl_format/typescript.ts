// Vidya — JSON Lines (JSONL) in TypeScript
//
// In-memory JSONL primitives mirroring cyrius.cyr.

function appendRecord(buf: number[], rec: number[]): void {
  for (const b of rec) buf.push(b);
  buf.push(0x0A);
}

interface LineIndex {
  offsets: number[];
  lengths: number[];
}

function buildIndex(buf: number[]): LineIndex {
  const offs: number[] = [];
  const lens: number[] = [];
  let start = 0;
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] === 0x0A) {
      offs.push(start);
      lens.push(i - start);
      start = i + 1;
    }
  }
  if (start < buf.length) {
    offs.push(start);
    lens.push(buf.length - start);
  }
  return { offsets: offs, lengths: lens };
}

// Returns escaped bytes, or null on bounds-check failure.
// RFC 8259 §7: quote, backslash AND every control byte U+0000-U+001F
// MUST be escaped. This minimal encoder has short forms for \n \t \r
// only and no \uXXXX form, so it refuses the other control bytes rather
// than emit invalid JSON. (In real TypeScript, JSON.stringify(str) is the
// complete escaper.) Each accepted byte expands to at most 2, so the
// 2x bound below is exact.
function jsonEscape(src: number[], dstCap: number): number[] | null {
  if (src.length * 2 > dstCap) return null;
  const out: number[] = [];
  for (const c of src) {
    if (c === 0x22) { out.push(0x5C, 0x22); }
    else if (c === 0x5C) { out.push(0x5C, 0x5C); }
    else if (c === 0x0A) { out.push(0x5C, 0x6E); }
    else if (c === 0x09) { out.push(0x5C, 0x74); }
    else if (c === 0x0D) { out.push(0x5C, 0x72); }
    else if (c < 0x20) { return null; }      // would need \u00XX
    else { out.push(c); }
  }
  return out;
}

function jsonUnescape(src: number[]): number[] {
  const out: number[] = [];
  let i = 0;
  while (i < src.length) {
    if (src[i] === 0x5C && i + 1 < src.length) {
      const n = src[i + 1];
      if (n === 0x22) { out.push(0x22); i += 2; }
      else if (n === 0x5C) { out.push(0x5C); i += 2; }
      else if (n === 0x6E) { out.push(0x0A); i += 2; }
      else if (n === 0x74) { out.push(0x09); i += 2; }
      else if (n === 0x72) { out.push(0x0D); i += 2; }
      else { out.push(src[i]); i++; }
    } else {
      out.push(src[i]);
      i++;
    }
  }
  return out;
}

function eqBytes(a: number[], b: number[], label: string): void {
  if (a.length !== b.length) throw new Error(`${label}: length ${a.length} vs ${b.length}`);
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) throw new Error(`${label}: diff at ${i}`);
}

function strBytes(s: string): number[] {
  return Array.from(Buffer.from(s, "utf-8"));
}

function main(): void {
  // Test 1
  const buf: number[] = [];
  appendRecord(buf, strBytes(`{"id":1}`));
  appendRecord(buf, strBytes(`{"id":2}`));
  appendRecord(buf, strBytes(`{"id":3}`));
  const idx = buildIndex(buf);
  if (idx.offsets.length !== 3) throw new Error("3 records indexed");
  if (idx.lengths[2] !== 8) throw new Error("third record length 8");
  const third = buf.slice(idx.offsets[2], idx.offsets[2] + idx.lengths[2]);
  eqBytes(third, strBytes(`{"id":3}`), "third record bytes");

  // Test 2: no trailing newline
  const buf2 = buf.slice();
  if (buf2[buf2.length - 1] === 0x0A) buf2.pop();
  const idx2 = buildIndex(buf2);
  if (idx2.offsets.length !== 3) throw new Error("3 records indexed without trailing newline");

  // Test 3: escape
  const s3 = [0x73, 0x61, 0x79, 0x20, 0x22, 0x68, 0x69, 0x22,
              0x09, 0x0A, 0x0D, 0x5C];
  const esc = jsonEscape(s3, 256);
  if (esc === null || esc.length !== 18) throw new Error("escape produces 18");
  // Same bytes as the platform's complete encoder for this input
  const viaJson = strBytes(JSON.stringify(Buffer.from(s3).toString("latin1")).slice(1, -1));
  eqBytes(esc, viaJson, "matches JSON.stringify");

  // Test 3b: other control bytes (here \b, 0x01) are refused, never copied raw
  if (jsonEscape([0x61, 0x08, 0x01, 0x62], 256) !== null) throw new Error("raw control byte refused");

  // Test 4: bounds check
  const s4 = [0x22, 0x22, 0x22, 0x22];
  if (jsonEscape(s4, 4) !== null) throw new Error("escape refuses tight cap");

  // Test 5: roundtrip
  const un = jsonUnescape(esc);
  if (un.length !== 12) throw new Error("unescape recovers 12");
  eqBytes(un, s3, "round-trip bytes");

  console.log("jsonl_format: 10/10 ok");
}

main();
