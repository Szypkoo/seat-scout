use crate::api::{self, SegmentQuery};
use crate::error::{Error, Result};
use crate::model::{Position, Stop, Train, WagonSeats};
use crate::svg::parse_wagon_svg;
use crate::transport::{HttpResponse, Transport};
use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_void};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::time::Duration;

extern "C" {
    fn free(p: *mut c_void);
}

const OK: c_int = 0;
const ERR_ARG: c_int = -1;
const ERR_TRANSPORT: c_int = -2;
const ERR_BLOCKED: c_int = -3;
const ERR_HTTP: c_int = -4;
const ERR_PARSE: c_int = -5;
const ERR_NOT_FOUND: c_int = -6;
const ERR_INTERNAL: c_int = -7;

thread_local! {
    static LAST_ERROR: RefCell<CString> = RefCell::new(CString::default());
}

pub(crate) fn set_last_status(s: i32) {
    crate::transport::set_last_http_status(s);
}

fn code(e: &Error) -> c_int {
    match e {
        Error::Arg(_) => ERR_ARG,
        Error::Transport(_) => ERR_TRANSPORT,
        Error::Blocked(_) => ERR_BLOCKED,
        Error::Http(_) => ERR_HTTP,
        Error::Parse(_) => ERR_PARSE,
        Error::NotFound(_) => ERR_NOT_FOUND,
    }
}

fn fail(e: Error) -> c_int {
    if let Error::Blocked(c) | Error::Http(c) = &e {
        set_last_status(*c);
    }
    let msg = e.to_string().replace('\0', " ");
    LAST_ERROR.with(|l| *l.borrow_mut() = CString::new(msg).unwrap_or_default());
    code(&e)
}

fn guard<T>(f: impl FnOnce() -> Result<T>) -> std::result::Result<T, c_int> {
    set_last_status(0);
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(v)) => Ok(v),
        Ok(Err(e)) => Err(fail(e)),
        Err(_) => {
            fail(Error::Parse("błąd wewnętrzny".into()));
            Err(ERR_INTERNAL)
        }
    }
}

fn guard_ptr<T>(f: impl FnOnce() -> Result<Box<T>>) -> *mut T {
    match guard(f) {
        Ok(b) => Box::into_raw(b),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn tc_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn tc_last_error() -> *const c_char {
    LAST_ERROR.with(|l| l.borrow().as_ptr())
}

#[no_mangle]
pub extern "C" fn tc_last_http_status() -> c_int {
    crate::transport::last_http_status()
}

#[repr(C)]
pub struct TcHttpResponse {
    pub status: c_int,
    pub data: *mut c_char,
    pub len: usize,
}

pub type TcHttpFn = Option<
    unsafe extern "C" fn(
        ctx: *mut c_void,
        method: *const c_char,
        url: *const c_char,
        body: *const c_char,
        out: *mut TcHttpResponse,
    ) -> c_int,
>;

#[repr(C)]
pub struct TcTransport {
    pub ctx: *mut c_void,
    pub fn_: TcHttpFn,
}

struct FfiTransport<'a>(&'a TcTransport);

unsafe impl Sync for FfiTransport<'_> {}

impl Transport for FfiTransport<'_> {
    fn request(&self, method: &str, url: &str, body: Option<&str>) -> Result<HttpResponse> {
        let f = self
            .0
            .fn_
            .ok_or_else(|| Error::Arg("transport.fn == NULL".into()))?;
        let m = CString::new(method).map_err(|_| Error::Arg("method".into()))?;
        let u = CString::new(url).map_err(|_| Error::Arg("url".into()))?;
        let b = body
            .map(|b| CString::new(b).map_err(|_| Error::Arg("body".into())))
            .transpose()?;
        let mut out = TcHttpResponse {
            status: 0,
            data: std::ptr::null_mut(),
            len: 0,
        };
        let rc = unsafe {
            f(
                self.0.ctx,
                m.as_ptr(),
                u.as_ptr(),
                b.as_ref().map_or(std::ptr::null(), |c| c.as_ptr()),
                &mut out,
            )
        };
        let text = if out.data.is_null() {
            String::new()
        } else {
            let bytes = unsafe { std::slice::from_raw_parts(out.data as *const u8, out.len) };
            let t = String::from_utf8_lossy(bytes).into_owned();
            unsafe { free(out.data as *mut c_void) };
            t
        };
        if rc != 0 {
            return Err(Error::Transport(format!("callback zwrócił {rc} dla {url}")));
        }
        Ok(HttpResponse {
            status: out.status,
            body: text,
        })
    }
}

fn transport<'a>(t: *const TcTransport) -> Result<FfiTransport<'a>> {
    unsafe { t.as_ref() }
        .map(FfiTransport)
        .ok_or_else(|| Error::Arg("transport == NULL".into()))
}

fn cstr<'a>(p: *const c_char, what: &str) -> Result<&'a str> {
    if p.is_null() {
        return Err(Error::Arg(format!("{what} == NULL")));
    }
    unsafe { CStr::from_ptr(p) }
        .to_str()
        .map_err(|_| Error::Arg(format!("{what}: niepoprawny UTF-8")))
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TcSeat {
    pub number: u16,
    pub free: u8,
    pub position: u8,
    pub special: u8,
    pub has_xy: u8,
    pub x: i16,
    pub y: i16,
}

#[repr(C)]
pub struct TcDecor {
    pub x: i16,
    pub y: i16,
    pub w: i16,
    pub h: i16,
    pub kind: u8,
    pub code: [c_char; 8],
    pub title: *const c_char,
}

#[repr(C)]
pub struct TcWagon {
    pub klasa: u8,
    pub wagon: i32,
    pub free_count: u32,
    pub occupied_count: u32,
    pub seats: *const TcSeat,
    pub seats_len: usize,
    pub width: i16,
    pub height: i16,
    pub decor: *const TcDecor,
    pub decor_len: usize,
}

struct WagonRow {
    wagon: WagonSeats,
    seats: Vec<TcSeat>,
    decor: Vec<TcDecor>,
    _titles: Vec<CString>,
}

pub struct TcSeatReport {
    rows: Vec<WagonRow>,
    warnings: Vec<CString>,
}

impl TcSeatReport {
    fn new(rows: Vec<WagonSeats>) -> Box<Self> {
        let rows = rows
            .into_iter()
            .map(|w| {
                let c = w
                    .seats
                    .iter()
                    .map(|s| TcSeat {
                        number: s.number,
                        free: s.free as u8,
                        position: match s.position {
                            Position::Unknown => 0,
                            Position::Window => 1,
                            Position::Aisle => 2,
                        },
                        special: s.special as u8,
                        has_xy: s.xy.is_some() as u8,
                        x: s.xy
                            .map_or(0, |p| p.0.clamp(i16::MIN as i32, i16::MAX as i32) as i16),
                        y: s.xy
                            .map_or(0, |p| p.1.clamp(i16::MIN as i32, i16::MAX as i32) as i16),
                    })
                    .collect();
                let titles: Vec<CString> = w.layout.decor.iter().map(|d| cs(&d.title)).collect();
                let decor = w
                    .layout
                    .decor
                    .iter()
                    .zip(&titles)
                    .map(|(d, t)| {
                        let mut code = [0 as c_char; 8];
                        for (i, b) in d.code.bytes().take(7).enumerate() {
                            code[i] = b as c_char;
                        }
                        let c16 = |v: i32| v.clamp(i16::MIN as i32, i16::MAX as i32) as i16;
                        TcDecor {
                            x: c16(d.x),
                            y: c16(d.y),
                            w: c16(d.w),
                            h: c16(d.h),
                            kind: (d.kind == "sign") as u8,
                            code,
                            title: t.as_ptr(),
                        }
                    })
                    .collect();
                WagonRow {
                    wagon: w,
                    seats: c,
                    decor,
                    _titles: titles,
                }
            })
            .collect();
        Box::new(TcSeatReport {
            rows,
            warnings: Vec::new(),
        })
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_parse_wagon_svg(
    svg: *const c_char,
    len: usize,
    default_class: c_int,
    exclude_special: c_int,
) -> *mut TcSeatReport {
    guard_ptr(|| {
        if svg.is_null() {
            return Err(Error::Arg("svg == NULL".into()));
        }
        let bytes = std::slice::from_raw_parts(svg as *const u8, len);
        let text =
            std::str::from_utf8(bytes).map_err(|_| Error::Arg("svg: niepoprawny UTF-8".into()))?;
        let class = if default_class == 1 { 1 } else { 2 };
        Ok(TcSeatReport::new(parse_wagon_svg(
            text,
            class,
            exclude_special != 0,
        )?))
    })
}

#[no_mangle]
pub unsafe extern "C" fn tc_seats_for_segment(
    t: *const TcTransport,
    category: *const c_char,
    train_nr: i64,
    from_epa: u32,
    to_epa: u32,
    dep_compact: *const c_char,
    arr_compact: *const c_char,
    klasa: c_int,
    exclude_special: c_int,
    delay_ms: u32,
    concurrency: u32,
) -> *mut TcSeatReport {
    guard_ptr(|| {
        let tr = transport(t)?;
        let q = SegmentQuery {
            category: cstr(category, "category")?,
            train_nr,
            from_epa,
            to_epa,
            dep: cstr(dep_compact, "dep_compact")?,
            arr: cstr(arr_compact, "arr_compact")?,
            class: match klasa {
                0 => None,
                1 | 2 => Some(klasa as u8),
                _ => return Err(Error::Arg("klasa: 0, 1 lub 2".into())),
            },
            exclude_special: exclude_special != 0,
            delay: Duration::from_millis(delay_ms as u64),
            concurrency: concurrency.max(1) as usize,
        };
        let res = api::seats_for_segment_ex(&tr, &q)?;
        let mut report = TcSeatReport::new(res.rows);
        report.warnings = res.warnings.iter().map(|w| cs(w)).collect();
        Ok(report)
    })
}

#[no_mangle]
pub unsafe extern "C" fn tc_report_count(r: *const TcSeatReport) -> usize {
    r.as_ref().map_or(0, |r| r.rows.len())
}

#[no_mangle]
pub unsafe extern "C" fn tc_report_get(
    r: *const TcSeatReport,
    index: usize,
    out: *mut TcWagon,
) -> c_int {
    let (Some(r), Some(out)) = (r.as_ref(), out.as_mut()) else {
        return ERR_ARG;
    };
    let Some(row) = r.rows.get(index) else {
        return ERR_ARG;
    };
    let (w, seats) = (&row.wagon, &row.seats);
    *out = TcWagon {
        klasa: w.class,
        wagon: w.wagon,
        free_count: w.free_count() as u32,
        occupied_count: w.occupied_count() as u32,
        seats: seats.as_ptr(),
        seats_len: seats.len(),
        width: w.layout.width.clamp(0, i16::MAX as i32) as i16,
        height: w.layout.height.clamp(0, i16::MAX as i32) as i16,
        decor: row.decor.as_ptr(),
        decor_len: row.decor.len(),
    };
    OK
}

#[no_mangle]
pub unsafe extern "C" fn tc_report_warning_count(r: *const TcSeatReport) -> usize {
    r.as_ref().map_or(0, |r| r.warnings.len())
}

#[no_mangle]
pub unsafe extern "C" fn tc_report_warning(r: *const TcSeatReport, index: usize) -> *const c_char {
    r.as_ref()
        .and_then(|r| r.warnings.get(index))
        .map_or(std::ptr::null(), |w| w.as_ptr())
}

#[no_mangle]
pub unsafe extern "C" fn tc_report_free(r: *mut TcSeatReport) {
    if !r.is_null() {
        drop(Box::from_raw(r));
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_grm_available(
    t: *const TcTransport,
    train_nr: i64,
    date_compact: *const c_char,
) -> c_int {
    match guard(|| {
        api::grm_available(
            &transport(t)?,
            train_nr,
            cstr(date_compact, "date_compact")?,
        )
    }) {
        Ok(b) => b as c_int,
        Err(c) => c,
    }
}

#[repr(C)]
pub struct TcTrain {
    pub id_polaczenia: i64,
    pub number: i64,
    pub category: *const c_char,
    pub name: *const c_char,
    pub dep: *const c_char,
    pub arr: *const c_char,
    pub from_kod: u32,
    pub to_kod: u32,
}

fn cs(s: &str) -> CString {
    CString::new(s.replace('\0', "")).unwrap_or_default()
}

pub struct TcConnections {
    trains: Vec<Train>,
    strings: Vec<[CString; 4]>,
}

#[no_mangle]
pub unsafe extern "C" fn tc_search_connections(
    t: *const TcTransport,
    date: *const c_char,
    from_kod: u32,
    to_kod: u32,
) -> *mut TcConnections {
    guard_ptr(|| {
        let trains =
            api::search_connections(&transport(t)?, cstr(date, "date")?, from_kod, to_kod)?;
        let strings = trains
            .iter()
            .map(|t| [cs(&t.category), cs(&t.name), cs(&t.dep), cs(&t.arr)])
            .collect();
        Ok(Box::new(TcConnections { trains, strings }))
    })
}

#[no_mangle]
pub unsafe extern "C" fn tc_connections_count(c: *const TcConnections) -> usize {
    c.as_ref().map_or(0, |c| c.trains.len())
}

#[no_mangle]
pub unsafe extern "C" fn tc_connections_get(
    c: *const TcConnections,
    index: usize,
    out: *mut TcTrain,
) -> c_int {
    let (Some(c), Some(out)) = (c.as_ref(), out.as_mut()) else {
        return ERR_ARG;
    };
    let (Some(t), Some(s)) = (c.trains.get(index), c.strings.get(index)) else {
        return ERR_ARG;
    };
    *out = TcTrain {
        id_polaczenia: t.connection_id,
        number: t.number,
        category: s[0].as_ptr(),
        name: s[1].as_ptr(),
        dep: s[2].as_ptr(),
        arr: s[3].as_ptr(),
        from_kod: t.from_kod,
        to_kod: t.to_kod,
    };
    OK
}

#[no_mangle]
pub unsafe extern "C" fn tc_connections_free(c: *mut TcConnections) {
    if !c.is_null() {
        drop(Box::from_raw(c));
    }
}

fn train_from_c(t: *const TcTrain) -> Result<Train> {
    let t = unsafe { t.as_ref() }.ok_or_else(|| Error::Arg("train == NULL".into()))?;
    Ok(Train {
        connection_id: t.id_polaczenia,
        number: t.number,
        category: cstr(t.category, "train.category")?.to_string(),
        name: if t.name.is_null() {
            String::new()
        } else {
            cstr(t.name, "train.name")?.to_string()
        },
        dep: cstr(t.dep, "train.dep")?.to_string(),
        arr: if t.arr.is_null() {
            String::new()
        } else {
            cstr(t.arr, "train.arr")?.to_string()
        },
        from_kod: t.from_kod,
        to_kod: t.to_kod,
    })
}

#[repr(C)]
pub struct TcStop {
    pub name: *const c_char,
    pub eva: u32,
    pub epa: u32,
    pub arr: *const c_char,
    pub dep: *const c_char,
    pub can_board: u8,
    pub can_alight: u8,
    pub platform: *const c_char,
    pub track: *const c_char,
    pub arr_actual: *const c_char,
    pub dep_actual: *const c_char,
    pub messages: *const c_char,
}

pub struct TcRoute {
    stops: Vec<Stop>,
    strings: Vec<[CString; 8]>,
}

#[no_mangle]
pub unsafe extern "C" fn tc_train_route(
    t: *const TcTransport,
    train: *const TcTrain,
    from_eva: u32,
    to_eva: u32,
) -> *mut TcRoute {
    guard_ptr(|| {
        let stops = api::train_route(&transport(t)?, &train_from_c(train)?, from_eva, to_eva)?;
        let strings = stops
            .iter()
            .map(|s| {
                [
                    cs(&s.name),
                    cs(&s.arr),
                    cs(&s.dep),
                    cs(&s.platform),
                    cs(&s.track),
                    cs(&s.arr_actual),
                    cs(&s.dep_actual),
                    cs(&s.messages),
                ]
            })
            .collect();
        Ok(Box::new(TcRoute { stops, strings }))
    })
}

#[no_mangle]
pub unsafe extern "C" fn tc_route_count(r: *const TcRoute) -> usize {
    r.as_ref().map_or(0, |r| r.stops.len())
}

#[no_mangle]
pub unsafe extern "C" fn tc_route_get(r: *const TcRoute, index: usize, out: *mut TcStop) -> c_int {
    let (Some(r), Some(out)) = (r.as_ref(), out.as_mut()) else {
        return ERR_ARG;
    };
    let (Some(s), Some(c)) = (r.stops.get(index), r.strings.get(index)) else {
        return ERR_ARG;
    };
    *out = TcStop {
        name: c[0].as_ptr(),
        eva: s.eva,
        epa: 0,
        arr: c[1].as_ptr(),
        dep: c[2].as_ptr(),
        can_board: s.can_board as u8,
        can_alight: s.can_alight as u8,
        platform: c[3].as_ptr(),
        track: c[4].as_ptr(),
        arr_actual: c[5].as_ptr(),
        dep_actual: c[6].as_ptr(),
        messages: c[7].as_ptr(),
    };
    OK
}

#[no_mangle]
pub unsafe extern "C" fn tc_route_free(r: *mut TcRoute) {
    if !r.is_null() {
        drop(Box::from_raw(r));
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_ticket_price(
    t: *const TcTransport,
    train: *const TcTrain,
    klasa: c_int,
    discount_code: c_int,
    out_pln: *mut f64,
) -> c_int {
    let r = guard(|| {
        if out_pln.is_null() {
            return Err(Error::Arg("out_pln == NULL".into()));
        }
        if klasa != 1 && klasa != 2 {
            return Err(Error::Arg("klasa: 1 lub 2".into()));
        }
        api::ticket_price(
            &transport(t)?,
            &train_from_c(train)?,
            klasa as i64,
            discount_code,
        )
    });
    match r {
        Ok(v) => {
            *out_pln = v;
            OK
        }
        Err(c) => c,
    }
}

fn export_buffer(bytes: Vec<u8>, out_data: *mut *mut u8, out_len: *mut usize) {
    let boxed = bytes.into_boxed_slice();
    unsafe {
        *out_len = boxed.len();
        *out_data = Box::into_raw(boxed) as *mut u8;
    }
}

fn pack_value(v: &serde_json::Value) -> Result<Vec<u8>> {
    let recs = crate::stations::records_from_json(v)?;
    if recs.is_empty() {
        return Err(Error::Parse("pusty słownik stacji".into()));
    }
    Ok(crate::stations::pack(&recs))
}

#[no_mangle]
pub unsafe extern "C" fn tc_fetch_stations_packed(
    t: *const TcTransport,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    let r = guard(|| {
        if out_data.is_null() || out_len.is_null() {
            return Err(Error::Arg("out == NULL".into()));
        }
        pack_value(&api::fetch_stations(&transport(t)?)?)
    });
    match r {
        Ok(bytes) => {
            export_buffer(bytes, out_data, out_len);
            OK
        }
        Err(c) => c,
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_pack_stations_json(
    json: *const c_char,
    len: usize,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> c_int {
    let r = guard(|| {
        if json.is_null() || out_data.is_null() || out_len.is_null() {
            return Err(Error::Arg("NULL".into()));
        }
        let text = std::str::from_utf8(std::slice::from_raw_parts(json as *const u8, len))
            .map_err(|_| Error::Arg("json: UTF-8".into()))?;
        pack_value(&serde_json::from_str(text).map_err(|e| Error::Parse(e.to_string()))?)
    });
    match r {
        Ok(bytes) => {
            export_buffer(bytes, out_data, out_len);
            OK
        }
        Err(c) => c,
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_buffer_free(data: *mut u8, len: usize) {
    if !data.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(data, len)));
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_time_compact(
    text: *const c_char,
    out: *mut c_char,
    cap: usize,
) -> c_int {
    let r = guard(|| {
        let t = cstr(text, "text")?;
        let c = crate::dates::to_compact(t).ok_or_else(|| Error::Parse(format!("czas `{t}`")))?;
        if out.is_null() || cap < c.len() + 1 {
            return Err(Error::Arg("bufor wyjściowy za mały".into()));
        }
        std::ptr::copy_nonoverlapping(c.as_ptr(), out as *mut u8, c.len());
        *out.add(c.len()) = 0;
        Ok(())
    });
    match r {
        Ok(()) => OK,
        Err(c) => c,
    }
}

use crate::planner::{Plan, Planner, SeatRef};

pub struct TcPlanner(Planner);
pub struct TcPlan(Plan);

#[repr(C)]
pub struct TcPlanRun {
    pub from_stop: u32,
    pub to_stop: u32,
    pub wagon: i32,
    pub seat: u16,
    pub has_seat: u8,
    pub window: u8,
    pub minutes: i32,
    pub seat2: u16,
    pub has_seat2: u8,
}

#[repr(C)]
pub struct TcPlanSummary {
    pub seated_minutes: i32,
    pub total_minutes: i32,
    pub changes: u32,
    pub full_ride_seats: u32,
}

#[no_mangle]
pub unsafe extern "C" fn tc_planner_new(
    stop_count: usize,
    arr_min: *const i32,
    dep_min: *const i32,
) -> *mut TcPlanner {
    guard_ptr(|| {
        if arr_min.is_null() || dep_min.is_null() || stop_count < 2 {
            return Err(Error::Arg(
                "planner: potrzeba >= 2 stacji i tablic czasów".into(),
            ));
        }
        let arr = std::slice::from_raw_parts(arr_min, stop_count).to_vec();
        let dep = std::slice::from_raw_parts(dep_min, stop_count).to_vec();
        Ok(Box::new(TcPlanner(Planner::new(arr, dep))))
    })
}

#[no_mangle]
pub unsafe extern "C" fn tc_planner_free(p: *mut TcPlanner) {
    if !p.is_null() {
        drop(Box::from_raw(p));
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_planner_add_free_seat(
    p: *mut TcPlanner,
    leg: usize,
    wagon: i32,
    seat: u16,
    window: c_int,
) -> c_int {
    match p.as_mut() {
        Some(p) if leg < p.0.leg_count() => {
            p.0.add_free_seat(
                leg,
                SeatRef {
                    wagon,
                    number: seat,
                },
                window != 0,
            );
            OK
        }
        _ => ERR_ARG,
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_planner_add_free_seat_xy(
    p: *mut TcPlanner,
    leg: usize,
    wagon: i32,
    seat: u16,
    window: c_int,
    has_xy: c_int,
    x: i32,
    y: i32,
) -> c_int {
    match p.as_mut() {
        Some(p) if leg < p.0.leg_count() => {
            let xy = if has_xy != 0 { Some((x, y)) } else { None };
            p.0.add_free_seat_xy(
                leg,
                SeatRef {
                    wagon,
                    number: seat,
                },
                window != 0,
                xy,
            );
            OK
        }
        _ => ERR_ARG,
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_planner_solve_pairs(
    p: *const TcPlanner,
    board: usize,
    alight: usize,
    change_penalty_min: i32,
) -> *mut TcPlan {
    guard_ptr(|| {
        let p = p
            .as_ref()
            .ok_or_else(|| Error::Arg("planner == NULL".into()))?;
        p.0.solve_pairs(board, alight, change_penalty_min)
            .map(|pl| Box::new(TcPlan(pl)))
            .ok_or_else(|| Error::Arg("niepoprawny zakres stacji".into()))
    })
}

#[no_mangle]
pub unsafe extern "C" fn tc_planner_solve_separate(
    p: *const TcPlanner,
    board: usize,
    alight: usize,
    change_penalty_min: i32,
    out_a: *mut *mut TcPlan,
    out_b: *mut *mut TcPlan,
) -> c_int {
    let r = guard(|| {
        if out_a.is_null() || out_b.is_null() {
            return Err(Error::Arg("out == NULL".into()));
        }
        let p = p
            .as_ref()
            .ok_or_else(|| Error::Arg("planner == NULL".into()))?;
        p.0.solve_separate(board, alight, change_penalty_min)
            .ok_or_else(|| Error::Arg("niepoprawny zakres stacji".into()))
    });
    match r {
        Ok((a, b)) => {
            *out_a = Box::into_raw(Box::new(TcPlan(a)));
            *out_b = Box::into_raw(Box::new(TcPlan(b)));
            OK
        }
        Err(c) => c,
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_planner_solve(
    p: *const TcPlanner,
    board: usize,
    alight: usize,
    change_penalty_min: i32,
) -> *mut TcPlan {
    guard_ptr(|| {
        let p = p
            .as_ref()
            .ok_or_else(|| Error::Arg("planner == NULL".into()))?;
        p.0.solve(board, alight, change_penalty_min)
            .map(|pl| Box::new(TcPlan(pl)))
            .ok_or_else(|| Error::Arg("niepoprawny zakres stacji".into()))
    })
}

#[no_mangle]
pub unsafe extern "C" fn tc_plan_summary(plan: *const TcPlan, out: *mut TcPlanSummary) -> c_int {
    let (Some(p), Some(out)) = (plan.as_ref(), out.as_mut()) else {
        return ERR_ARG;
    };
    *out = TcPlanSummary {
        seated_minutes: p.0.seated_minutes,
        total_minutes: p.0.total_minutes,
        changes: p.0.changes,
        full_ride_seats: p.0.full_ride_seats,
    };
    OK
}

#[no_mangle]
pub unsafe extern "C" fn tc_plan_run_count(plan: *const TcPlan) -> usize {
    plan.as_ref().map_or(0, |p| p.0.runs.len())
}

#[no_mangle]
pub unsafe extern "C" fn tc_plan_run(
    plan: *const TcPlan,
    index: usize,
    out: *mut TcPlanRun,
) -> c_int {
    let (Some(p), Some(out)) = (plan.as_ref(), out.as_mut()) else {
        return ERR_ARG;
    };
    let Some(r) = p.0.runs.get(index) else {
        return ERR_ARG;
    };
    *out = TcPlanRun {
        from_stop: r.from_stop as u32,
        to_stop: r.to_stop as u32,
        wagon: r.seat.map_or(0, |s| s.wagon),
        seat: r.seat.map_or(0, |s| s.number),
        has_seat: r.seat.is_some() as u8,
        window: r.window as u8,
        minutes: r.minutes,
        seat2: r.seat2.map_or(0, |s| s.number),
        has_seat2: r.seat2.is_some() as u8,
    };
    OK
}

#[no_mangle]
pub unsafe extern "C" fn tc_plan_free(plan: *mut TcPlan) {
    if !plan.is_null() {
        drop(Box::from_raw(plan));
    }
}

use crate::tracker::{self, Source, TripState, TripStatus};

pub struct TcTrip(TripStatus);

#[repr(C)]
pub struct TcTripStatus {
    pub state: u8,
    pub source: u8,
    pub from_index: u32,
    pub to_index: u32,
    pub has_delay: u8,
    pub delay_min: i32,
    pub has_next: u8,
    pub minutes_to_next: i32,
    pub progress_permille: u32,
}

#[repr(C)]
pub struct TcStopPrediction {
    pub sched_arr: i64,
    pub sched_dep: i64,
    pub arr: i64,
    pub dep: i64,
    pub arr_actual: u8,
    pub dep_actual: u8,
}

#[no_mangle]
pub unsafe extern "C" fn tc_compact_minutes(compact: *const c_char, out: *mut i64) -> c_int {
    let r = guard(|| {
        let c = cstr(compact, "compact")?;
        crate::dates::compact_to_minutes(c).ok_or_else(|| Error::Parse(format!("czas `{c}`")))
    });
    match r {
        Ok(m) if !out.is_null() => {
            *out = m;
            OK
        }
        Ok(_) => ERR_ARG,
        Err(c) => c,
    }
}

#[no_mangle]
pub unsafe extern "C" fn tc_route_track(route: *const TcRoute, now_minutes: i64) -> *mut TcTrip {
    guard_ptr(|| {
        let r = route
            .as_ref()
            .ok_or_else(|| Error::Arg("route == NULL".into()))?;
        tracker::track(&r.stops, now_minutes)
            .map(|t| Box::new(TcTrip(t)))
            .ok_or_else(|| Error::Parse("trasa bez rozpoznanych godzin".into()))
    })
}

#[no_mangle]
pub unsafe extern "C" fn tc_trip_status(trip: *const TcTrip, out: *mut TcTripStatus) -> c_int {
    let (Some(t), Some(out)) = (trip.as_ref(), out.as_mut()) else {
        return ERR_ARG;
    };
    let t = &t.0;
    let (state, from, to) = match t.state {
        TripState::NotStarted => (0, 0, 0),
        TripState::AtStation(i) => (1, i, i),
        TripState::Between(a, b) => (2, a, b),
        TripState::Finished => (3, 0, 0),
    };
    *out = TcTripStatus {
        state,
        source: matches!(t.source, Source::Actual) as u8,
        from_index: from as u32,
        to_index: to as u32,
        has_delay: t.delay_min.is_some() as u8,
        delay_min: t.delay_min.unwrap_or(0) as i32,
        has_next: t.next_stop.is_some() as u8,
        minutes_to_next: t.minutes_to_next.unwrap_or(0) as i32,
        progress_permille: (t.progress * 1000.0).round() as u32,
    };
    OK
}

#[no_mangle]
pub unsafe extern "C" fn tc_trip_stop(
    trip: *const TcTrip,
    index: usize,
    out: *mut TcStopPrediction,
) -> c_int {
    let (Some(t), Some(out)) = (trip.as_ref(), out.as_mut()) else {
        return ERR_ARG;
    };
    let Some(p) = t.0.stops.get(index) else {
        return ERR_ARG;
    };
    *out = TcStopPrediction {
        sched_arr: p.sched_arr,
        sched_dep: p.sched_dep,
        arr: p.arr,
        dep: p.dep,
        arr_actual: p.arr_actual as u8,
        dep_actual: p.dep_actual as u8,
    };
    OK
}

#[no_mangle]
pub unsafe extern "C" fn tc_trip_free(trip: *mut TcTrip) {
    if !trip.is_null() {
        drop(Box::from_raw(trip));
    }
}
