/* Vidya — DNS in C
 *
 * In-memory resolver: zone, CNAME chains, TTL cache, negative cache.
 */

#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#define RR_A     1
#define RR_AAAA  2
#define RR_CNAME 3
#define RR_MX    4
#define RR_TXT   5

#define CNAME_MAX_DEPTH 16
#define NXDOMAIN ((int64_t)-1)
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

static void zone_add(uint64_t name, int32_t rtype, int64_t ttl, int64_t value) {
    if (zone_count < ZONE_CAP) {
        zone[zone_count++] = (Record){name, rtype, ttl, value};
    }
}

static int64_t zone_lookup(uint64_t name, int32_t rtype) {
    int depth = 0;
    uint64_t cur = name;
    while (depth <= CNAME_MAX_DEPTH) {
        for (int i = 0; i < zone_count; i++) {
            if (zone[i].name == cur && zone[i].rtype == rtype) return zone[i].value;
        }
        if (rtype == RR_A) {
            uint64_t cn = 0;
            for (int i = 0; i < zone_count; i++) {
                if (zone[i].name == cur && zone[i].rtype == RR_CNAME) {
                    cn = (uint64_t)zone[i].value;
                    break;
                }
            }
            if (cn == 0) return NXDOMAIN;
            cur = cn;
            depth++;
        } else {
            return NXDOMAIN;
        }
    }
    return NXDOMAIN;
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
    if (v == NXDOMAIN) {
        cache_insert(name, rtype, NXDOMAIN, NEGATIVE_TTL);
        return NXDOMAIN;
    }
    int64_t ttl = NEGATIVE_TTL;
    for (int i = 0; i < zone_count; i++) {
        if (zone[i].name == name && zone[i].rtype == rtype) { ttl = zone[i].ttl; break; }
    }
    cache_insert(name, rtype, v, ttl);
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

    assert(zone_lookup(1, RR_A) == 0x7F000001);
    assert(zone_lookup(2, RR_A) == 0x7F000001);
    assert(zone_lookup(3, RR_A) == 0x08080808);
    assert(zone_lookup(10, RR_A) == NXDOMAIN);
    assert(zone_lookup(20, RR_A) == NXDOMAIN);

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

    cache_init();
    assert(resolve(99, RR_A) == NXDOMAIN);
    resolve(99, RR_A);
    assert(last_status == 1);

    assert(zone_lookup(1, RR_MX) == 10);
    assert(zone_lookup(1, RR_TXT) == 99);
    assert(zone_lookup(1, RR_AAAA) == NXDOMAIN);

    printf("dns: 15/15 ok\n");
    return 0;
}
