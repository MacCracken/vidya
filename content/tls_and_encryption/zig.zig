// Vidya — TLS and Encryption in Zig
//
// Simulation of TLS 1.3 handshake state machine + cipher negotiation
// + cert chain verification + a *demo* seal/open pair (NOT AEAD — see
// the disclaimer above weakChecksum below).

const std = @import("std");

const HsState = enum(u8) { Init, HelloSent, ServerHello, CertVerified, Established, Failed };

const TLS_AES_128_GCM_SHA256: u16 = 0x1301;
const TLS_AES_256_GCM_SHA384: u16 = 0x1302;
const TLS_CHACHA20_POLY1305_SHA256: u16 = 0x1303;
const TLS_RSA_AES_128_CBC_SHA: u16 = 0x002F;

const Cert = struct { subject: u64, issuer: u64 };

fn isTls13Cipher(c: u16) bool {
    return c == TLS_AES_128_GCM_SHA256 or c == TLS_AES_256_GCM_SHA384 or c == TLS_CHACHA20_POLY1305_SHA256;
}

fn pickCipher(srv: []const u16, cli: []const u16) u16 {
    for (srv) |s| {
        if (!isTls13Cipher(s)) continue;
        for (cli) |c| if (s == c) return s;
    }
    return 0;
}

fn verifyChain(chain: []const Cert, trust: []const Cert) bool {
    if (chain.len == 0) return false;
    var i: usize = 0;
    while (i < chain.len - 1) : (i += 1) {
        if (chain[i].issuer != chain[i + 1].subject) return false;
    }
    const last = chain[chain.len - 1].subject;
    for (trust) |t| if (t.subject == last) return true;
    return false;
}

fn certMatchesHostname(c: Cert, h: u64) bool { return c.subject == h; }

fn xorStream(out: []u8, src: []const u8, key: u8) void {
    for (src, 0..) |b, i| out[i] = b ^ key;
}

// ---------------------------------------------------------------------------
// NOT AUTHENTICATED ENCRYPTION. Do not use any of the three functions below to
// protect real data, ever.
//
// weakChecksum is a byte SUM. Addition is commutative, so the checksum is
// permutation-invariant: reorder the bytes of a message and the value does not
// move. That is exactly the property a real MAC must not have.
//
// Concretely, under this file's demo parameters (key 42, nonce 7):
//     "transfer 10 usd"  -> byte sum 1362 -> tag 1407
//     "transfer u0 1sd"  -> byte sum 1362 -> tag 1407   (bytes 9 and 12 swapped)
// Same tag, different message: demoOpen accepts the second one as genuine. A
// forger who can reorder bytes gets a "verified" message for free. (A single
// flipped byte usually does move the sum, which is why the tamper assertion in
// main() still fails to open — but "usually catches one flip" is not
// authentication.)
//
// What this IS for: the *structural shape* of an AEAD — seal produces
// ciphertext plus a tag, open recomputes the tag over what it decrypted and
// refuses to return plaintext unless the tag matches. Real code gets that shape
// from AES-GCM or ChaCha20-Poly1305 in a vetted library; see concept.toml.
// ---------------------------------------------------------------------------

fn weakChecksum(buf: []const u8, key: u64, nonce: u64) u64 {
    var sum: u64 = 0;
    for (buf) |b| sum += b;
    return (sum ^ key) ^ nonce;
}

fn demoSeal(pt: []const u8, key: u8, nonce: u64, ct_out: []u8) u64 {
    xorStream(ct_out, pt, key);
    return weakChecksum(pt, key, nonce);
}

fn demoOpen(ct: []const u8, key: u8, nonce: u64, tag: u64, pt_out: []u8) i32 {
    xorStream(pt_out, ct, key);
    if (weakChecksum(pt_out[0..ct.len], key, nonce) != tag) return -1;
    return @intCast(ct.len);
}

const Handshake = struct {
    state: HsState = .Init,
    negotiated: u16 = 0,

    fn advance(self: *Handshake, srv: []const u16, cli: []const u16,
               chain: []const Cert, trust: []const Cert, hostname: u64) void {
        switch (self.state) {
            .Init => self.state = .HelloSent,
            .HelloSent => {
                const c = pickCipher(srv, cli);
                if (c == 0) { self.state = .Failed; return; }
                self.negotiated = c;
                self.state = .ServerHello;
            },
            .ServerHello => {
                if (!verifyChain(chain, trust)) { self.state = .Failed; return; }
                if (!certMatchesHostname(chain[0], hostname)) { self.state = .Failed; return; }
                self.state = .CertVerified;
            },
            .CertVerified => self.state = .Established,
            else => {},
        }
    }
};

pub fn main() !void {
    const srv = [_]u16{ TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384 };
    const cli = [_]u16{ TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256 };
    if (pickCipher(&srv, &cli) != TLS_AES_128_GCM_SHA256) return error.Pick;
    if (pickCipher(&[_]u16{TLS_RSA_AES_128_CBC_SHA}, &cli) != 0) return error.Legacy;

    const leaf = Cert{ .subject = 100, .issuer = 200 };
    const inter = Cert{ .subject = 200, .issuer = 300 };
    const root = Cert{ .subject = 300, .issuer = 300 };
    const chain = [_]Cert{ leaf, inter, root };
    const trust = [_]Cert{root};
    if (!verifyChain(&chain, &trust)) return error.Chain;
    if (verifyChain(&chain, &[_]Cert{Cert{ .subject = 999, .issuer = 999 }})) return error.BadTrust;
    if (verifyChain(&[_]Cert{Cert{ .subject = 100, .issuer = 100 }}, &trust)) return error.SS;

    const pt = "secret message";
    var ct: [64]u8 = undefined;
    var dec: [64]u8 = undefined;
    const tag = demoSeal(pt, 42, 7, ct[0..pt.len]);
    const dlen = demoOpen(ct[0..pt.len], 42, 7, tag, dec[0..pt.len]);
    if (dlen != @as(i32, pt.len)) return error.RoundtripLen;
    if (!std.mem.eql(u8, dec[0..pt.len], pt)) return error.RoundtripBytes;
    ct[5] ^= 1;
    if (demoOpen(ct[0..pt.len], 42, 7, tag, dec[0..pt.len]) != -1) return error.Tampered;
    ct[5] ^= 1;
    if (demoOpen(ct[0..pt.len], 42, 7, tag ^ 1, dec[0..pt.len]) != -1) return error.WrongTag;

    var hs = Handshake{};
    if (hs.state != .Init) return error.Init;
    hs.advance(&srv, &cli, &chain, &trust, 100);
    if (hs.state != .HelloSent) return error.HelloSent;
    hs.advance(&srv, &cli, &chain, &trust, 100);
    if (hs.state != .ServerHello) return error.ServerHello;
    if (hs.negotiated != TLS_AES_128_GCM_SHA256) return error.Negotiated;
    hs.advance(&srv, &cli, &chain, &trust, 100);
    if (hs.state != .CertVerified) return error.CertVerified;
    hs.advance(&srv, &cli, &chain, &trust, 100);
    if (hs.state != .Established) return error.Established;

    var hs2 = Handshake{};
    hs2.advance(&srv, &cli, &chain, &trust, 100);
    hs2.advance(&srv, &cli, &chain, &trust, 100);
    hs2.advance(&srv, &cli, &chain, &trust, 999);
    if (hs2.state != .Failed) return error.HostnameMismatch;

    std.debug.print("tls_and_encryption: 16/16 ok\n", .{});
}
