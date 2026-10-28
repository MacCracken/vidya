// Vidya — DNS in TypeScript
//
// In-memory resolver: zone, CNAME chains, TTL cache, negative cache.

const RR_A = 1;
const RR_AAAA = 2;
const RR_CNAME = 3;
const RR_MX = 4;
const RR_TXT = 5;

const CNAME_MAX_DEPTH = 16;
// Three negative outcomes, three answers. NXDOMAIN tells an RFC 8020
// resolver that nothing exists at or below the name, so answering it for a
// name that exists but lacks the type (AAAA for name 1 below) would deny
// that name's other records too; that case is NODATA. A CNAME loop or an
// over-deep chain is a failure to resolve (RFC 1034 §3.6.2), not a
// statement about the name: SERVFAIL.
const NXDOMAIN = -1;  // the name does not exist at all (RCODE 3)
const NODATA = -2;    // the name exists, but has no record of this type (RFC 2308 §2.2)
const SERVFAIL = -3;  // CNAME loop or chain too deep
const NEGATIVE_TTL = 300;

interface Record { name: number; rtype: number; ttl: number; value: number; }
interface CacheEntry { name: number; rtype: number; value: number; expires: number; }

class Resolver {
  zone: Record[] = [];
  cache: CacheEntry[] = [];
  now = 0;
  lastStatus = 0;
  lastTtl = 0;   // min TTL over the records zoneLookup's answer came through

  zoneAdd(name: number, rtype: number, ttl: number, value: number): void {
    this.zone.push({ name, rtype, ttl, value });
  }

  zoneLookup(name: number, rtype: number): number {
    let depth = 0;
    let cur = name;
    let ttl = Infinity;
    while (depth <= CNAME_MAX_DEPTH) {
      for (const r of this.zone) {
        if (r.name === cur && r.rtype === rtype) { this.lastTtl = Math.min(ttl, r.ttl); return r.value; }
      }
      const miss = this.zone.some((r) => r.name === cur) ? NODATA : NXDOMAIN;
      if (rtype === RR_A) {
        let cn = 0;
        for (const r of this.zone) {
          if (r.name === cur && r.rtype === RR_CNAME) { cn = r.value; ttl = Math.min(ttl, r.ttl); break; }
        }
        if (cn === 0) return miss;
        cur = cn;
        depth++;
      } else {
        return miss;
      }
    }
    return SERVFAIL;
  }

  cacheInit(): void { this.cache = []; this.now = 0; }
  advanceTime(s: number): void { this.now += s; }

  cacheInsert(name: number, rtype: number, value: number, ttl: number): void {
    const exp = this.now + ttl;
    for (const slot of this.cache) {
      if (slot.name === name && slot.rtype === rtype) { slot.value = value; slot.expires = exp; return; }
    }
    this.cache.push({ name, rtype, value, expires: exp });
  }

  cacheLookup(name: number, rtype: number): number {
    for (const slot of this.cache) {
      if (slot.name === name && slot.rtype === rtype && slot.expires > this.now) {
        this.lastStatus = 1;
        return slot.value;
      }
    }
    this.lastStatus = 0;
    return NXDOMAIN;
  }

  resolve(name: number, rtype: number): number {
    const cached = this.cacheLookup(name, rtype);
    if (this.lastStatus === 1) return cached;
    const v = this.zoneLookup(name, rtype);
    // NXDOMAIN, NODATA and SERVFAIL are all cached briefly.
    if (v < 0) { this.cacheInsert(name, rtype, v, NEGATIVE_TTL); return v; }
    // A CNAME-chased answer is only as fresh as the shortest-lived record in
    // the chain: 3 -CNAME(600)-> 4 -A(60)-> must expire after 60s, not 600.
    this.cacheInsert(name, rtype, v, this.lastTtl);
    return v;
  }
}

function eq(got: number, want: number, label: string): void {
  if (got !== want) throw new Error(`${label}: got ${got} want ${want}`);
}

function main(): void {
  const r = new Resolver();
  r.zoneAdd(1, RR_A, 300, 0x7F000001);
  r.zoneAdd(1, RR_MX, 3600, 10);
  r.zoneAdd(1, RR_TXT, 60, 99);
  r.zoneAdd(2, RR_CNAME, 600, 1);
  r.zoneAdd(3, RR_CNAME, 600, 4);
  r.zoneAdd(4, RR_A, 60, 0x08080808);
  r.zoneAdd(5, RR_A, 3600, 0x0A000001);
  r.zoneAdd(10, RR_CNAME, 600, 11);
  r.zoneAdd(11, RR_CNAME, 600, 10);
  for (let k = 20; k <= 36; k++) r.zoneAdd(k, RR_CNAME, 600, k + 1);
  r.zoneAdd(37, RR_A, 60, 0x12345678);

  eq(r.zoneLookup(1, RR_A), 0x7F000001, "a1");
  eq(r.zoneLookup(2, RR_A), 0x7F000001, "cname");
  eq(r.zoneLookup(3, RR_A), 0x08080808, "cname2");
  eq(r.zoneLookup(10, RR_A), SERVFAIL, "loop");   // 10 -> 11 -> 10
  eq(r.zoneLookup(20, RR_A), SERVFAIL, "deep");   // 17 hops > CNAME_MAX_DEPTH

  r.cacheInit();
  const first = r.resolve(1, RR_A);
  eq(r.lastStatus, 0, "first miss");
  const second = r.resolve(1, RR_A);
  eq(r.lastStatus, 1, "second hit");
  eq(second, first, "same");

  r.advanceTime(301);
  const third = r.resolve(1, RR_A);
  eq(r.lastStatus, 0, "expired");
  eq(third, 0x7F000001, "requery");

  r.cacheInit();
  r.resolve(3, RR_A);              // via CNAME (ttl 600) to an A with ttl 60
  r.advanceTime(61);
  r.resolve(3, RR_A);
  eq(r.lastStatus, 0, "cname answer expires with the chain's min ttl");

  r.cacheInit();
  eq(r.resolve(99, RR_A), NXDOMAIN, "nxdomain");
  r.resolve(99, RR_A);
  eq(r.lastStatus, 1, "neg cache");

  eq(r.zoneLookup(1, RR_MX), 10, "mx");
  eq(r.zoneLookup(1, RR_TXT), 99, "txt");
  eq(r.zoneLookup(1, RR_AAAA), NODATA, "aaaa on an existing name is NODATA");
  eq(r.zoneLookup(99, RR_AAAA), NXDOMAIN, "aaaa on a missing name is NXDOMAIN");

  console.log("dns: 17/17 ok");
}

main();
