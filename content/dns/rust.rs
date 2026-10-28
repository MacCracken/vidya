// Vidya — DNS in Rust
//
// In-memory DNS resolver: small zone (A/AAAA/CNAME/MX/TXT), CNAME
// chain following with depth bound, TTL cache with monotonic clock,
// negative caching.

const RR_A: i32 = 1;
const RR_AAAA: i32 = 2;
const RR_CNAME: i32 = 3;
const RR_MX: i32 = 4;
const RR_TXT: i32 = 5;

const CNAME_MAX_DEPTH: i32 = 16;
// Three different "no answer" outcomes, kept apart as in real DNS:
const NXDOMAIN: i64 = -1; // the name does not exist at all (RFC 2308 §2.1)
const NODATA: i64 = -2;   // the name exists, but has no record of this type (§2.2)
const SERVFAIL: i64 = -3; // CNAME loop / chain too long: an error, not a non-existence
                          // proof (RFC 1034 §3.6.2) — NXDOMAIN here would deny the
                          // name's other records to an RFC 8020 resolver
const NEGATIVE_TTL: i64 = 300;

#[derive(Copy, Clone)]
struct Record { name: u64, rtype: i32, ttl: i64, value: i64 }

struct Resolver {
    zone: Vec<Record>,
    cache: Vec<(u64, i32, i64, i64)>, // name, type, value, expires_at
    now: i64,
    pub last_status: i32, // 1 = hit, 0 = miss
}

impl Resolver {
    fn new() -> Self { Resolver { zone: vec![], cache: vec![], now: 0, last_status: 0 } }

    fn zone_add(&mut self, name: u64, rtype: i32, ttl: i64, value: i64) {
        self.zone.push(Record { name, rtype, ttl, value });
    }

    fn zone_lookup(&self, name: u64, rtype: i32) -> i64 { self.zone_lookup_ttl(name, rtype).0 }

    // Returns (value, ttl). The ttl is the MINIMUM along the CNAME chain:
    // the answer is only valid while every link in it is. (This demo follows
    // CNAMEs for A queries only; RFC 1034 §3.6.2 applies them to every type.)
    fn zone_lookup_ttl(&self, name: u64, rtype: i32) -> (i64, i64) {
        let mut depth = 0;
        let mut cur = name;
        let mut ttl = i64::MAX;
        while depth <= CNAME_MAX_DEPTH {
            for r in &self.zone {
                if r.name == cur && r.rtype == rtype { return (r.value, ttl.min(r.ttl)); }
            }
            let mut cn = 0u64;
            if rtype == RR_A {
                for r in &self.zone {
                    if r.name == cur && r.rtype == RR_CNAME { cn = r.value as u64; ttl = ttl.min(r.ttl); break; }
                }
            }
            if cn == 0 {
                let exists = self.zone.iter().any(|r| r.name == cur);
                return (if exists { NODATA } else { NXDOMAIN }, NEGATIVE_TTL);
            }
            cur = cn;
            depth += 1;
        }
        (SERVFAIL, NEGATIVE_TTL) // loop, or more than CNAME_MAX_DEPTH hops
    }

    fn cache_init(&mut self) {
        self.cache.clear();
        self.now = 0;
    }

    fn advance_time(&mut self, secs: i64) { self.now += secs; }

    fn cache_insert(&mut self, name: u64, rtype: i32, value: i64, ttl: i64) {
        let exp = self.now + ttl;
        for slot in self.cache.iter_mut() {
            if slot.0 == name && slot.1 == rtype { slot.2 = value; slot.3 = exp; return; }
        }
        self.cache.push((name, rtype, value, exp));
    }

    fn cache_lookup(&mut self, name: u64, rtype: i32) -> i64 {
        for slot in &self.cache {
            if slot.0 == name && slot.1 == rtype && slot.3 > self.now {
                self.last_status = 1;
                return slot.2;
            }
        }
        self.last_status = 0;
        NXDOMAIN
    }

    fn resolve(&mut self, name: u64, rtype: i32) -> i64 {
        let cached = self.cache_lookup(name, rtype);
        if self.last_status == 1 { return cached; }
        let (v, ttl) = self.zone_lookup_ttl(name, rtype);
        if v < 0 {
            // negative caching for every negative outcome (RFC 2308 §5, §7)
            self.cache_insert(name, rtype, v, NEGATIVE_TTL);
            return v;
        }
        self.cache_insert(name, rtype, v, ttl);
        v
    }
}

fn main() {
    let mut r = Resolver::new();
    r.zone_add(1, RR_A, 300, 0x7F000001);
    r.zone_add(1, RR_MX, 3600, 10);
    r.zone_add(1, RR_TXT, 60, 99);
    r.zone_add(2, RR_CNAME, 600, 1);
    r.zone_add(3, RR_CNAME, 600, 4);
    r.zone_add(4, RR_A, 60, 0x08080808);
    r.zone_add(5, RR_A, 3600, 0x0A000001);
    r.zone_add(10, RR_CNAME, 600, 11);
    r.zone_add(11, RR_CNAME, 600, 10);
    for k in 20..=36 { r.zone_add(k, RR_CNAME, 600, (k + 1) as i64); }
    r.zone_add(37, RR_A, 60, 0x12345678);

    assert_eq!(r.zone_lookup(1, RR_A), 0x7F000001);
    assert_eq!(r.zone_lookup(2, RR_A), 0x7F000001);
    assert_eq!(r.zone_lookup(3, RR_A), 0x08080808);
    assert_eq!(r.zone_lookup(10, RR_A), SERVFAIL); // 10 <-> 11 CNAME loop
    assert_eq!(r.zone_lookup(20, RR_A), SERVFAIL); // 17 hops > CNAME_MAX_DEPTH
    assert_eq!(r.zone_lookup(98, RR_A), NXDOMAIN); // no such name

    r.cache_init();
    let first = r.resolve(1, RR_A);
    assert_eq!(r.last_status, 0);
    let second = r.resolve(1, RR_A);
    assert_eq!(r.last_status, 1);
    assert_eq!(second, first);

    r.advance_time(301);
    let third = r.resolve(1, RR_A);
    assert_eq!(r.last_status, 0);
    assert_eq!(third, 0x7F000001);

    // CNAME answer expires with its shortest link: 3 -CNAME(600)-> 4 -A(60)->
    r.cache_init();
    r.resolve(3, RR_A);
    r.advance_time(61);
    assert_eq!(r.resolve(3, RR_A), 0x08080808);
    assert_eq!(r.last_status, 0, "chained answer must not outlive the A record's 60s TTL");

    r.cache_init();
    assert_eq!(r.resolve(99, RR_A), NXDOMAIN);
    let _ = r.resolve(99, RR_A);
    assert_eq!(r.last_status, 1);

    assert_eq!(r.zone_lookup(1, RR_MX), 10);
    assert_eq!(r.zone_lookup(1, RR_TXT), 99);
    assert_eq!(r.zone_lookup(1, RR_AAAA), NODATA); // name 1 exists, no AAAA

    println!("dns: 18/18 ok");
}
