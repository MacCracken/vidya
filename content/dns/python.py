# Vidya — DNS in Python
#
# In-memory resolver: zone, CNAME chains, TTL cache, negative cache.

RR_A = 1
RR_AAAA = 2
RR_CNAME = 3
RR_MX = 4
RR_TXT = 5

CNAME_MAX_DEPTH = 16
NXDOMAIN = -1
NEGATIVE_TTL = 300


class Resolver:
    def __init__(self):
        self.zone = []  # list of (name, rtype, ttl, value)
        self.cache = []  # list of [name, rtype, value, expires]
        self.now = 0
        self.last_status = 0

    def zone_add(self, name, rtype, ttl, value):
        self.zone.append((name, rtype, ttl, value))

    def zone_lookup(self, name, rtype):
        depth = 0
        cur = name
        while depth <= CNAME_MAX_DEPTH:
            for n, t, _, v in self.zone:
                if n == cur and t == rtype:
                    return v
            if rtype == RR_A:
                cn = 0
                for n, t, _, v in self.zone:
                    if n == cur and t == RR_CNAME:
                        cn = v
                        break
                if cn == 0:
                    return NXDOMAIN
                cur = cn
                depth += 1
            else:
                return NXDOMAIN
        return NXDOMAIN

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
        if v == NXDOMAIN:
            self.cache_insert(name, rtype, NXDOMAIN, NEGATIVE_TTL)
            return NXDOMAIN
        ttl = NEGATIVE_TTL
        for n, t, ttl_v, _ in self.zone:
            if n == name and t == rtype:
                ttl = ttl_v
                break
        self.cache_insert(name, rtype, v, ttl)
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
    assert r.zone_lookup(10, RR_A) == NXDOMAIN
    assert r.zone_lookup(20, RR_A) == NXDOMAIN

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

    r.cache_init()
    assert r.resolve(99, RR_A) == NXDOMAIN
    r.resolve(99, RR_A)
    assert r.last_status == 1

    assert r.zone_lookup(1, RR_MX) == 10
    assert r.zone_lookup(1, RR_TXT) == 99
    assert r.zone_lookup(1, RR_AAAA) == NXDOMAIN

    print("dns: 15/15 ok")


main()
