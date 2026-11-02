#ifndef SEAT_SCOUT_CORE_H
#define SEAT_SCOUT_CORE_H

#include <stddef.h>
#include <stdint.h>

enum {
    TC_NORM_ABBREV = 1,        
    TC_NORM_PARTIAL_LAST = 2   
};

size_t tc_normalize(const char *utf8, char *out, size_t cap, unsigned flags);

size_t tc_edit_distance(const char *a, size_t alen, const char *b, size_t blen, size_t max);

typedef struct TcStations TcStations;

typedef struct TcStation {
    uint32_t kod;        
    uint32_t epa;        
    uint32_t eva;        
    float lat;
    float lon;
    const char *name;    
    const char *key;     
} TcStation;

typedef enum TcMatchKind {
    TC_MATCH_NONE = 0,
    TC_MATCH_EXACT = 1,
    TC_MATCH_PREFIX = 2,
    TC_MATCH_CONTAINS = 3,
    TC_MATCH_FUZZY = 4
} TcMatchKind;

TcStations *tc_stations_open(const char *path);
 
TcStations *tc_stations_open_buffer(const void *data, size_t len);
void tc_stations_close(TcStations *s);

size_t tc_stations_count(const TcStations *s);
int tc_stations_get(const TcStations *s, size_t index, TcStation *out);

int tc_stations_find_eva(const TcStations *s, uint32_t eva, TcStation *out);

int tc_stations_find(const TcStations *s, const char *query, TcStation *out);

size_t tc_stations_suggest(const TcStations *s, const char *query, TcStation *out, size_t cap);

#endif
