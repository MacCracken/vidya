# Vidya — DNS in Python
#
# In-memory resolver: zone, CNAME chains, TTL cache, negative cache.

RR_A = 1
RR_AAAA = 2
RR_CNAME = 3
RR_MX = 4
RR_TXT = 5

CNAME_MAX_DEPTH = 16
NXDOMAIN = -1  # the name does not exist at all (RCODE 3)
NODATA = -2    # the name exists, but has no record of this type (RFC 2308 §2.2)
SERVFAIL = -3  # CNAME loop or chain too deep: an error, not a negative answer
NEGATIVE_TTL = 300


class Resolver:
    def __init__(self):
        self.zone = []  # list of (name, rtype, ttl, value)
        self.cache = []  # list of [name, rtype, value, expires]
        self.now = 0
        self.last_status = 0
        self.last_ttl = 0  # min TTL over every record on the last answer's chain

    def zone_add(self, name, rtype, ttl, value):
        self.zone.append((name, rtype, ttl, value))

    def zone_lookup(self, name, rtype):
        depth = 0
        cur = name
        self.last_ttl = NEGATIVE_TTL
        chain_ttl = None
        while depth <= CNAME_MAX_DEPTH:
            for n, t, ttl, v in self.zone:
                if n == cur and t == rtype:
                    # Every record on a CNAME chain expires on its own TTL,
                    # so the composed answer is only good for its
                    # SHORTEST-lived link.
                    self.last_ttl = ttl if chain_ttl is None else min(chain_ttl, ttl)
                    return v
            exists = any(n == cur for n, _, _, _ in self.zone)
            if rtype == RR_A:
                cn = 0
                for n, t, ttl, v in self.zone:
                    if n == cur and t == RR_CNAME:
                        cn = v
                        chain_ttl = ttl if chain_ttl is None else min(chain_ttl, ttl)
                        break
                if cn == 0:
                    return NODATA if exists else NXDOMAIN
                cur = cn
                depth += 1
            else:
                return NODATA if exists else NXDOMAIN
        return SERVFAIL

    def cache_init(self):
        self.cache = []
        self.now = 0

    def advance_time(self, secs):
        self.now += secs

    def cache_insert(self, name, rtype, value, ttl):
        exp = self.now + ttl
        for slot in self.cache:
            if slot[0] == name and slot[1] == rtype:
                slot[2] = value
                slot[3] = exp
                return
        self.cache.append([name, rtype, value, exp])

    def cache_lookup(self, name, rtype):
        for slot in self.cache:
            if slot[0] == name and slot[1] == rtype and slot[3] > self.now:
                self.last_status = 1
                return slot[2]
        self.last_status = 0
        return NXDOMAIN

    def resolve(self, name, rtype):
        cached = self.cache_lookup(name, rtype)
        if self.last_status == 1:
            return cached
        v = self.zone_lookup(name, rtype)
        if v < 0:  # NXDOMAIN, NODATA and SERVFAIL are all cached briefly
            self.cache_insert(name, rtype, v, NEGATIVE_TTL)
            return v
        # Not "the TTL of a (name, rtype) record": for 3 -> CNAME -> 4 no such
        # record exists and the old fallback cached 4's 60 s A for 300 s.
        self.cache_insert(name, rtype, v, self.last_ttl)
        return v


def main():
    r = Resolver()
    r.zone_add(1, RR_A, 300, 0x7F000001)
    r.zone_add(1, RR_MX, 3600, 10)
    r.zone_add(1, RR_TXT, 60, 99)
    r.zone_add(2, RR_CNAME, 600, 1)
    r.zone_add(3, RR_CNAME, 600, 4)
    r.zone_add(4, RR_A, 60, 0x08080808)
    r.zone_add(5, RR_A, 3600, 0x0A000001)
    r.zone_add(10, RR_CNAME, 600, 11)
    r.zone_add(11, RR_CNAME, 600, 10)
    for k in range(20, 37):
        r.zone_add(k, RR_CNAME, 600, k + 1)
    r.zone_add(37, RR_A, 60, 0x12345678)

    assert r.zone_lookup(1, RR_A) == 0x7F000001
    assert r.zone_lookup(2, RR_A) == 0x7F000001
    assert r.zone_lookup(3, RR_A) == 0x08080808
    assert r.zone_lookup(10, RR_A) == SERVFAIL  # 10 -> 11 -> 10 loop
    assert r.zone_lookup(20, RR_A) == SERVFAIL  # 17 hops > CNAME_MAX_DEPTH

    r.cache_init()
    first = r.resolve(1, RR_A)
    assert r.last_status == 0
    second = r.resolve(1, RR_A)
    assert r.last_status == 1
    assert second == first

    r.advance_time(301)
    third = r.resolve(1, RR_A)
    assert r.last_status == 0
    assert third == 0x7F000001

    # CNAME-resolved answer expires with its shortest link (4's A: 60 s)
    r.cache_init()
    assert r.resolve(3, RR_A) == 0x08080808
    r.advance_time(61)
    r.resolve(3, RR_A)
    assert r.last_status == 0, "expired with the 60 s A record, not 300 s"

    r.cache_init()
    assert r.resolve(99, RR_A) == NXDOMAIN
    r.resolve(99, RR_A)
    assert r.last_status == 1

    assert r.zone_lookup(1, RR_MX) == 10
    assert r.zone_lookup(1, RR_TXT) == 99
    # Name 1 exists (A, MX, TXT) but has no AAAA: NODATA, not NXDOMAIN.
    # NXDOMAIN tells an RFC 8020 resolver that nothing exists at or below
    # the name, so answering NXDOMAIN here would deny name 1's A record too.
    assert r.zone_lookup(1, RR_AAAA) == NODATA

    print("dns: 17/17 ok")


main()
