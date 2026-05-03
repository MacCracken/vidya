// Vidya — Transactions and ACID — TypeScript port.
// OCC store with read-set version snapshots.

const N_ACCOUNTS = 8;
const N_TX = 2;
const TX_CAP = 4;

const enum TxStatus {
    Free = 0,
    Active = 1,
    Committed = 2,
    Aborted = 3,
}

class Store {
    accounts: number[] = new Array(N_ACCOUNTS).fill(0);
    version: number[] = new Array(N_ACCOUNTS).fill(0);
    status: number[] = new Array(N_TX).fill(TxStatus.Free);
    writes: Map<number, number>[] = [];
    reads: Map<number, number>[] = [];

    constructor() {
        for (let i = 0; i < N_TX; i++) {
            this.writes.push(new Map());
            this.reads.push(new Map());
        }
    }

    accountSetRaw(k: number, v: number): void {
        this.accounts[k] = v;
        this.version[k] += 1;
    }
    accountGetRaw(k: number): number { return this.accounts[k]; }
    total(): number { return this.accounts.reduce((a, b) => a + b, 0); }

    begin(): number {
        for (let t = 0; t < N_TX; t++) {
            if (this.status[t] === TxStatus.Free) {
                this.status[t] = TxStatus.Active;
                this.writes[t] = new Map();
                this.reads[t] = new Map();
                return t;
            }
        }
        return -1;
    }

    read(tx: number, k: number): number {
        if (this.status[tx] !== TxStatus.Active) throw new Error("read on non-active tx");
        if (this.writes[tx].has(k)) return this.writes[tx].get(k)!;
        if (!this.reads[tx].has(k) && this.reads[tx].size < TX_CAP) {
            this.reads[tx].set(k, this.version[k]);
        }
        return this.accounts[k];
    }

    write(tx: number, k: number, v: number): number {
        if (this.status[tx] !== TxStatus.Active) return 0;
        if (this.writes[tx].has(k)) {
            this.writes[tx].set(k, v);
            return 1;
        }
        if (this.writes[tx].size >= TX_CAP) return 0;
        this.writes[tx].set(k, v);
        return 1;
    }

    validate(tx: number): boolean {
        for (const [k, snap] of this.reads[tx]) {
            if (this.version[k] !== snap) return false;
        }
        return true;
    }

    commit(tx: number): number {
        if (this.status[tx] !== TxStatus.Active) return 0;
        if (!this.validate(tx)) {
            this.status[tx] = TxStatus.Aborted;
            return 0;
        }
        for (const [k, v] of this.writes[tx]) {
            this.accounts[k] = v;
            this.version[k] += 1;
        }
        this.status[tx] = TxStatus.Committed;
        return 1;
    }

    abort(tx: number): number {
        if (this.status[tx] !== TxStatus.Active) return 0;
        this.status[tx] = TxStatus.Aborted;
        return 1;
    }

    crashRecovery(): void {
        for (let t = 0; t < N_TX; t++) {
            this.status[t] = TxStatus.Free;
            this.writes[t] = new Map();
            this.reads[t] = new Map();
        }
    }
}

function seed(): Store {
    const s = new Store();
    s.accountSetRaw(0, 1000);
    s.accountSetRaw(1, 500);
    s.accountSetRaw(2, 200);
    return s;
}

let passCount = 0;
let failCount = 0;
function check(cond: boolean, name: string): void {
    if (cond) passCount++;
    else { failCount++; console.error("  FAIL:", name); }
}

{
    const s = seed();
    const tx = s.begin();
    s.write(tx, 0, 9999);
    s.write(tx, 1, 8888);
    s.write(tx, 2, 7777);
    s.abort(tx);
    check(s.accountGetRaw(0) === 1000, "abort: key 0 unchanged");
    check(s.accountGetRaw(1) === 500, "abort: key 1 unchanged");
    check(s.accountGetRaw(2) === 200, "abort: key 2 unchanged");
    check(s.status[tx] === TxStatus.Aborted, "tx status = ABORTED");
}
{
    const s = seed();
    const tx = s.begin();
    s.write(tx, 0, 100);
    s.write(tx, 1, 200);
    s.write(tx, 2, 300);
    check(s.commit(tx) === 1, "commit succeeded");
    check(s.accountGetRaw(0) === 100, "commit: key 0 installed");
    check(s.accountGetRaw(1) === 200, "commit: key 1 installed");
    check(s.accountGetRaw(2) === 300, "commit: key 2 installed");
    check(s.status[tx] === TxStatus.Committed, "tx status = COMMITTED");
}
{
    const s = seed();
    const initial = s.total();
    const tx = s.begin();
    const src = s.read(tx, 0);
    const dst = s.read(tx, 1);
    s.write(tx, 0, src - 100);
    s.write(tx, 1, dst + 100);
    s.commit(tx);
    check(s.accountGetRaw(0) === 900, "src debited");
    check(s.accountGetRaw(1) === 600, "dst credited");
    check(s.total() === initial, "total preserved");
}
{
    const s = seed();
    const tx1 = s.begin();
    const tx2 = s.begin();
    s.write(tx1, 0, 9999);
    check(s.read(tx2, 0) === 1000, "tx2 sees committed, not pending");
}
{
    const s = seed();
    const tx = s.begin();
    s.write(tx, 0, 4242);
    check(s.read(tx, 0) === 4242, "tx sees own write");
    check(s.accountGetRaw(0) === 1000, "durable unchanged before commit");
}
{
    const s = seed();
    const tx1 = s.begin();
    const tx2 = s.begin();
    const v1 = s.read(tx1, 0);
    s.write(tx1, 0, v1 + 50);
    const v2 = s.read(tx2, 0);
    s.write(tx2, 0, v2 + 100);
    const ok1 = s.commit(tx1);
    const ok2 = s.commit(tx2);
    check(ok1 === 1, "tx1 commits");
    check(ok2 === 0, "tx2 conflicts and aborts");
    check(s.status[tx2] === TxStatus.Aborted, "tx2 status = ABORTED");
    check(s.accountGetRaw(0) === 1050, "tx1 durable; tx2 lost");
}
{
    const s = seed();
    const tx = s.begin();
    s.write(tx, 0, 12345);
    s.commit(tx);
    s.crashRecovery();
    check(s.accountGetRaw(0) === 12345, "committed survives crash");
}
{
    const s = seed();
    const tx = s.begin();
    s.write(tx, 0, 7);
    const ok1 = s.commit(tx);
    const ok2 = s.commit(tx);
    check(ok1 === 1, "first commit ok");
    check(ok2 === 0, "second commit rejected");
}
{
    const s = seed();
    const tx = s.begin();
    s.write(tx, 0, 1);
    s.write(tx, 1, 2);
    s.write(tx, 2, 3);
    s.write(tx, 3, 4);
    const fifth = s.write(tx, 4, 5);
    check(fifth === 0, "5th write rejected (cap=4)");
}

console.log("=== transactions_and_acid ===");
console.log(`${passCount} passed, ${failCount} failed (${passCount + failCount} total)`);
process.exit(failCount > 0 ? 1 : 0);
