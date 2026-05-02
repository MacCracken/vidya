# Vidya — TLS and Encryption in Python
#
# Simulation of TLS 1.3 handshake state machine + cipher negotiation
# + cert chain verification + AEAD seal/open.

ST_INIT = 0
ST_HELLO_SENT = 1
ST_SERVER_HELLO = 2
ST_CERT_VERIFIED = 3
ST_ESTABLISHED = 4
ST_FAILED = 5

TLS_AES_128_GCM_SHA256 = 0x1301
TLS_AES_256_GCM_SHA384 = 0x1302
TLS_CHACHA20_POLY1305_SHA256 = 0x1303
TLS_RSA_AES_128_CBC_SHA = 0x002F


def is_tls13_cipher(c):
    return c in (TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256)


def pick_cipher(server, client):
    for s in server:
        if is_tls13_cipher(s) and s in client:
            return s
    return 0


def verify_chain(chain, trust):
    if not chain:
        return False
    for i in range(len(chain) - 1):
        if chain[i]["issuer"] != chain[i + 1]["subject"]:
            return False
    last_subj = chain[-1]["subject"]
    return any(c["subject"] == last_subj for c in trust)


def cert_matches_hostname(cert, hostname):
    return cert["subject"] == hostname


def xor_stream(src, key):
    return bytes(b ^ key for b in src)


def compute_tag(buf, key, nonce):
    return (sum(buf) ^ key) ^ nonce


def aead_seal(pt, key, nonce):
    ct = xor_stream(pt, key)
    return ct, compute_tag(pt, key, nonce)


def aead_open(ct, key, nonce, claimed_tag):
    pt = xor_stream(ct, key)
    if compute_tag(pt, key, nonce) != claimed_tag:
        return None
    return pt


class Handshake:
    def __init__(self):
        self.state = ST_INIT
        self.negotiated = 0

    def advance(self, srv, cli, chain, trust, hostname):
        if self.state == ST_INIT:
            self.state = ST_HELLO_SENT
        elif self.state == ST_HELLO_SENT:
            c = pick_cipher(srv, cli)
            if c == 0:
                self.state = ST_FAILED
                return
            self.negotiated = c
            self.state = ST_SERVER_HELLO
        elif self.state == ST_SERVER_HELLO:
            if not verify_chain(chain, trust):
                self.state = ST_FAILED
                return
            if not cert_matches_hostname(chain[0], hostname):
                self.state = ST_FAILED
                return
            self.state = ST_CERT_VERIFIED
        elif self.state == ST_CERT_VERIFIED:
            self.state = ST_ESTABLISHED


def main():
    srv = [TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384]
    cli = [TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256]
    assert pick_cipher(srv, cli) == TLS_AES_128_GCM_SHA256
    assert pick_cipher([TLS_RSA_AES_128_CBC_SHA], cli) == 0

    leaf = {"subject": 100, "issuer": 200}
    inter = {"subject": 200, "issuer": 300}
    root = {"subject": 300, "issuer": 300}
    chain = [leaf, inter, root]
    trust = [root]
    assert verify_chain(chain, trust)
    assert not verify_chain(chain, [{"subject": 999, "issuer": 999}])
    assert not verify_chain([{"subject": 100, "issuer": 100}], trust)

    pt = b"secret message"
    ct, tag = aead_seal(pt, 42, 7)
    dec = aead_open(ct, 42, 7, tag)
    assert dec == pt
    tampered = bytearray(ct); tampered[5] ^= 1
    assert aead_open(bytes(tampered), 42, 7, tag) is None
    assert aead_open(ct, 42, 7, tag ^ 1) is None

    hs = Handshake()
    assert hs.state == ST_INIT
    hs.advance(srv, cli, chain, trust, 100); assert hs.state == ST_HELLO_SENT
    hs.advance(srv, cli, chain, trust, 100); assert hs.state == ST_SERVER_HELLO
    assert hs.negotiated == TLS_AES_128_GCM_SHA256
    hs.advance(srv, cli, chain, trust, 100); assert hs.state == ST_CERT_VERIFIED
    hs.advance(srv, cli, chain, trust, 100); assert hs.state == ST_ESTABLISHED

    hs2 = Handshake()
    hs2.advance(srv, cli, chain, trust, 100)
    hs2.advance(srv, cli, chain, trust, 100)
    hs2.advance(srv, cli, chain, trust, 999)
    assert hs2.state == ST_FAILED

    print("tls_and_encryption: 16/16 ok")


main()
