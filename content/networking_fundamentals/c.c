/* Vidya — Networking Fundamentals in C
 *
 * In-memory simulation of TCP socket state machine + lifecycle.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define SOCK_CAP 8
#define BUF_CAP  256

enum { ST_CLOSED = 0, ST_LISTEN, ST_SYN_RCVD, ST_ESTABLISHED, ST_FIN_WAIT };

typedef struct {
    int state[SOCK_CAP];
    uint16_t port[SOCK_CAP];
    int peer[SOCK_CAP];
    uint8_t rxbuf[SOCK_CAP][BUF_CAP];
    int rxlen[SOCK_CAP];
    int port_to_sock[65536];
    int next_free;
} Net;

static void net_init(Net *n) { memset(n, 0, sizeof *n); n->next_free = 1; }

static int sock_create(Net *n) {
    for (int i = n->next_free; i < SOCK_CAP; i++) {
        if (n->state[i] == ST_CLOSED && n->port[i] == 0) {
            n->next_free = i + 1;
            return i;
        }
    }
    return 0;
}

static int state_get(const Net *n, int s) {
    if (s == 0 || s >= SOCK_CAP) return -1;
    return n->state[s];
}

static int sock_bind(Net *n, int s, uint16_t port) {
    if (s == 0 || s >= SOCK_CAP) return 0;
    if (n->port_to_sock[port] != 0) return 0;
    if (n->port[s] != 0) return 0;
    n->port[s] = port;
    n->port_to_sock[port] = s;
    return 1;
}

static int sock_listen(Net *n, int s) {
    if (s == 0 || s >= SOCK_CAP) return 0;
    if (n->state[s] != ST_CLOSED || n->port[s] == 0) return 0;
    n->state[s] = ST_LISTEN;
    return 1;
}

static int sock_connect(Net *n, int client, uint16_t port) {
    if (client == 0 || client >= SOCK_CAP) return 0;
    int server = n->port_to_sock[port];
    if (server == 0 || n->state[server] != ST_LISTEN) return 0;
    n->state[client] = ST_ESTABLISHED;
    n->state[server] = ST_ESTABLISHED;
    n->peer[client] = server;
    n->peer[server] = client;
    return 1;
}

static int sock_send_byte(Net *n, int s, uint8_t b) {
    if (s == 0 || s >= SOCK_CAP || n->state[s] != ST_ESTABLISHED) return 0;
    int peer = n->peer[s];
    if (peer == 0 || n->rxlen[peer] >= BUF_CAP) return 0;
    n->rxbuf[peer][n->rxlen[peer]++] = b;
    return 1;
}

static int sock_recv_byte(Net *n, int s) {
    if (s == 0 || s >= SOCK_CAP) return -1;
    int st = n->state[s];
    if (st != ST_ESTABLISHED && st != ST_FIN_WAIT) return -1;
    if (n->rxlen[s] == 0) return -1;
    uint8_t b = n->rxbuf[s][0];
    for (int i = 0; i < n->rxlen[s] - 1; i++) n->rxbuf[s][i] = n->rxbuf[s][i + 1];
    n->rxlen[s]--;
    return (int)b;
}

static int sock_close(Net *n, int s) {
    if (s == 0 || s >= SOCK_CAP || n->state[s] == ST_CLOSED) return 0;
    if (n->port[s] != 0) n->port_to_sock[n->port[s]] = 0;
    n->state[s] = ST_CLOSED;
    n->port[s] = 0;
    n->peer[s] = 0;
    return 1;
}

int main(void) {
    Net n;
    net_init(&n);

    int srv = sock_create(&n);
    assert(state_get(&n, srv) == ST_CLOSED);

    assert(sock_bind(&n, srv, 8080));
    assert(sock_listen(&n, srv));
    assert(state_get(&n, srv) == ST_LISTEN);

    int cli = sock_create(&n);
    assert(sock_connect(&n, cli, 8080));
    assert(state_get(&n, cli) == ST_ESTABLISHED);
    assert(state_get(&n, srv) == ST_ESTABLISHED);

    assert(sock_send_byte(&n, cli, 65));
    assert(sock_send_byte(&n, cli, 66));
    assert(sock_recv_byte(&n, srv) == 65);
    assert(sock_recv_byte(&n, srv) == 66);
    assert(sock_recv_byte(&n, srv) == -1);
    assert(sock_send_byte(&n, srv, 67));
    assert(sock_recv_byte(&n, cli) == 67);

    assert(sock_close(&n, cli));
    assert(state_get(&n, cli) == ST_CLOSED);

    int srv2 = sock_create(&n);
    assert(!sock_bind(&n, srv2, 8080));

    assert(sock_recv_byte(&n, cli) == -1);

    sock_close(&n, srv);
    assert(sock_bind(&n, srv2, 8080));

    printf("networking_fundamentals: 19/19 ok\n");
    return 0;
}
