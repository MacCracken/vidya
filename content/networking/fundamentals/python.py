# Vidya — Networking Fundamentals in Python
#
# In-memory simulation of TCP socket state machine + lifecycle.

ST_CLOSED = 0
ST_LISTEN = 1
ST_SYN_RCVD = 2
ST_ESTABLISHED = 3
ST_FIN_WAIT = 4

SOCK_CAP = 8
BUF_CAP = 256


class Net:
    def __init__(self):
        self.state = [ST_CLOSED] * SOCK_CAP
        self.port = [0] * SOCK_CAP
        self.peer = [0] * SOCK_CAP
        self.rxbuf = [bytearray() for _ in range(SOCK_CAP)]
        self.port_to_sock = {}
        self.next_free = 1

    def create(self):
        for i in range(self.next_free, SOCK_CAP):
            if self.state[i] == ST_CLOSED and self.port[i] == 0:
                self.next_free = i + 1
                return i
        return 0

    def state_get(self, s):
        if s == 0 or s >= SOCK_CAP:
            return -1
        return self.state[s]

    def bind(self, s, port):
        if s == 0 or s >= SOCK_CAP:
            return False
        if port in self.port_to_sock:
            return False
        if self.port[s] != 0:
            return False
        self.port[s] = port
        self.port_to_sock[port] = s
        return True

    def listen(self, s):
        if s == 0 or s >= SOCK_CAP:
            return False
        if self.state[s] != ST_CLOSED or self.port[s] == 0:
            return False
        self.state[s] = ST_LISTEN
        return True

    def connect(self, client, port):
        if client == 0 or client >= SOCK_CAP:
            return False
        server = self.port_to_sock.get(port, 0)
        if server == 0 or self.state[server] != ST_LISTEN:
            return False
        self.state[client] = ST_ESTABLISHED
        self.state[server] = ST_ESTABLISHED
        self.peer[client] = server
        self.peer[server] = client
        return True

    def send_byte(self, s, b):
        if s == 0 or s >= SOCK_CAP or self.state[s] != ST_ESTABLISHED:
            return False
        peer = self.peer[s]
        if peer == 0 or len(self.rxbuf[peer]) >= BUF_CAP:
            return False
        self.rxbuf[peer].append(b)
        return True

    def recv_byte(self, s):
        if s == 0 or s >= SOCK_CAP:
            return -1
        if self.state[s] not in (ST_ESTABLISHED, ST_FIN_WAIT):
            return -1
        if not self.rxbuf[s]:
            return -1
        return self.rxbuf[s].pop(0)

    def close(self, s):
        if s == 0 or s >= SOCK_CAP or self.state[s] == ST_CLOSED:
            return False
        port = self.port[s]
        if port != 0:
            self.port_to_sock.pop(port, None)
        self.state[s] = ST_CLOSED
        self.port[s] = 0
        self.peer[s] = 0
        return True


def main():
    n = Net()

    srv = n.create()
    assert n.state_get(srv) == ST_CLOSED

    assert n.bind(srv, 8080)
    assert n.listen(srv)
    assert n.state_get(srv) == ST_LISTEN

    cli = n.create()
    assert n.connect(cli, 8080)
    assert n.state_get(cli) == ST_ESTABLISHED
    assert n.state_get(srv) == ST_ESTABLISHED

    assert n.send_byte(cli, 65)
    assert n.send_byte(cli, 66)
    assert n.recv_byte(srv) == 65
    assert n.recv_byte(srv) == 66
    assert n.recv_byte(srv) == -1
    assert n.send_byte(srv, 67)
    assert n.recv_byte(cli) == 67

    assert n.close(cli)
    assert n.state_get(cli) == ST_CLOSED

    srv2 = n.create()
    assert not n.bind(srv2, 8080)

    assert n.recv_byte(cli) == -1

    n.close(srv)
    assert n.bind(srv2, 8080)

    print("networking_fundamentals: 19/19 ok")


main()
