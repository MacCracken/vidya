// Vidya — DNS in C
//
// In-memory resolver: zone, CNAME chains, TTL cache, negative cache.

#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#define RR_A     1
#define RR_AAAA  2
#define RR_CNAME 3
#define RR_MX    4
#define RR_TXT   5

#define CNAME_MAX_DEPTH 16
#define NXDOMAIN ((int64_t)-1) /* the name does not exist at all (RCODE 3) */
#define NODATA   ((int64_t)-2) /* the name exists, but has no record of this type (RFC 2308 §2.2) */
#define SERVFAIL ((int64_t)-3) /* CNAME loop or chain too deep: an error (RFC 1034 §3.6.2) */
#define NEGATIVE_TTL 300

#define ZONE_CAP 64
#define CACHE_CAP 32

typedef struct { uint64_t name; int32_t rtype; int64_t ttl; int64_t value; } Record;
typedef struct { uint64_t name; int32_t rtype; int64_t value; int64_t expires; } CacheEntry;

static Record zone[ZONE_CAP];
static int zone_count = 0;
static CacheEntry cache[CACHE_CAP];
static int cache_count = 0;
static int64_t now_clock = 0;
static int last_status = 0;
/* TTL of the last successful zone_lookup: the MINIMUM over every record on
 * the CNAME chain. Each link is its own cached record, and the collapsed
 * answer is only valid while every link still is — so it may be cached no
 * longer than its shortest link. */
static int64_t last_ttl = 0;

static void zone_add(uint64_t name, int32_t rtype, int64_t ttl, int64_t value) {
    if (zone_count < ZONE_CAP) {
        zone[zone_count++] = (Record){name, rtype, ttl, value};
    }
}

static int name_exists(uint64_t name) {
    for (int i = 0; i < zone_count; i++) {
        if (zone[i].name == name) return 1;
    }
    return 0;
}

/* Three negative outcomes, three answers. NXDOMAIN tells an RFC 8020
 * resolver that nothing exists at or below the name, so answering it for a
 * name that exists but lacks the type would deny that name's other records
 * too; that case is NODATA. A loop or an over-deep chain is a failure to
 * resolve (SERVFAIL), not a statement about the name. */
static int64_t zone_lookup(uint64_t name, int32_t rtype) {
    int depth = 0;
    uint64_t cur = name;
    int64_t min_ttl = INT64_MAX;
    while (depth <= CNAME_MAX_DEPTH) {
        for (int i = 0; i < zone_count; i++) {
            if (zone[i].name == cur && zone[i].rtype == rtype) {
                last_ttl = zone[i].ttl < min_ttl ? zone[i].ttl : min_ttl;
                return zone[i].value;
            }
        }
        int64_t miss = name_exists(cur) ? NODATA : NXDOMAIN;
        if (rtype == RR_A) {
            uint64_t cn = 0;
            for (int i = 0; i < zone_count; i++) {
                if (zone[i].name == cur && zone[i].rtype == RR_CNAME) {
                    cn = (uint64_t)zone[i].value;
                    if (zone[i].ttl < min_ttl) min_ttl = zone[i].ttl;
                    break;
                }
            }
            if (cn == 0) return miss;
            cur = cn;
            depth++;
        } else {
            return miss;
        }
    }
    return SERVFAIL;
}

static void cache_init(void) { cache_count = 0; now_clock = 0; }
static void advance_time(int64_t s) { now_clock += s; }

static void cache_insert(uint64_t name, int32_t rtype, int64_t value, int64_t ttl) {
    int64_t exp = now_clock + ttl;
    for (int i = 0; i < cache_count; i++) {
        if (cache[i].name == name && cache[i].rtype == rtype) {
            cache[i].value = value; cache[i].expires = exp; return;
        }
    }
    if (cache_count < CACHE_CAP) {
        cache[cache_count++] = (CacheEntry){name, rtype, value, exp};
    }
}

static int64_t cache_lookup(uint64_t name, int32_t rtype) {
    for (int i = 0; i < cache_count; i++) {
        if (cache[i].name == name && cache[i].rtype == rtype && cache[i].expires > now_clock) {
            last_status = 1;
            return cache[i].value;
        }
    }
    last_status = 0;
    return NXDOMAIN;
}

static int64_t resolve(uint64_t name, int32_t rtype) {
    int64_t cached = cache_lookup(name, rtype);
    if (last_status == 1) return cached;
    int64_t v = zone_lookup(name, rtype);
    if (v < 0) { /* NXDOMAIN, NODATA and SERVFAIL are all cached briefly */
        cache_insert(name, rtype, v, NEGATIVE_TTL);
        return v;
    }
    /* Not NEGATIVE_TTL, and not "the TTL of a record named `name`": for a
     * CNAME-chased answer no such record exists, and the old fallback
     * cached 3 -> 4's A (ttl 60) for 300 s. */
    cache_insert(name, rtype, v, last_ttl);
    return v;
}

int main(void) {
    zone_add(1, RR_A, 300, 0x7F000001);
    zone_add(1, RR_MX, 3600, 10);
    zone_add(1, RR_TXT, 60, 99);
    zone_add(2, RR_CNAME, 600, 1);
    zone_add(3, RR_CNAME, 600, 4);
    zone_add(4, RR_A, 60, 0x08080808);
    zone_add(5, RR_A, 3600, 0x0A000001);
    zone_add(10, RR_CNAME, 600, 11);
    zone_add(11, RR_CNAME, 600, 10);
    for (int k = 20; k <= 36; k++) zone_add(k, RR_CNAME, 600, k + 1);
    zone_add(37, RR_A, 60, 0x12345678);

    /* zone_lookup sets last_ttl and resolve fills the cache, so both run
     * outside assert(): under -DNDEBUG assert's expression is not
     * evaluated, and the cache state the later checks rely on would differ. */
    int64_t v = zone_lookup(1, RR_A);
    assert(v == 0x7F000001);
    v = zone_lookup(2, RR_A);
    assert(v == 0x7F000001);
    v = zone_lookup(3, RR_A);
    assert(v == 0x08080808);
    v = zone_lookup(10, RR_A);
    assert(v == SERVFAIL); /* 10 -> 11 -> 10 loop */
    v = zone_lookup(20, RR_A);
    assert(v == SERVFAIL); /* 17 hops > CNAME_MAX_DEPTH */

    cache_init();
    int64_t first = resolve(1, RR_A);
    assert(last_status == 0);
    int64_t second = resolve(1, RR_A);
    assert(last_status == 1);
    assert(second == first);

    advance_time(301);
    int64_t third = resolve(1, RR_A);
    assert(last_status == 0);
    assert(third == 0x7F000001);

    /* CNAME chain 3 -> 4 (A ttl 60): the cached answer expires with the A */
    cache_init();
    v = resolve(3, RR_A);
    assert(v == 0x08080808);
    advance_time(61);
    resolve(3, RR_A);
    assert(last_status == 0);

    cache_init();
    v = resolve(99, RR_A);
    assert(v == NXDOMAIN);
    resolve(99, RR_A);
    assert(last_status == 1);

    v = zone_lookup(1, RR_MX);
    assert(v == 10);
    v = zone_lookup(1, RR_TXT);
    assert(v == 99);
    /* Name 1 exists (A, MX, TXT) but has no AAAA: NODATA, not NXDOMAIN. */
    v = zone_lookup(1, RR_AAAA);
    assert(v == NODATA);
    v = zone_lookup(99, RR_AAAA);
    assert(v == NXDOMAIN);

    printf("dns: 18/18 ok\n");
    return 0;
}
