// Vidya — Networking Fundamentals in Rust
//
// In-memory simulation of TCP socket state machine + lifecycle.
// 6-state subset: CLOSED, LISTEN, SYN_RCVD, ESTABLISHED, FIN_WAIT, CLOSED.

use std::collections::HashMap;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum State { Closed, Listen, SynRcvd, Established, FinWait }

const SOCK_CAP: usize = 8;
const BUF_CAP: usize = 256;

struct Net {
    state: [State; SOCK_CAP],
    port: [u16; SOCK_CAP],
    peer: [usize; SOCK_CAP],
    rxbuf: Vec<Vec<u8>>,
    port_to_sock: HashMap<u16, usize>,
    next_free: usize,
}

impl Net {
    fn new() -> Self {
        Net {
            state: [State::Closed; SOCK_CAP],
            port: [0; SOCK_CAP],
            peer: [0; SOCK_CAP],
            rxbuf: (0..SOCK_CAP).map(|_| Vec::with_capacity(BUF_CAP)).collect(),
            port_to_sock: HashMap::new(),
            next_free: 1,
        }
    }

    fn create(&mut self) -> usize {
        for i in 1..SOCK_CAP {
            if self.state[i] == State::Closed && self.port[i] == 0 && i >= self.next_free {
                self.next_free = i + 1;
                return i;
            }
        }
        0
    }

    fn state_get(&self, s: usize) -> i32 {
        if s == 0 || s >= SOCK_CAP { return -1; }
        self.state[s] as i32
    }

    fn bind(&mut self, s: usize, port: u16) -> bool {
        if s == 0 || s >= SOCK_CAP { return false; }
        if self.port_to_sock.contains_key(&port) { return false; }
        if self.port[s] != 0 { return false; }
        self.port[s] = port;
        self.port_to_sock.insert(port, s);
        true
    }

    fn listen(&mut self, s: usize) -> bool {
        if s == 0 || s >= SOCK_CAP { return false; }
        if self.state[s] != State::Closed { return false; }
        if self.port[s] == 0 { return false; }
        self.state[s] = State::Listen;
        true
    }

    fn connect(&mut self, client: usize, port: u16) -> bool {
        if client == 0 || client >= SOCK_CAP { return false; }
        let server = match self.port_to_sock.get(&port) { Some(&s) => s, None => return false };
        if self.state[server] != State::Listen { return false; }
        self.state[client] = State::Established;
        self.state[server] = State::Established;
        self.peer[client] = server;
        self.peer[server] = client;
        true
    }

    fn send_byte(&mut self, s: usize, b: u8) -> bool {
        if s == 0 || s >= SOCK_CAP || self.state[s] != State::Established { return false; }
        let peer = self.peer[s];
        if peer == 0 || self.rxbuf[peer].len() >= BUF_CAP { return false; }
        self.rxbuf[peer].push(b);
        true
    }

    fn recv_byte(&mut self, s: usize) -> i32 {
        if s == 0 || s >= SOCK_CAP { return -1; }
        let st = self.state[s];
        if st != State::Established && st != State::FinWait { return -1; }
        if self.rxbuf[s].is_empty() { return -1; }
        self.rxbuf[s].remove(0) as i32
    }

    fn close(&mut self, s: usize) -> bool {
        if s == 0 || s >= SOCK_CAP { return false; }
        if self.state[s] == State::Closed { return false; }
        let port = self.port[s];
        if port != 0 { self.port_to_sock.remove(&port); }
        self.state[s] = State::Closed;
        self.port[s] = 0;
        self.peer[s] = 0;
        true
    }
}

fn main() {
    let mut n = Net::new();

    let srv = n.create();
    assert_eq!(n.state_get(srv), State::Closed as i32);

    assert!(n.bind(srv, 8080));
    assert!(n.listen(srv));
    assert_eq!(n.state_get(srv), State::Listen as i32);

    let cli = n.create();
    assert!(n.connect(cli, 8080));
    assert_eq!(n.state_get(cli), State::Established as i32);
    assert_eq!(n.state_get(srv), State::Established as i32);

    assert!(n.send_byte(cli, 65));
    assert!(n.send_byte(cli, 66));
    assert_eq!(n.recv_byte(srv), 65);
    assert_eq!(n.recv_byte(srv), 66);
    assert_eq!(n.recv_byte(srv), -1);
    assert!(n.send_byte(srv, 67));
    assert_eq!(n.recv_byte(cli), 67);

    assert!(n.close(cli));
    assert_eq!(n.state_get(cli), State::Closed as i32);

    let srv2 = n.create();
    assert!(!n.bind(srv2, 8080));

    assert_eq!(n.recv_byte(cli), -1);

    n.close(srv);
    assert!(n.bind(srv2, 8080));

    println!("networking_fundamentals: 19/19 ok");
}
