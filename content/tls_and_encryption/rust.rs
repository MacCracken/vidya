// Vidya — TLS and Encryption in Rust
//
// Simulation of TLS 1.3 handshake state machine + cipher
// negotiation + cert chain verification + AEAD seal/open.

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum HsState { Init, HelloSent, ServerHello, CertVerified, Established, Failed }

const TLS_AES_128_GCM_SHA256: u16 = 0x1301;
const TLS_AES_256_GCM_SHA384: u16 = 0x1302;
const TLS_CHACHA20_POLY1305_SHA256: u16 = 0x1303;
const TLS_RSA_AES_128_CBC_SHA: u16 = 0x002F;

fn is_tls13_cipher(c: u16) -> bool {
    matches!(c, TLS_AES_128_GCM_SHA256 | TLS_AES_256_GCM_SHA384 | TLS_CHACHA20_POLY1305_SHA256)
}

fn pick_cipher(server: &[u16], client: &[u16]) -> u16 {
    for &s in server {
        if is_tls13_cipher(s) && client.contains(&s) {
            return s;
        }
    }
    0
}

#[derive(Copy, Clone)]
struct Cert { subject: u64, issuer: u64 }

fn verify_chain(chain: &[Cert], trust: &[Cert]) -> bool {
    if chain.is_empty() { return false; }
    for i in 0..chain.len() - 1 {
        if chain[i].issuer != chain[i + 1].subject { return false; }
    }
    let last_subj = chain[chain.len() - 1].subject;
    trust.iter().any(|c| c.subject == last_subj)
}

fn cert_matches_hostname(cert: &Cert, hostname: u64) -> bool {
    cert.subject == hostname
}

fn xor_stream(out: &mut [u8], src: &[u8], key: u8) {
    for (o, &b) in out.iter_mut().zip(src.iter()) { *o = b ^ key; }
}

fn compute_tag(buf: &[u8], key: u64, nonce: u64) -> u64 {
    let sum: u64 = buf.iter().map(|&b| b as u64).sum();
    (sum ^ key) ^ nonce
}

fn aead_seal(pt: &[u8], key: u8, nonce: u64, ct_out: &mut [u8]) -> u64 {
    xor_stream(ct_out, pt, key);
    compute_tag(pt, key as u64, nonce)
}

fn aead_open(ct: &[u8], key: u8, nonce: u64, claimed_tag: u64, pt_out: &mut [u8]) -> i32 {
    xor_stream(pt_out, ct, key);
    let actual = compute_tag(&pt_out[..ct.len()], key as u64, nonce);
    if actual != claimed_tag { return -1; }
    ct.len() as i32
}

struct Handshake { state: HsState, negotiated: u16 }

impl Handshake {
    fn new() -> Self { Handshake { state: HsState::Init, negotiated: 0 } }

    fn advance(&mut self, srv: &[u16], cli: &[u16], chain: &[Cert], trust: &[Cert], hostname: u64) {
        match self.state {
            HsState::Init => self.state = HsState::HelloSent,
            HsState::HelloSent => {
                let c = pick_cipher(srv, cli);
                if c == 0 { self.state = HsState::Failed; return; }
                self.negotiated = c;
                self.state = HsState::ServerHello;
            }
            HsState::ServerHello => {
                if !verify_chain(chain, trust) { self.state = HsState::Failed; return; }
                if !cert_matches_hostname(&chain[0], hostname) { self.state = HsState::Failed; return; }
                self.state = HsState::CertVerified;
            }
            HsState::CertVerified => self.state = HsState::Established,
            _ => {}
        }
    }
}

fn main() {
    // Cipher negotiation
    let srv = [TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384];
    let cli = [TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256];
    assert_eq!(pick_cipher(&srv, &cli), TLS_AES_128_GCM_SHA256);
    let srv_legacy = [TLS_RSA_AES_128_CBC_SHA];
    assert_eq!(pick_cipher(&srv_legacy, &cli), 0);

    // Cert chain
    let leaf = Cert { subject: 100, issuer: 200 };
    let inter = Cert { subject: 200, issuer: 300 };
    let root = Cert { subject: 300, issuer: 300 };
    let chain = [leaf, inter, root];
    let trust = [root];
    assert!(verify_chain(&chain, &trust));
    let bad_trust = [Cert { subject: 999, issuer: 999 }];
    assert!(!verify_chain(&chain, &bad_trust));
    let ss_leaf = Cert { subject: 100, issuer: 100 };
    assert!(!verify_chain(&[ss_leaf], &trust));

    // AEAD
    let pt = b"secret message";
    let mut ct = vec![0u8; pt.len()];
    let mut dec = vec![0u8; pt.len()];
    let tag = aead_seal(pt, 42, 7, &mut ct);
    let dlen = aead_open(&ct, 42, 7, tag, &mut dec);
    assert_eq!(dlen, pt.len() as i32);
    assert_eq!(&dec[..], pt);
    let mut tampered_ct = ct.clone();
    tampered_ct[5] ^= 1;
    assert_eq!(aead_open(&tampered_ct, 42, 7, tag, &mut dec), -1);
    assert_eq!(aead_open(&ct, 42, 7, tag ^ 1, &mut dec), -1);

    // Handshake happy path
    let mut hs = Handshake::new();
    assert_eq!(hs.state, HsState::Init);
    hs.advance(&srv, &cli, &chain, &trust, 100);
    assert_eq!(hs.state, HsState::HelloSent);
    hs.advance(&srv, &cli, &chain, &trust, 100);
    assert_eq!(hs.state, HsState::ServerHello);
    assert_eq!(hs.negotiated, TLS_AES_128_GCM_SHA256);
    hs.advance(&srv, &cli, &chain, &trust, 100);
    assert_eq!(hs.state, HsState::CertVerified);
    hs.advance(&srv, &cli, &chain, &trust, 100);
    assert_eq!(hs.state, HsState::Established);

    // Hostname mismatch
    let mut hs2 = Handshake::new();
    hs2.advance(&srv, &cli, &chain, &trust, 100);
    hs2.advance(&srv, &cli, &chain, &trust, 100);
    hs2.advance(&srv, &cli, &chain, &trust, 999);
    assert_eq!(hs2.state, HsState::Failed);

    println!("tls_and_encryption: 16/16 ok");
}
