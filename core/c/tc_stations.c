#include "seat_scout_core.h"

#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define HDR_SIZE 24u
#define ENT_SIZE 32u
#define MAX_TOP 64u
#define MAX_KEY 256u

struct TcStations {
    const uint8_t *base;
    size_t len;
    int mapped;
    uint32_t count;
    const uint8_t *table;
    const char *pool;
    uint32_t pool_size;
};

static uint32_t rd32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static float rdf(const uint8_t *p) {
    uint32_t u = rd32(p);
    float f;
    memcpy(&f, &u, sizeof f);
    return f;
}

static const char *str_at(const TcStations *s, uint32_t off) { return s->pool + off; }

static const char *key_at(const TcStations *s, size_t i) {
    return str_at(s, rd32(s->table + i * ENT_SIZE));
}

static int offset_ok(const TcStations *s, uint32_t off) {
    if (off >= s->pool_size) return 0;
    return memchr(s->pool + off, '\0', s->pool_size - off) != NULL;
}

TcStations *tc_stations_open_buffer(const void *data, size_t len) {
    const uint8_t *b = data;
    if (!b || len < HDR_SIZE || memcmp(b, "TCST", 4) != 0 || rd32(b + 4) != 1) return NULL;
    uint32_t count = rd32(b + 8), table_off = rd32(b + 12), pool_off = rd32(b + 16),
             pool_size = rd32(b + 20);
    if ((uint64_t)table_off + (uint64_t)count * ENT_SIZE > len) return NULL;
    if ((uint64_t)pool_off + pool_size > len) return NULL;

    TcStations *s = calloc(1, sizeof *s);
    if (!s) return NULL;
    s->base = b;
    s->len = len;
    s->count = count;
    s->table = b + table_off;
    s->pool = (const char *)(b + pool_off);
    s->pool_size = pool_size;

    const char *prev = NULL;
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *e = s->table + (size_t)i * ENT_SIZE;
        if (!offset_ok(s, rd32(e)) || !offset_ok(s, rd32(e + 4))) { free(s); return NULL; }
        const char *k = key_at(s, i);
        if (prev && strcmp(prev, k) > 0) { free(s); return NULL; }  
        prev = k;
    }
    return s;
}

TcStations *tc_stations_open(const char *path) {
    if (!path) return NULL;
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < (off_t)HDR_SIZE) { close(fd); return NULL; }
    void *m = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (m == MAP_FAILED) return NULL;
    TcStations *s = tc_stations_open_buffer(m, (size_t)st.st_size);
    if (!s) { munmap(m, (size_t)st.st_size); return NULL; }
    s->mapped = 1;
    return s;
}

void tc_stations_close(TcStations *s) {
    if (!s) return;
    if (s->mapped) munmap((void *)s->base, s->len);
    free(s);
}

size_t tc_stations_count(const TcStations *s) { return s ? s->count : 0; }

static void fill(const TcStations *s, size_t i, TcStation *out) {
    const uint8_t *e = s->table + i * ENT_SIZE;
    out->key = str_at(s, rd32(e));
    out->name = str_at(s, rd32(e + 4));
    out->kod = rd32(e + 8);
    out->epa = rd32(e + 12);
    out->eva = rd32(e + 16);
    out->lat = rdf(e + 20);
    out->lon = rdf(e + 24);
}

int tc_stations_get(const TcStations *s, size_t index, TcStation *out) {
    if (!s || !out || index >= s->count) return -1;
    fill(s, index, out);
    return 0;
}

int tc_stations_find_eva(const TcStations *s, uint32_t eva, TcStation *out) {
    if (!s || !out || eva == 0) return -1;
    for (size_t i = 0; i < s->count; i++) {
        if (rd32(s->table + i * ENT_SIZE + 16) == eva) {
            fill(s, i, out);
            return 0;
        }
    }
    return -1;
}

static size_t lower_bound(const TcStations *s, const char *q) {
    size_t lo = 0, hi = s->count;
    while (lo < hi) {
        size_t mid = lo + (hi - lo) / 2;
        if (strcmp(key_at(s, mid), q) < 0) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

typedef struct {
    int tier;       
    size_t dist;
    size_t klen;
    size_t idx;
} Cand;

static int cand_less(const Cand *a, const Cand *b) {
    if (a->tier != b->tier) return a->tier < b->tier;
    if (a->dist != b->dist) return a->dist < b->dist;
    return a->idx < b->idx;
}

typedef struct {
    Cand c[MAX_TOP];
    size_t n, cap;
} Top;

static void top_add(Top *t, Cand c) {
    for (size_t i = 0; i < t->n; i++) {
        if (t->c[i].idx == c.idx) {
            if (!cand_less(&c, &t->c[i])) return;
            memmove(t->c + i, t->c + i + 1, (t->n - i - 1) * sizeof(Cand));
            t->n--;
            break;
        }
    }
    size_t pos = t->n;
    while (pos > 0 && cand_less(&c, &t->c[pos - 1])) pos--;
    if (pos >= t->cap) return;
    size_t last = t->n < t->cap ? t->n : t->cap - 1;
    memmove(t->c + pos + 1, t->c + pos, (last - pos) * sizeof(Cand));
    t->c[pos] = c;
    if (t->n < t->cap) t->n++;
}

static size_t fuzzy_limit(size_t qlen) {
    if (qlen <= 3) return 0;
    if (qlen <= 6) return 1;
    if (qlen <= 10) return 2;
    return 3;
}

static void collect(const TcStations *s, const char *q, size_t qlen, Top *top) {
    if (qlen == 0) return;

    for (size_t i = lower_bound(s, q); i < s->count; i++) {
        const char *k = key_at(s, i);
        if (strncmp(k, q, qlen) != 0) break;
        size_t klen = strlen(k);
        Cand c = {klen == qlen ? 1 : 2, 0, klen, i};
        top_add(top, c);
    }
    if (top->n >= top->cap && top->c[top->n - 1].tier <= 2) return;

    size_t lim = fuzzy_limit(qlen);
    for (size_t i = 0; i < s->count; i++) {
        const char *k = key_at(s, i);
        size_t klen = strlen(k);
        if (klen >= qlen && strncmp(k, q, qlen) == 0) continue;
        if (strstr(k, q)) {
            Cand c = {3, 0, klen, i};
            top_add(top, c);
            continue;
        }
        if (!lim) continue;
        size_t d = tc_edit_distance(q, qlen, k, klen, lim);
        size_t pl = klen < qlen ? klen : qlen;
        size_t dp = tc_edit_distance(q, qlen, k, pl, lim);  
        if (dp < d) d = dp;
        if (d <= lim) {
            Cand c = {4, d, klen, i};
            top_add(top, c);
        }
    }
}

static size_t run(const TcStations *s, const char *query, size_t cap, Top *top) {
    char qa[MAX_KEY], qr[MAX_KEY];
    size_t la = tc_normalize(query, qa, sizeof qa, TC_NORM_ABBREV | TC_NORM_PARTIAL_LAST);
    size_t lr = tc_normalize(query, qr, sizeof qr, 0);
    if (la >= sizeof qa) la = sizeof qa - 1;
    if (lr >= sizeof qr) lr = sizeof qr - 1;
    top->n = 0;
    top->cap = cap > MAX_TOP ? MAX_TOP : cap;
    if (top->cap == 0) return 0;
    collect(s, qa, la, top);
    if (lr != la || memcmp(qa, qr, la) != 0) collect(s, qr, lr, top);
    return top->n;
}

int tc_stations_find(const TcStations *s, const char *query, TcStation *out) {
    if (!s || !query || !out) return TC_MATCH_NONE;
    Top top;
    if (run(s, query, 1, &top) == 0) return TC_MATCH_NONE;
    fill(s, top.c[0].idx, out);
    return top.c[0].tier;  
}

size_t tc_stations_suggest(const TcStations *s, const char *query, TcStation *out, size_t cap) {
    if (!s || !query || !out) return 0;
    Top top;
    size_t n = run(s, query, cap, &top);
    for (size_t i = 0; i < n; i++) fill(s, top.c[i].idx, &out[i]);
    return n;
}
