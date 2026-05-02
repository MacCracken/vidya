// Vidya — DNS in Go
//
// In-memory resolver: zone, CNAME chains, TTL cache, negative cache.

package main

import "fmt"

const (
	RR_A     = 1
	RR_AAAA  = 2
	RR_CNAME = 3
	RR_MX    = 4
	RR_TXT   = 5

	CNAME_MAX_DEPTH = 16
	NEGATIVE_TTL    = 300
)

const NXDOMAIN int64 = -1

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
				return NXDOMAIN
			}
			cur = cn
			depth++
		} else {
			return NXDOMAIN
		}
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
	if v == NXDOMAIN {
		r.CacheInsert(name, rtype, NXDOMAIN, NEGATIVE_TTL)
		return NXDOMAIN
	}
	var ttl int64 = NEGATIVE_TTL
	for _, rec := range r.Zone {
		if rec.Name == name && rec.Type == rtype {
			ttl = rec.TTL
			break
		}
	}
	r.CacheInsert(name, rtype, v, ttl)
	return v
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

	if r.ZoneLookup(1, RR_A) != 0x7F000001 { panic("a1") }
	if r.ZoneLookup(2, RR_A) != 0x7F000001 { panic("cname") }
	if r.ZoneLookup(3, RR_A) != 0x08080808 { panic("cname2") }
	if r.ZoneLookup(10, RR_A) != NXDOMAIN { panic("loop") }
	if r.ZoneLookup(20, RR_A) != NXDOMAIN { panic("deep") }

	r.CacheInit()
	first := r.Resolve(1, RR_A)
	if r.LastStatus != 0 { panic("first miss") }
	second := r.Resolve(1, RR_A)
	if r.LastStatus != 1 { panic("second hit") }
	if second != first { panic("same") }

	r.AdvanceTime(301)
	third := r.Resolve(1, RR_A)
	if r.LastStatus != 0 { panic("expired") }
	if third != 0x7F000001 { panic("requery") }

	r.CacheInit()
	if r.Resolve(99, RR_A) != NXDOMAIN { panic("nxdomain") }
	r.Resolve(99, RR_A)
	if r.LastStatus != 1 { panic("neg cache") }

	if r.ZoneLookup(1, RR_MX) != 10 { panic("mx") }
	if r.ZoneLookup(1, RR_TXT) != 99 { panic("txt") }
	if r.ZoneLookup(1, RR_AAAA) != NXDOMAIN { panic("aaaa") }

	fmt.Println("dns: 15/15 ok")
}
