#include "seat_scout_core.h"

#include <string.h>

typedef struct {
    uint32_t cp;
    char ascii;
} Fold;

static const Fold FOLDS[] = {
    {0x0105, 'a'}, {0x0104, 'a'}, {0x0107, 'c'}, {0x0106, 'c'}, {0x0119, 'e'}, {0x0118, 'e'},
    {0x0142, 'l'}, {0x0141, 'l'}, {0x0144, 'n'}, {0x0143, 'n'}, {0x00F3, 'o'}, {0x00D3, 'o'},
    {0x015B, 's'}, {0x015A, 's'}, {0x017A, 'z'}, {0x0179, 'z'}, {0x017C, 'z'}, {0x017B, 'z'},
    {0x00E4, 'a'}, {0x00C4, 'a'}, {0x00F6, 'o'}, {0x00D6, 'o'}, {0x00FC, 'u'}, {0x00DC, 'u'},
    {0x00E1, 'a'}, {0x00C1, 'a'}, {0x00E9, 'e'}, {0x00C9, 'e'}, {0x00ED, 'i'}, {0x00CD, 'i'},
    {0x00FD, 'y'}, {0x00DD, 'y'}, {0x00FA, 'u'}, {0x00DA, 'u'}, {0x010D, 'c'}, {0x010C, 'c'},
    {0x0161, 's'}, {0x0160, 's'}, {0x017E, 'z'}, {0x017D, 'z'}, {0x0159, 'r'}, {0x0158, 'r'},
    {0x011B, 'e'}, {0x011A, 'e'}, {0x010F, 'd'}, {0x010E, 'd'}, {0x0165, 't'}, {0x0164, 't'},
    {0x0148, 'n'}, {0x0147, 'n'}, {0x016F, 'u'}, {0x016E, 'u'}, {0x013E, 'l'}, {0x013D, 'l'},
};

typedef struct {
    const char *full;
    const char *abbr;
} Abbrev;

static const Abbrev ABBREVS[] = {
    {"centralna", "centr"}, {"centralny", "centr"}, {"glowna", "gl"},     {"glowny", "gl"},
    {"glowne", "gl"},       {"centralne", "centr"},
    {"wschodnia", "wsch"},  {"wschodni", "wsch"},   {"zachodnia", "zach"}, {"zachodni", "zach"},
};
#define N_ABBREVS (sizeof(ABBREVS) / sizeof(ABBREVS[0]))

static uint32_t decode(const unsigned char *s, size_t *adv) {
    unsigned char c = s[0];
    if (c < 0x80) { *adv = 1; return c; }
    size_t n = 0;
    uint32_t cp = 0;
    if ((c & 0xE0) == 0xC0) { n = 2; cp = c & 0x1F; }
    else if ((c & 0xF0) == 0xE0) { n = 3; cp = c & 0x0F; }
    else if ((c & 0xF8) == 0xF0) { n = 4; cp = c & 0x07; }
    else { *adv = 1; return 0xFFFD; }
    for (size_t i = 1; i < n; i++) {
        if ((s[i] & 0xC0) != 0x80) { *adv = i; return 0xFFFD; }  
        cp = (cp << 6) | (s[i] & 0x3F);
    }
    *adv = n;
    return cp;
}

static char fold_cp(uint32_t cp) {
    if (cp < 0x80) {
        if (cp >= 'A' && cp <= 'Z') return (char)(cp - 'A' + 'a');
        if ((cp >= 'a' && cp <= 'z') || (cp >= '0' && cp <= '9')) return (char)cp;
        return 0;
    }
    for (size_t i = 0; i < sizeof(FOLDS) / sizeof(FOLDS[0]); i++)
        if (FOLDS[i].cp == cp) return FOLDS[i].ascii;
    return 0;
}

static const char *map_token(const char *tok, size_t len, int is_last, unsigned flags) {
    if (!(flags & TC_NORM_ABBREV)) return NULL;
    for (size_t i = 0; i < N_ABBREVS; i++)
        if (strlen(ABBREVS[i].full) == len && memcmp(ABBREVS[i].full, tok, len) == 0)
            return ABBREVS[i].abbr;
    if ((flags & TC_NORM_PARTIAL_LAST) && is_last && len >= 3) {
        for (size_t i = 0; i < N_ABBREVS; i++)
            if (strlen(ABBREVS[i].full) > len && memcmp(ABBREVS[i].full, tok, len) == 0)
                return ABBREVS[i].abbr;
    }
    return NULL;
}

size_t tc_normalize(const char *utf8, char *out, size_t cap, unsigned flags) {
     
    char tmp[512];
    size_t tl = 0;
    int pending_sep = 0;
    if (utf8) {
        const unsigned char *p = (const unsigned char *)utf8;
        while (*p && tl < sizeof(tmp) - 2) {
            size_t adv;
            uint32_t cp = decode(p, &adv);
            char c = fold_cp(cp);
            if (c) {
                if (pending_sep && tl > 0) tmp[tl++] = ' ';
                pending_sep = 0;
                tmp[tl++] = c;
            } else {
                pending_sep = 1;
            }
            p += adv;
        }
    }
    tmp[tl] = '\0';

    size_t ol = 0;
    size_t i = 0;
    while (i < tl) {
        size_t j = i;
        while (j < tl && tmp[j] != ' ') j++;
        int is_last = (j >= tl);
        const char *m = map_token(tmp + i, j - i, is_last, flags);
        const char *src = m ? m : tmp + i;
        size_t n = m ? strlen(m) : j - i;
        for (size_t k = 0; k < n; k++) {
            if (cap && ol + 1 < cap) out[ol] = src[k];
            ol++;
        }
        i = j + 1;
    }
    if (cap) out[ol < cap ? ol : cap - 1] = '\0';
    return ol;
}

size_t tc_edit_distance(const char *a, size_t alen, const char *b, size_t blen, size_t max) {
    enum { LIM = 255 };
    if (alen > LIM || blen > LIM) return max + 1;
    size_t diff = alen > blen ? alen - blen : blen - alen;
    if (diff > max) return max + 1;

    size_t prev[LIM + 1], cur[LIM + 1];
    for (size_t j = 0; j <= blen; j++) prev[j] = j;
    for (size_t i = 1; i <= alen; i++) {
        cur[0] = i;
        size_t row_min = cur[0];
        for (size_t j = 1; j <= blen; j++) {
            size_t cost = a[i - 1] == b[j - 1] ? 0 : 1;
            size_t v = prev[j - 1] + cost;
            if (prev[j] + 1 < v) v = prev[j] + 1;
            if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
            cur[j] = v;
            if (v < row_min) row_min = v;
        }
        if (row_min > max) return max + 1;
        memcpy(prev, cur, (blen + 1) * sizeof(size_t));
    }
    return prev[blen] > max ? max + 1 : prev[blen];
}
