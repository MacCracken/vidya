// Vidya — TLS and Encryption in TypeScript
//
// Simulation of TLS 1.3 handshake state machine + cipher negotiation
// + cert chain verification + AEAD seal/open.

const ST_INIT = 0;
const ST_HELLO_SENT = 1;
const ST_SERVER_HELLO = 2;
const ST_CERT_VERIFIED = 3;
const ST_ESTABLISHED = 4;
const ST_FAILED = 5;

const TLS_AES_128_GCM_SHA256 = 0x1301;
const TLS_AES_256_GCM_SHA384 = 0x1302;
const TLS_CHACHA20_POLY1305_SHA256 = 0x1303;
const TLS_RSA_AES_128_CBC_SHA = 0x002F;

interface Cert { subject: number; issuer: number; }

function isTls13Cipher(c: number): boolean {
  return c === TLS_AES_128_GCM_SHA256 || c === TLS_AES_256_GCM_SHA384 || c === TLS_CHACHA20_POLY1305_SHA256;
}

function pickCipher(srv: number[], cli: number[]): number {
  for (const s of srv) {
    if (!isTls13Cipher(s)) continue;
    if (cli.includes(s)) return s;
  }
  return 0;
}

function verifyChain(chain: Cert[], trust: Cert[]): boolean {
  if (chain.length === 0) return false;
  for (let i = 0; i < chain.length - 1; i++) {
    if (chain[i].issuer !== chain[i + 1].subject) return false;
  }
  const last = chain[chain.length - 1].subject;
  return trust.some(t => t.subject === last);
}

function certMatchesHostname(c: Cert, h: number): boolean { return c.subject === h; }

function xorStream(src: Uint8Array, key: number): Uint8Array {
  const out = new Uint8Array(src.length);
  for (let i = 0; i < src.length; i++) out[i] = src[i] ^ key;
  return out;
}

function computeTag(buf: Uint8Array, key: number, nonce: number): number {
  let sum = 0;
  for (const b of buf) sum += b;
  return (sum ^ key) ^ nonce;
}

function aeadSeal(pt: Uint8Array, key: number, nonce: number): { ct: Uint8Array; tag: number } {
  return { ct: xorStream(pt, key), tag: computeTag(pt, key, nonce) };
}

function aeadOpen(ct: Uint8Array, key: number, nonce: number, tag: number): Uint8Array | null {
  const pt = xorStream(ct, key);
  if (computeTag(pt, key, nonce) !== tag) return null;
  return pt;
}

class Handshake {
  state = ST_INIT;
  negotiated = 0;

  advance(srv: number[], cli: number[], chain: Cert[], trust: Cert[], hostname: number): void {
    switch (this.state) {
      case ST_INIT: this.state = ST_HELLO_SENT; break;
      case ST_HELLO_SENT: {
        const c = pickCipher(srv, cli);
        if (c === 0) { this.state = ST_FAILED; return; }
        this.negotiated = c;
        this.state = ST_SERVER_HELLO;
        break;
      }
      case ST_SERVER_HELLO: {
        if (!verifyChain(chain, trust)) { this.state = ST_FAILED; return; }
        if (!certMatchesHostname(chain[0], hostname)) { this.state = ST_FAILED; return; }
        this.state = ST_CERT_VERIFIED;
        break;
      }
      case ST_CERT_VERIFIED: this.state = ST_ESTABLISHED; break;
    }
  }
}

function bytesEq(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function main(): void {
  const srv = [TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384];
  const cli = [TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256];
  if (pickCipher(srv, cli) !== TLS_AES_128_GCM_SHA256) throw new Error("pick");
  if (pickCipher([TLS_RSA_AES_128_CBC_SHA], cli) !== 0) throw new Error("legacy");

  const leaf: Cert = { subject: 100, issuer: 200 };
  const inter: Cert = { subject: 200, issuer: 300 };
  const root: Cert = { subject: 300, issuer: 300 };
  const chain = [leaf, inter, root];
  const trust = [root];
  if (!verifyChain(chain, trust)) throw new Error("chain");
  if (verifyChain(chain, [{ subject: 999, issuer: 999 }])) throw new Error("bad trust");
  if (verifyChain([{ subject: 100, issuer: 100 }], trust)) throw new Error("ss");

  const pt = new Uint8Array(Buffer.from("secret message"));
  const { ct, tag } = aeadSeal(pt, 42, 7);
  const dec = aeadOpen(ct, 42, 7, tag);
  if (!dec || !bytesEq(dec, pt)) throw new Error("roundtrip");
  const tampered = new Uint8Array(ct);
  tampered[5] ^= 1;
  if (aeadOpen(tampered, 42, 7, tag) !== null) throw new Error("tampered");
  if (aeadOpen(ct, 42, 7, tag ^ 1) !== null) throw new Error("wrong tag");

  const hs = new Handshake();
  if (hs.state !== ST_INIT) throw new Error("init");
  hs.advance(srv, cli, chain, trust, 100);
  if (hs.state !== ST_HELLO_SENT) throw new Error("hello sent");
  hs.advance(srv, cli, chain, trust, 100);
  if (hs.state !== ST_SERVER_HELLO) throw new Error("server hello");
  if (hs.negotiated !== TLS_AES_128_GCM_SHA256) throw new Error("negotiated");
  hs.advance(srv, cli, chain, trust, 100);
  if (hs.state !== ST_CERT_VERIFIED) throw new Error("cert verified");
  hs.advance(srv, cli, chain, trust, 100);
  if (hs.state !== ST_ESTABLISHED) throw new Error("established");

  const hs2 = new Handshake();
  hs2.advance(srv, cli, chain, trust, 100);
  hs2.advance(srv, cli, chain, trust, 100);
  hs2.advance(srv, cli, chain, trust, 999);
  if (hs2.state !== ST_FAILED) throw new Error("hostname mismatch");

  console.log("tls_and_encryption: 16/16 ok");
}

main();
