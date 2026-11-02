#ifndef SEAT_SCOUT_CORE_H
#define SEAT_SCOUT_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum TcStatus {
    TC_OK = 0,
    TC_ERR_ARG = -1,
    TC_ERR_TRANSPORT = -2,
    TC_ERR_BLOCKED = -3,
    TC_ERR_HTTP = -4,
    TC_ERR_PARSE = -5,
    TC_ERR_NOT_FOUND = -6,
    TC_ERR_INTERNAL = -7
} TcStatus;

const char *tc_version(void);
const char *tc_last_error(void);

int tc_last_http_status(void);

typedef struct TcHttpResponse {
    int status;
    char *data;
    size_t len;
} TcHttpResponse;

typedef int (*TcHttpFn)(void *ctx, const char *method, const char *url,
                        const char *body, TcHttpResponse *out);

typedef struct TcTransport {
    void *ctx;
    TcHttpFn fn;
} TcTransport;

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

int tc_fetch_stations_packed(const TcTransport *t, uint8_t **out_data, size_t *out_len);

int tc_pack_stations_json(const char *json, size_t len, uint8_t **out_data, size_t *out_len);
void tc_buffer_free(uint8_t *data, size_t len);

typedef enum TcSeatPosition {
    TC_POS_UNKNOWN = 0,
    TC_POS_WINDOW = 1,
    TC_POS_AISLE = 2
} TcSeatPosition;

typedef struct TcSeat {
    uint16_t number;
    uint8_t free;
    uint8_t position;
    uint8_t special;
    uint8_t has_xy;
    int16_t x;
    int16_t y;
} TcSeat;

typedef struct TcDecor {
    int16_t x, y, w, h;
    uint8_t kind;
    char code[8];
    const char *title;
} TcDecor;

typedef struct TcWagon {
    uint8_t klasa;
    int32_t wagon;
    uint32_t free_count;
    uint32_t occupied_count;
    const TcSeat *seats;
    size_t seats_len;
    int16_t width, height;
    const TcDecor *decor;
    size_t decor_len;
} TcWagon;

typedef struct TcSeatReport TcSeatReport;

TcSeatReport *tc_parse_wagon_svg(const char *svg, size_t len, int default_class,
                                 int exclude_special);
int32_t tc_report_direction(const TcSeatReport *r);
int32_t tc_report_compartments(const TcSeatReport *r, size_t index);
size_t tc_report_count(const TcSeatReport *r);
int tc_report_get(const TcSeatReport *r, size_t index, TcWagon *out);

size_t tc_report_warning_count(const TcSeatReport *r);
const char *tc_report_warning(const TcSeatReport *r, size_t index);
void tc_report_free(TcSeatReport *r);

TcSeatReport *tc_seats_for_segment(const TcTransport *t, const char *category, int64_t train_nr,
                                   uint32_t from_epa, uint32_t to_epa,
                                   const char *dep_compact, const char *arr_compact,
                                   int klasa, int exclude_special, uint32_t delay_ms,
                                   uint32_t concurrency);

int tc_time_compact(const char *text, char *out, size_t cap);

int tc_grm_available(const TcTransport *t, int64_t train_nr, const char *date_compact);

typedef struct TcTrain {
    int64_t id_polaczenia;
    int64_t number;
    const char *category;
    const char *name;
    const char *dep;
    const char *arr;
    uint32_t from_kod;
    uint32_t to_kod;
} TcTrain;

typedef struct TcConnections TcConnections;

TcConnections *tc_search_connections(const TcTransport *t, const char *date,
                                     uint32_t from_kod, uint32_t to_kod);
size_t tc_connections_count(const TcConnections *c);
int tc_connections_get(const TcConnections *c, size_t index, TcTrain *out);
void tc_connections_free(TcConnections *c);

typedef struct TcStop {
    const char *name;
    uint32_t eva;
    uint32_t epa;
    const char *arr;
    const char *dep;
    uint8_t can_board;
    uint8_t can_alight;
    const char *platform;
    const char *track;
    const char *arr_actual;
    const char *dep_actual;
    const char *messages;
} TcStop;

typedef struct TcRoute TcRoute;

TcRoute *tc_train_route(const TcTransport *t, const TcTrain *train, uint32_t from_eva,
                        uint32_t to_eva);
size_t tc_route_count(const TcRoute *r);
int tc_route_get(const TcRoute *r, size_t index, TcStop *out);
void tc_route_free(TcRoute *r);

int tc_compact_minutes(const char *compact, int64_t *out);

typedef enum TcTripState {
    TC_TRIP_NOT_STARTED = 0,
    TC_TRIP_AT_STATION = 1,
    TC_TRIP_BETWEEN = 2,
    TC_TRIP_FINISHED = 3
} TcTripState;

typedef struct TcTripStatus {
    uint8_t state;
    uint8_t source;
    uint32_t from_index;
    uint32_t to_index;
    uint8_t has_delay;
    int32_t delay_min;
    uint8_t has_next;
    int32_t minutes_to_next;
    uint32_t progress_permille;
} TcTripStatus;

typedef struct TcStopPrediction {
    int64_t sched_arr, sched_dep;
    int64_t arr, dep;
    uint8_t arr_actual, dep_actual;
} TcStopPrediction;

typedef struct TcTrip TcTrip;

TcTrip *tc_route_track(const TcRoute *route, int64_t now_minutes);
int tc_trip_status(const TcTrip *trip, TcTripStatus *out);
int tc_trip_stop(const TcTrip *trip, size_t index, TcStopPrediction *out);
void tc_trip_free(TcTrip *trip);

int tc_ticket_price(const TcTransport *t, const TcTrain *train, int klasa, int discount_code,
                    double *out_pln);

typedef struct TcPlanner TcPlanner;

TcPlanner *tc_planner_new(size_t stop_count, const int32_t *arr_min, const int32_t *dep_min);
void tc_planner_free(TcPlanner *p);

int tc_planner_add_free_seat(TcPlanner *p, size_t leg, int32_t wagon, uint16_t seat, int window);

int tc_planner_add_free_seat_xy(TcPlanner *p, size_t leg, int32_t wagon, uint16_t seat, int window,
                                int has_xy, int32_t x, int32_t y);

typedef struct TcPlanRun {
    uint32_t from_stop;
    uint32_t to_stop;
    int32_t wagon;
    uint16_t seat;
    uint8_t has_seat;
    uint8_t window;
    int32_t minutes;
    uint16_t seat2;
    uint8_t has_seat2;
} TcPlanRun;

typedef struct TcPlanSummary {
    int32_t seated_minutes;
    int32_t total_minutes;
    uint32_t changes;
    uint32_t full_ride_seats;
} TcPlanSummary;

typedef struct TcPlan TcPlan;

TcPlan *tc_planner_solve(const TcPlanner *p, size_t board_stop, size_t alight_stop,
                         int32_t change_penalty_min);

TcPlan *tc_planner_solve_pairs(const TcPlanner *p, size_t board_stop, size_t alight_stop,
                               int32_t change_penalty_min);

int tc_planner_solve_separate(const TcPlanner *p, size_t board_stop, size_t alight_stop,
                              int32_t change_penalty_min, TcPlan **out_a, TcPlan **out_b);
int tc_plan_summary(const TcPlan *plan, TcPlanSummary *out);
size_t tc_plan_run_count(const TcPlan *plan);
int tc_plan_run(const TcPlan *plan, size_t index, TcPlanRun *out);
void tc_plan_free(TcPlan *plan);

#ifdef __cplusplus
}
#endif

#endif
