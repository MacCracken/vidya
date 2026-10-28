// Vidya — DNS in Go
//
// In-memory resolver: zone, CNAME chains, TTL cache, negative cache.

package main

import (
	"fmt"
	"math"
)

const (
	RR_A     = 1
	RR_AAAA  = 2
	RR_CNAME = 3
	RR_MX    = 4
	RR_TXT   = 5

	CNAME_MAX_DEPTH = 16
	NEGATIVE_TTL    = 300
)

// Negative answers are not all the same (RFC 2308, RFC 8020):
//
//	NXDOMAIN — the name does not exist at all, for ANY type
//	NODATA   — the name exists but has no record of the asked type
//	SERVFAIL — resolution failed (CNAME loop, chain too deep)
//
// Answering NXDOMAIN for an existing name tells an RFC 8020 resolver the
// whole name is gone, which also denies the records it does have.
const (
	NXDOMAIN int64 = -1
	NODATA   int64 = -2
	SERVFAIL int64 = -3
)

// nameExists reports whether the zone has any record at all for name.
func (r *Resolver) nameExists(name uint64) bool {
	for _, rec := range r.Zone {
		if rec.Name == name {
			return true
		}
	}
	return false
}

type Record struct {
	Name  uint64
	Type  int32
	TTL   int64
	Value int64
}

type CacheEntry struct {
	Name    uint64
	Type    int32
	Value   int64
	Expires int64
}

type Resolver struct {
	Zone       []Record
	Cache      []CacheEntry
	Now        int64
	LastStatus int32
}

func (r *Resolver) ZoneAdd(name uint64, rtype int32, ttl, value int64) {
	r.Zone = append(r.Zone, Record{name, rtype, ttl, value})
}

func (r *Resolver) ZoneLookup(name uint64, rtype int32) int64 {
	depth := 0
	cur := name
	for depth <= CNAME_MAX_DEPTH {
		for _, rec := range r.Zone {
			if rec.Name == cur && rec.Type == rtype {
				return rec.Value
			}
		}
		if rtype == RR_A {
			var cn uint64 = 0
			for _, rec := range r.Zone {
				if rec.Name == cur && rec.Type == RR_CNAME {
					cn = uint64(rec.Value)
					break
				}
			}
			if cn == 0 {
				break
			}
			cur = cn
			depth++
		} else {
			break
		}
	}
	if depth > CNAME_MAX_DEPTH {
		return SERVFAIL // loop or over-long chain (RFC 1034 §3.6.2: an error)
	}
	if r.nameExists(cur) {
		return NODATA
	}
	return NXDOMAIN
}

func (r *Resolver) CacheInit() {
	r.Cache = nil
	r.Now = 0
}

func (r *Resolver) AdvanceTime(s int64) { r.Now += s }

func (r *Resolver) CacheInsert(name uint64, rtype int32, value, ttl int64) {
	exp := r.Now + ttl
	for i := range r.Cache {
		if r.Cache[i].Name == name && r.Cache[i].Type == rtype {
			r.Cache[i].Value = value
			r.Cache[i].Expires = exp
			return
		}
	}
	r.Cache = append(r.Cache, CacheEntry{name, rtype, value, exp})
}

func (r *Resolver) CacheLookup(name uint64, rtype int32) int64 {
	for _, c := range r.Cache {
		if c.Name == name && c.Type == rtype && c.Expires > r.Now {
			r.LastStatus = 1
			return c.Value
		}
	}
	r.LastStatus = 0
	return NXDOMAIN
}

func (r *Resolver) Resolve(name uint64, rtype int32) int64 {
	cached := r.CacheLookup(name, rtype)
	if r.LastStatus == 1 {
		return cached
	}
	v := r.ZoneLookup(name, rtype)
	if v < 0 { // NXDOMAIN, NODATA, SERVFAIL: all negatively cached
		r.CacheInsert(name, rtype, v, NEGATIVE_TTL)
		return v
	}
	r.CacheInsert(name, rtype, v, r.answerTTL(name, rtype))
	return v
}

// answerTTL is how long a positive answer may be cached: the minimum TTL
// over every record the lookup used (each CNAME link and the final
// record), because the answer is only valid while all of them are.
// Looking up only the queried name's own record misses a CNAME-resolved
// answer and would cache it past the target record's TTL.
func (r *Resolver) answerTTL(name uint64, rtype int32) int64 {
	ttl := int64(math.MaxInt64)
	cur := name
	for depth := 0; depth <= CNAME_MAX_DEPTH; depth++ {
		var cname *Record
		for i := range r.Zone {
			rec := &r.Zone[i]
			if rec.Name != cur {
				continue
			}
			if rec.Type == rtype {
				return min(ttl, rec.TTL)
			}
			if rec.Type == RR_CNAME && cname == nil {
				cname = rec
			}
		}
		if cname == nil || rtype != RR_A {
			break
		}
		ttl = min(ttl, cname.TTL)
		cur = uint64(cname.Value)
	}
	return NEGATIVE_TTL // not reached for a name ZoneLookup resolved
}

// checks counts the assertions this file runs, for the final tally.
var checks int

func check(cond bool, label string) {
	checks++
	if !cond {
		panic(label)
	}
}

func main() {
	r := &Resolver{}
	r.ZoneAdd(1, RR_A, 300, 0x7F000001)
	r.ZoneAdd(1, RR_MX, 3600, 10)
	r.ZoneAdd(1, RR_TXT, 60, 99)
	r.ZoneAdd(2, RR_CNAME, 600, 1)
	r.ZoneAdd(3, RR_CNAME, 600, 4)
	r.ZoneAdd(4, RR_A, 60, 0x08080808)
	r.ZoneAdd(5, RR_A, 3600, 0x0A000001)
	r.ZoneAdd(10, RR_CNAME, 600, 11)
	r.ZoneAdd(11, RR_CNAME, 600, 10)
	for k := uint64(20); k <= 36; k++ {
		r.ZoneAdd(k, RR_CNAME, 600, int64(k+1))
	}
	r.ZoneAdd(37, RR_A, 60, 0x12345678)

	check(r.ZoneLookup(1, RR_A) == 0x7F000001, "a1")
	check(r.ZoneLookup(2, RR_A) == 0x7F000001, "cname")
	check(r.ZoneLookup(3, RR_A) == 0x08080808, "cname2")
	check(r.ZoneLookup(10, RR_A) == SERVFAIL, "loop")
	check(r.ZoneLookup(20, RR_A) == SERVFAIL, "deep")

	r.CacheInit()
	first := r.Resolve(1, RR_A)
	check(r.LastStatus == 0, "first miss")
	second := r.Resolve(1, RR_A)
	check(r.LastStatus == 1, "second hit")
	check(second == first, "same")

	r.AdvanceTime(301)
	third := r.Resolve(1, RR_A)
	check(r.LastStatus == 0, "expired")
	check(third == 0x7F000001, "requery")

	// A CNAME-resolved answer expires with the shortest TTL on the chain:
	// 3 -CNAME(600)-> 4 -A(60)-> so the cached answer is gone after 61s.
	r.CacheInit()
	r.Resolve(3, RR_A)
	r.AdvanceTime(61)
	check(r.Resolve(3, RR_A) == 0x08080808 && r.LastStatus == 0, "cname chain cached past the A record's TTL")

	r.CacheInit()
	check(r.Resolve(99, RR_A) == NXDOMAIN, "nxdomain")
	r.Resolve(99, RR_A)
	check(r.LastStatus == 1, "neg cache")

	check(r.ZoneLookup(1, RR_MX) == 10, "mx")
	check(r.ZoneLookup(1, RR_TXT) == 99, "txt")
	check(r.ZoneLookup(1, RR_AAAA) == NODATA, "aaaa: name 1 exists, so a missing type is NODATA, not NXDOMAIN")

	// Every check panics on failure, so reaching this line means all
	// `checks` of them ran and passed; the count is not hard-coded.
	fmt.Printf("dns: %d/%d ok\n", checks, checks)
}
