// Vidya — Transactions and ACID — Rust port.
//
// OCC store with read-set version snapshots. Single-threaded, no
// real fsync; demonstrates the four ACID properties via tests.

use std::collections::HashMap;

const N_ACCOUNTS: usize = 8;
const N_TX: usize = 2;
const TX_CAP: usize = 4;

#[derive(Copy, Clone, PartialEq, Eq, Debug)]
enum TxStatus {
    Free,
    Active,
    Committed,
    Aborted,
}

struct Store {
    accounts: [i64; N_ACCOUNTS],
    version: [i64; N_ACCOUNTS],
    tx_status: [TxStatus; N_TX],
    tx_writes: [HashMap<usize, i64>; N_TX],
    tx_reads: [HashMap<usize, i64>; N_TX],
}

impl Store {
    fn new() -> Self {
        Store {
            accounts: [0; N_ACCOUNTS],
            version: [0; N_ACCOUNTS],
            tx_status: [TxStatus::Free; N_TX],
            tx_writes: [HashMap::new(), HashMap::new()],
            tx_reads: [HashMap::new(), HashMap::new()],
        }
    }

    fn account_set_raw(&mut self, k: usize, v: i64) {
        self.accounts[k] = v;
        self.version[k] += 1;
    }

    fn account_get_raw(&self, k: usize) -> i64 {
        self.accounts[k]
    }

    fn total(&self) -> i64 {
        self.accounts.iter().sum()
    }

    fn begin(&mut self) -> usize {
        for t in 0..N_TX {
            if self.tx_status[t] == TxStatus::Free {
                self.tx_status[t] = TxStatus::Active;
                self.tx_writes[t].clear();
                self.tx_reads[t].clear();
                return t;
            }
        }
        panic!("no free tx slot");
    }

    fn read(&mut self, tx: usize, k: usize) -> i64 {
        assert!(self.tx_status[tx] == TxStatus::Active);
        if let Some(&v) = self.tx_writes[tx].get(&k) {
            return v;
        }
        if !self.tx_reads[tx].contains_key(&k) && self.tx_reads[tx].len() < TX_CAP {
            self.tx_reads[tx].insert(k, self.version[k]);
        }
        self.accounts[k]
    }

    fn write(&mut self, tx: usize, k: usize, v: i64) -> i32 {
        if self.tx_status[tx] != TxStatus::Active {
            return 0;
        }
        if self.tx_writes[tx].contains_key(&k) {
            self.tx_writes[tx].insert(k, v);
            return 1;
        }
        if self.tx_writes[tx].len() >= TX_CAP {
            return 0;
        }
        self.tx_writes[tx].insert(k, v);
        1
    }

    fn validate(&self, tx: usize) -> bool {
        for (&k, &snap) in &self.tx_reads[tx] {
            if self.version[k] != snap {
                return false;
            }
        }
        true
    }

    fn commit(&mut self, tx: usize) -> i32 {
        if self.tx_status[tx] != TxStatus::Active {
            return 0;
        }
        if !self.validate(tx) {
            self.tx_status[tx] = TxStatus::Aborted;
            return 0;
        }
        let writes: Vec<(usize, i64)> = self.tx_writes[tx].iter().map(|(&k, &v)| (k, v)).collect();
        for (k, v) in writes {
            self.accounts[k] = v;
            self.version[k] += 1;
        }
        self.tx_status[tx] = TxStatus::Committed;
        1
    }

    fn abort(&mut self, tx: usize) -> i32 {
        if self.tx_status[tx] != TxStatus::Active {
            return 0;
        }
        self.tx_status[tx] = TxStatus::Aborted;
        1
    }

    fn crash_recovery(&mut self) {
        for t in 0..N_TX {
            self.tx_status[t] = TxStatus::Free;
            self.tx_writes[t].clear();
            self.tx_reads[t].clear();
        }
    }
}

fn seed() -> Store {
    let mut s = Store::new();
    s.account_set_raw(0, 1000);
    s.account_set_raw(1, 500);
    s.account_set_raw(2, 200);
    s
}

fn main() {
    // A — abort discards all writes
    {
        let mut s = seed();
        let tx = s.begin();
        s.write(tx, 0, 9999);
        s.write(tx, 1, 8888);
        s.write(tx, 2, 7777);
        s.abort(tx);
        assert_eq!(s.account_get_raw(0), 1000);
        assert_eq!(s.account_get_raw(1), 500);
        assert_eq!(s.account_get_raw(2), 200);
        assert_eq!(s.tx_status[tx], TxStatus::Aborted);
    }
    // A — commit installs all-or-nothing
    {
        let mut s = seed();
        let tx = s.begin();
        s.write(tx, 0, 100);
        s.write(tx, 1, 200);
        s.write(tx, 2, 300);
        assert_eq!(s.commit(tx), 1);
        assert_eq!(s.account_get_raw(0), 100);
        assert_eq!(s.account_get_raw(1), 200);
        assert_eq!(s.account_get_raw(2), 300);
        assert_eq!(s.tx_status[tx], TxStatus::Committed);
    }
    // C — transfer preserves total
    {
        let mut s = seed();
        let initial = s.total();
        let tx = s.begin();
        let src = s.read(tx, 0);
        let dst = s.read(tx, 1);
        s.write(tx, 0, src - 100);
        s.write(tx, 1, dst + 100);
        s.commit(tx);
        assert_eq!(s.account_get_raw(0), 900);
        assert_eq!(s.account_get_raw(1), 600);
        assert_eq!(s.total(), initial);
    }
    // I — no dirty read
    {
        let mut s = seed();
        let tx1 = s.begin();
        let tx2 = s.begin();
        s.write(tx1, 0, 9999);
        assert_eq!(s.read(tx2, 0), 1000);
    }
    // I — read-your-own-writes
    {
        let mut s = seed();
        let tx = s.begin();
        s.write(tx, 0, 4242);
        assert_eq!(s.read(tx, 0), 4242);
        assert_eq!(s.account_get_raw(0), 1000);
    }
    // I — write-write conflict (lost-update prevention)
    {
        let mut s = seed();
        let tx1 = s.begin();
        let tx2 = s.begin();
        let v1 = s.read(tx1, 0);
        s.write(tx1, 0, v1 + 50);
        let v2 = s.read(tx2, 0);
        s.write(tx2, 0, v2 + 100);
        assert_eq!(s.commit(tx1), 1);
        assert_eq!(s.commit(tx2), 0);
        assert_eq!(s.tx_status[tx2], TxStatus::Aborted);
        assert_eq!(s.account_get_raw(0), 1050);
    }
    // D — committed survives crash
    {
        let mut s = seed();
        let tx = s.begin();
        s.write(tx, 0, 12345);
        s.commit(tx);
        s.crash_recovery();
        assert_eq!(s.account_get_raw(0), 12345);
    }
    // No double-commit
    {
        let mut s = seed();
        let tx = s.begin();
        s.write(tx, 0, 7);
        assert_eq!(s.commit(tx), 1);
        assert_eq!(s.commit(tx), 0);
    }
    // Write-set capacity bounded
    {
        let mut s = seed();
        let tx = s.begin();
        s.write(tx, 0, 1);
        s.write(tx, 1, 2);
        s.write(tx, 2, 3);
        s.write(tx, 3, 4);
        assert_eq!(s.write(tx, 4, 5), 0);
    }

    println!("transactions_and_acid: 9 tests, 23 assertions ok");
}
