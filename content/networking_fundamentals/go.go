// Vidya — Networking Fundamentals in Go
//
// In-memory simulation of TCP socket state machine + lifecycle.

package main

import "fmt"

const (
	StClosed = iota
	StListen
	StSynRcvd
	StEstablished
	StFinWait
)

const (
	SockCap = 8
	BufCap  = 256
)

type Net struct {
	state       [SockCap]int
	port        [SockCap]uint16
	peer        [SockCap]int
	rxbuf       [SockCap][]byte
	portToSock  map[uint16]int
	nextFree    int
}

func newNet() *Net {
	n := &Net{portToSock: make(map[uint16]int), nextFree: 1}
	for i := range n.rxbuf {
		n.rxbuf[i] = make([]byte, 0, BufCap)
	}
	return n
}

func (n *Net) Create() int {
	for i := n.nextFree; i < SockCap; i++ {
		if n.state[i] == StClosed && n.port[i] == 0 {
			n.nextFree = i + 1
			return i
		}
	}
	return 0
}

func (n *Net) StateGet(s int) int {
	if s == 0 || s >= SockCap {
		return -1
	}
	return n.state[s]
}

func (n *Net) Bind(s int, port uint16) bool {
	if s == 0 || s >= SockCap {
		return false
	}
	if _, ok := n.portToSock[port]; ok {
		return false
	}
	if n.port[s] != 0 {
		return false
	}
	n.port[s] = port
	n.portToSock[port] = s
	return true
}

func (n *Net) Listen(s int) bool {
	if s == 0 || s >= SockCap {
		return false
	}
	if n.state[s] != StClosed || n.port[s] == 0 {
		return false
	}
	n.state[s] = StListen
	return true
}

func (n *Net) Connect(client int, port uint16) bool {
	if client == 0 || client >= SockCap {
		return false
	}
	server, ok := n.portToSock[port]
	if !ok || n.state[server] != StListen {
		return false
	}
	n.state[client] = StEstablished
	n.state[server] = StEstablished
	n.peer[client] = server
	n.peer[server] = client
	return true
}

func (n *Net) SendByte(s int, b byte) bool {
	if s == 0 || s >= SockCap || n.state[s] != StEstablished {
		return false
	}
	peer := n.peer[s]
	if peer == 0 || len(n.rxbuf[peer]) >= BufCap {
		return false
	}
	n.rxbuf[peer] = append(n.rxbuf[peer], b)
	return true
}

func (n *Net) RecvByte(s int) int {
	if s == 0 || s >= SockCap {
		return -1
	}
	st := n.state[s]
	if st != StEstablished && st != StFinWait {
		return -1
	}
	if len(n.rxbuf[s]) == 0 {
		return -1
	}
	b := n.rxbuf[s][0]
	n.rxbuf[s] = n.rxbuf[s][1:]
	return int(b)
}

func (n *Net) Close(s int) bool {
	if s == 0 || s >= SockCap || n.state[s] == StClosed {
		return false
	}
	if n.port[s] != 0 {
		delete(n.portToSock, n.port[s])
	}
	n.state[s] = StClosed
	n.port[s] = 0
	n.peer[s] = 0
	return true
}

func ok(b bool, label string) {
	if !b {
		panic(label)
	}
}

func eq(got, want int, label string) {
	if got != want {
		panic(fmt.Sprintf("%s: got %d want %d", label, got, want))
	}
}

func main() {
	n := newNet()

	srv := n.Create()
	eq(n.StateGet(srv), StClosed, "srv init closed")

	ok(n.Bind(srv, 8080), "bind 8080")
	ok(n.Listen(srv), "listen")
	eq(n.StateGet(srv), StListen, "srv listen")

	cli := n.Create()
	ok(n.Connect(cli, 8080), "connect")
	eq(n.StateGet(cli), StEstablished, "cli est")
	eq(n.StateGet(srv), StEstablished, "srv est")

	ok(n.SendByte(cli, 65), "send A")
	ok(n.SendByte(cli, 66), "send B")
	eq(n.RecvByte(srv), 65, "recv A")
	eq(n.RecvByte(srv), 66, "recv B")
	eq(n.RecvByte(srv), -1, "recv empty")
	ok(n.SendByte(srv, 67), "echo C")
	eq(n.RecvByte(cli), 67, "cli recv C")

	ok(n.Close(cli), "close cli")
	eq(n.StateGet(cli), StClosed, "cli closed")

	srv2 := n.Create()
	ok(!n.Bind(srv2, 8080), "port reuse rejected")

	eq(n.RecvByte(cli), -1, "recv on closed -1")

	n.Close(srv)
	ok(n.Bind(srv2, 8080), "rebind after close")

	fmt.Println("networking_fundamentals: 19/19 ok")
}
