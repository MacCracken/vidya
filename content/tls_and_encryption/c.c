/* Vidya — TLS and Encryption in C
 *
 * Simulation of TLS 1.3 handshake state machine + cipher negotiation
 * + cert chain verification + AEAD seal/open.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum { ST_INIT, ST_HELLO_SENT, ST_SERVER_HELLO, ST_CERT_VERIFIED, ST_ESTABLISHED, ST_FAILED };

#define TLS_AES_128_GCM_SHA256 0x1301
#define TLS_AES_256_GCM_SHA384 0x1302
#define TLS_CHACHA20_POLY1305_SHA256 0x1303
#define TLS_RSA_AES_128_CBC_SHA 0x002F

typedef struct { uint64_t subject, issuer; } Cert;

static int is_tls13_cipher(uint16_t c) {
    return c == TLS_AES_128_GCM_SHA256 || c == TLS_AES_256_GCM_SHA384 || c == TLS_CHACHA20_POLY1305_SHA256;
}

static uint16_t pick_cipher(const uint16_t *server, int sn, const uint16_t *client, int cn) {
    for (int i = 0; i < sn; i++) {
        if (!is_tls13_cipher(server[i])) continue;
        for (int j = 0; j < cn; j++) {
            if (server[i] == client[j]) return server[i];
        }
    }
    return 0;
}

static int verify_chain(const Cert *chain, int n_certs, const Cert *trust, int n_roots) {
    if (n_certs == 0) return 0;
    for (int i = 0; i < n_certs - 1; i++) {
        if (chain[i].issuer != chain[i + 1].subject) return 0;
    }
    uint64_t last = chain[n_certs - 1].subject;
    for (int i = 0; i < n_roots; i++) {
        if (trust[i].subject == last) return 1;
    }
    return 0;
}

static int cert_matches_hostname(const Cert *c, uint64_t h) { return c->subject == h; }

static void xor_stream(uint8_t *out, const uint8_t *src, int len, uint8_t key) {
    for (int i = 0; i < len; i++) out[i] = src[i] ^ key;
}

static uint64_t compute_tag(const uint8_t *buf, int len, uint64_t key, uint64_t nonce) {
    uint64_t sum = 0;
    for (int i = 0; i < len; i++) sum += buf[i];
    return (sum ^ key) ^ nonce;
}

static uint64_t aead_seal(const uint8_t *pt, int len, uint8_t key, uint64_t nonce, uint8_t *ct_out) {
    xor_stream(ct_out, pt, len, key);
    return compute_tag(pt, len, key, nonce);
}

static int aead_open(const uint8_t *ct, int len, uint8_t key, uint64_t nonce, uint64_t tag, uint8_t *pt_out) {
    xor_stream(pt_out, ct, len, key);
    if (compute_tag(pt_out, len, key, nonce) != tag) return -1;
    return len;
}

typedef struct { int state; uint16_t negotiated; } Handshake;

static void hs_advance(Handshake *hs, const uint16_t *srv, int sn, const uint16_t *cli, int cn,
                       const Cert *chain, int n_certs, const Cert *trust, int n_roots, uint64_t hostname) {
    switch (hs->state) {
        case ST_INIT: hs->state = ST_HELLO_SENT; break;
        case ST_HELLO_SENT: {
            uint16_t c = pick_cipher(srv, sn, cli, cn);
            if (c == 0) { hs->state = ST_FAILED; break; }
            hs->negotiated = c;
            hs->state = ST_SERVER_HELLO;
            break;
        }
        case ST_SERVER_HELLO: {
            if (!verify_chain(chain, n_certs, trust, n_roots)) { hs->state = ST_FAILED; break; }
            if (!cert_matches_hostname(&chain[0], hostname)) { hs->state = ST_FAILED; break; }
            hs->state = ST_CERT_VERIFIED;
            break;
        }
        case ST_CERT_VERIFIED: hs->state = ST_ESTABLISHED; break;
    }
}

int main(void) {
    uint16_t srv[] = { TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384 };
    uint16_t cli[] = { TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256 };
    assert(pick_cipher(srv, 2, cli, 2) == TLS_AES_128_GCM_SHA256);
    uint16_t srv_legacy[] = { TLS_RSA_AES_128_CBC_SHA };
    assert(pick_cipher(srv_legacy, 1, cli, 2) == 0);

    Cert leaf = {100, 200}, inter = {200, 300}, root = {300, 300};
    Cert chain[] = { leaf, inter, root };
    Cert trust[] = { root };
    assert(verify_chain(chain, 3, trust, 1));
    Cert bad_trust[] = { {999, 999} };
    assert(!verify_chain(chain, 3, bad_trust, 1));
    Cert ss[] = { {100, 100} };
    assert(!verify_chain(ss, 1, trust, 1));

    const uint8_t *pt = (const uint8_t *)"secret message";
    int pt_len = 14;
    uint8_t ct[64], dec[64];
    uint64_t tag = aead_seal(pt, pt_len, 42, 7, ct);
    int dlen = aead_open(ct, pt_len, 42, 7, tag, dec);
    assert(dlen == pt_len);
    assert(memcmp(dec, pt, pt_len) == 0);
    ct[5] ^= 1;
    assert(aead_open(ct, pt_len, 42, 7, tag, dec) == -1);
    ct[5] ^= 1;
    assert(aead_open(ct, pt_len, 42, 7, tag ^ 1, dec) == -1);

    Handshake hs = {ST_INIT, 0};
    assert(hs.state == ST_INIT);
    hs_advance(&hs, srv, 2, cli, 2, chain, 3, trust, 1, 100);
    assert(hs.state == ST_HELLO_SENT);
    hs_advance(&hs, srv, 2, cli, 2, chain, 3, trust, 1, 100);
    assert(hs.state == ST_SERVER_HELLO);
    assert(hs.negotiated == TLS_AES_128_GCM_SHA256);
    hs_advance(&hs, srv, 2, cli, 2, chain, 3, trust, 1, 100);
    assert(hs.state == ST_CERT_VERIFIED);
    hs_advance(&hs, srv, 2, cli, 2, chain, 3, trust, 1, 100);
    assert(hs.state == ST_ESTABLISHED);

    Handshake hs2 = {ST_INIT, 0};
    hs_advance(&hs2, srv, 2, cli, 2, chain, 3, trust, 1, 100);
    hs_advance(&hs2, srv, 2, cli, 2, chain, 3, trust, 1, 100);
    hs_advance(&hs2, srv, 2, cli, 2, chain, 3, trust, 1, 999);
    assert(hs2.state == ST_FAILED);

    printf("tls_and_encryption: 16/16 ok\n");
    return 0;
}
