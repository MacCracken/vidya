// Vidya — Networking Fundamentals in TypeScript
//
// In-memory simulation of TCP socket state machine + lifecycle.

const ST_CLOSED = 0;
const ST_LISTEN = 1;
const ST_SYN_RCVD = 2;
const ST_ESTABLISHED = 3;
const ST_FIN_WAIT = 4;

const SOCK_CAP = 8;
const BUF_CAP = 256;

class Net {
  state = new Array<number>(SOCK_CAP).fill(ST_CLOSED);
  port = new Array<number>(SOCK_CAP).fill(0);
  peer = new Array<number>(SOCK_CAP).fill(0);
  rxbuf: number[][] = Array.from({ length: SOCK_CAP }, () => []);
  portToSock = new Map<number, number>();
  nextFree = 1;

  create(): number {
    for (let i = this.nextFree; i < SOCK_CAP; i++) {
      if (this.state[i] === ST_CLOSED && this.port[i] === 0) {
        this.nextFree = i + 1;
        return i;
      }
    }
    return 0;
  }

  stateGet(s: number): number {
    if (s === 0 || s >= SOCK_CAP) return -1;
    return this.state[s];
  }

  bind(s: number, port: number): boolean {
    if (s === 0 || s >= SOCK_CAP) return false;
    if (this.portToSock.has(port)) return false;
    if (this.port[s] !== 0) return false;
    this.port[s] = port;
    this.portToSock.set(port, s);
    return true;
  }

  listen(s: number): boolean {
    if (s === 0 || s >= SOCK_CAP) return false;
    if (this.state[s] !== ST_CLOSED || this.port[s] === 0) return false;
    this.state[s] = ST_LISTEN;
    return true;
  }

  connect(client: number, port: number): boolean {
    if (client === 0 || client >= SOCK_CAP) return false;
    const server = this.portToSock.get(port);
    if (server === undefined || this.state[server] !== ST_LISTEN) return false;
    this.state[client] = ST_ESTABLISHED;
    this.state[server] = ST_ESTABLISHED;
    this.peer[client] = server;
    this.peer[server] = client;
    return true;
  }

  sendByte(s: number, b: number): boolean {
    if (s === 0 || s >= SOCK_CAP || this.state[s] !== ST_ESTABLISHED) return false;
    const peer = this.peer[s];
    if (peer === 0 || this.rxbuf[peer].length >= BUF_CAP) return false;
    this.rxbuf[peer].push(b);
    return true;
  }

  recvByte(s: number): number {
    if (s === 0 || s >= SOCK_CAP) return -1;
    const st = this.state[s];
    if (st !== ST_ESTABLISHED && st !== ST_FIN_WAIT) return -1;
    if (this.rxbuf[s].length === 0) return -1;
    return this.rxbuf[s].shift()!;
  }

  close(s: number): boolean {
    if (s === 0 || s >= SOCK_CAP || this.state[s] === ST_CLOSED) return false;
    if (this.port[s] !== 0) this.portToSock.delete(this.port[s]);
    this.state[s] = ST_CLOSED;
    this.port[s] = 0;
    this.peer[s] = 0;
    return true;
  }
}

function ok(b: boolean, label: string): void {
  if (!b) throw new Error(label);
}

function eq(got: number, want: number, label: string): void {
  if (got !== want) throw new Error(`${label}: got ${got} want ${want}`);
}

function main(): void {
  const n = new Net();

  const srv = n.create();
  eq(n.stateGet(srv), ST_CLOSED, "init");

  ok(n.bind(srv, 8080), "bind");
  ok(n.listen(srv), "listen");
  eq(n.stateGet(srv), ST_LISTEN, "listen state");

  const cli = n.create();
  ok(n.connect(cli, 8080), "connect");
  eq(n.stateGet(cli), ST_ESTABLISHED, "cli est");
  eq(n.stateGet(srv), ST_ESTABLISHED, "srv est");

  ok(n.sendByte(cli, 65), "send A");
  ok(n.sendByte(cli, 66), "send B");
  eq(n.recvByte(srv), 65, "recv A");
  eq(n.recvByte(srv), 66, "recv B");
  eq(n.recvByte(srv), -1, "empty");
  ok(n.sendByte(srv, 67), "echo");
  eq(n.recvByte(cli), 67, "cli recv");

  ok(n.close(cli), "close");
  eq(n.stateGet(cli), ST_CLOSED, "closed");

  const srv2 = n.create();
  ok(!n.bind(srv2, 8080), "port reuse");

  eq(n.recvByte(cli), -1, "recv closed");

  n.close(srv);
  ok(n.bind(srv2, 8080), "rebind");

  console.log("networking_fundamentals: 19/19 ok");
}

main();
