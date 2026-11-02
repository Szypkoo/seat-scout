use crate::dates;
use crate::error::{Error, Result};
use crate::model::WagonSeats;
use crate::model::{Stop, Train};
use crate::svg::parse_wagon_svg;
use crate::transport::{fetch_json, fetch_text, Transport};
use serde_json::{json, Value};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Mutex;
use std::thread::sleep;
use std::time::{Duration, Instant};

pub const GATEWAY: &str = "https://api-gateway.intercity.pl";
const DEVICE_NO: i64 = 956;
const APP_VERSION: &str = "1.6.13_desktop";

pub fn search_payload(date: &str, from_kod: u32, to_kod: u32) -> Value {
    json!({
        "metoda": "wyszukajPolaczenia",
        "wersja": APP_VERSION,
        "dataWyjazdu": format!("{date} 00:00:00"),
        "dataPrzyjazdu": format!("{date} 23:59:59"),
        "stacjaWyjazdu": from_kod,
        "stacjaPrzyjazdu": to_kod,
        "czasNaPrzesiadkeMin": 5,
        "stacjePrzez": [],
        "polaczeniaBezposrednie": 1,
        "polaczeniaNajszybsze": 0,
        "liczbaPolaczen": 0,
        "kategoriePociagow": [],
        "kodyPrzewoznikow": [],
        "rodzajeMiejsc": [],
        "typyMiejsc": [],
        "czasNaPrzesiadkeMax": 1440,
        "braille": 0,
        "liczbaPrzesiadekMax": 0,
        "atrybutyHandlowe": [],
        "urzadzenieNr": DEVICE_NO
    })
}

pub fn stations_payload() -> Value {
    json!({"metoda": "pobierzStacje", "urzadzenieNr": DEVICE_NO})
}

pub fn route_payload(train: &Train, from_eva: u32, to_eva: u32) -> Value {
    json!({
        "dataWyjazdu": train.dep.replace(' ', "T"),
        "stacjaWyjazdu": from_eva.to_string(),
        "stacjaPrzyjazdu": to_eva.to_string(),
        "numerPociagu": train.number,
        "metoda": "pobierzTrasePrzejazdu",
        "jezyk": "PL",
        "wersja": APP_VERSION,
        "urzadzenieNr": DEVICE_NO
    })
}

pub fn price_payload(train: &Train, discount_code: i32) -> Value {
    json!({
        "metoda": "sprawdzCenyLite",
        "urzadzenieNr": DEVICE_NO,
        "wersja": APP_VERSION,
        "jezyk": "PL",
        "biletTyp": 1,
        "ofertyZaznaczone": [],
        "polaczenia": [{
            "idPolaczenia": train.connection_id,
            "odcinki": [{
                "wyjazdData": train.dep,
                "stacjaOdKod": train.from_kod,
                "stacjaDoKod": train.to_kod,
                "pociagNr": train.number,
                "kategoriaPociagu": train.category
            }]
        }],
        "podrozni": [{"kodZakupowyZnizki": discount_code}]
    })
}

pub fn sklad_url(cat: &str, nr: i64, from_epa: u32, to_epa: u32, dep: &str, arr: &str) -> String {
    format!("{GATEWAY}/grm/sklad/wbnet/{cat}/{nr}/{arr}/{from_epa}/{dep}/{to_epa}")
}

#[allow(clippy::too_many_arguments)]
pub fn wagon_svg_url(
    cat: &str,
    nr: i64,
    wagon: i64,
    schema: &str,
    from_epa: u32,
    to_epa: u32,
    dep: &str,
    arr: &str,
) -> String {
    format!(
        "{GATEWAY}/grm/wagon/svg/wbnet/{cat}/{nr}/{wagon}/{schema}/{dep}/{arr}/{from_epa}/{to_epa}"
    )
}

pub fn available_url(nr: i64, date_compact: &str) -> String {
    format!("{GATEWAY}/grm/grm/available/{nr}/{date_compact}")
}

fn as_u32(v: &Value) -> Option<u32> {
    v.as_u64()
        .and_then(|number| u32::try_from(number).ok())
        .or_else(|| v.as_str().and_then(|s| s.trim().parse().ok()))
}

fn as_i64(v: &Value) -> Option<i64> {
    v.as_i64()
        .or_else(|| v.as_str().and_then(|s| s.trim().parse().ok()))
}

fn read_string(v: &Value, key: &str) -> String {
    v.get(key).and_then(Value::as_str).unwrap_or("").to_string()
}

pub fn parse_connections(v: &Value) -> Result<Vec<Train>> {
    let conns = v
        .get("polaczenia")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::Parse("brak pola `polaczenia`".into()))?;
    let mut out = Vec::new();
    for (i, c) in conns.iter().enumerate() {
        let Some(t) = c
            .get("pociagi")
            .and_then(Value::as_array)
            .and_then(|a| a.first())
        else {
            continue;
        };
        out.push(Train {
            connection_id: c
                .get("idPolaczenia")
                .and_then(as_i64)
                .unwrap_or(i as i64 + 1),
            number: t.get("nrPociagu").and_then(as_i64).unwrap_or(0),
            category: read_string(t, "kategoriaPociagu"),
            name: read_string(t, "nazwaPociagu"),
            dep: read_string(t, "dataWyjazdu"),
            arr: read_string(t, "dataPrzyjazdu"),
            from_kod: t.get("stacjaWyjazdu").and_then(as_u32).unwrap_or(0),
            to_kod: t.get("stacjaPrzyjazdu").and_then(as_u32).unwrap_or(0),
        });
    }
    Ok(out)
}

fn messages(v: Option<&Value>) -> String {
    let Some(arr) = v.and_then(Value::as_array) else {
        return String::new();
    };
    arr.iter()
        .filter_map(|m| match m {
            Value::String(t) => Some(t.trim().to_string()),
            Value::Object(o) => ["tekst", "opis", "tresc", "komunikat", "message", "text"]
                .iter()
                .find_map(|k| o.get(*k).and_then(Value::as_str))
                .map(|t| t.trim().to_string())
                .or_else(|| o.values().find_map(Value::as_str).map(str::to_string)),
            _ => None,
        })
        .filter(|t| !t.is_empty())
        .collect::<Vec<_>>()
        .join(" | ")
}

pub fn parse_route(v: &Value) -> Result<Vec<Stop>> {
    let arr = v
        .pointer("/trasePrzejezdu/trasaPrzejazdu")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::Parse("brak `trasePrzejezdu.trasaPrzejazdu`".into()))?;
    Ok(arr
        .iter()
        .map(|st| Stop {
            name: read_string(st, "nazwaStacji"),
            eva: st.get("stacja").and_then(as_u32).unwrap_or(0),
            arr: read_string(st, "dataPrzyjazdu"),
            dep: read_string(st, "dataWyjazdu"),
            can_board: st
                .get("dozwoloneWsiadanie")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            can_alight: st
                .get("dozwoloneWysiadanie")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            platform: read_string(st, "peron"),
            track: read_string(st, "tor"),
            arr_actual: read_string(st, "dataPrzyjazduRzeczywista"),
            dep_actual: read_string(st, "dataWyjazduRzeczywista"),
            messages: messages(st.get("komunikaty")),
        })
        .collect())
}

pub fn extract_price(v: &Value, class: i64) -> Option<f64> {
    for cp in v.get("cenyPolaczen")?.as_array()? {
        for c in cp.get("ceny")?.as_array()? {
            if c.get("klasa").and_then(Value::as_i64) == Some(class) {
                return Some(c.get("cena").and_then(Value::as_f64).unwrap_or(0.0) / 100.0);
            }
        }
    }
    None
}

pub fn price_for_class(v: &Value, class: i64) -> Result<f64> {
    let mut message: Option<String> = None;
    let cennik = v
        .get("cenyPolaczen")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::Parse("brak `cenyPolaczen`".into()))?;
    for cp in cennik {
        for c in cp
            .get("ceny")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            if c.get("klasa").and_then(Value::as_i64) != Some(class) {
                continue;
            }
            let cena = c.get("cena").and_then(Value::as_f64).unwrap_or(0.0);
            let code = c.get("komunikatKod").and_then(Value::as_i64).unwrap_or(0);
            if cena > 0.0 && code == 0 {
                return Ok(cena / 100.0);
            }
            let text = c
                .get("komunikatTekst")
                .and_then(Value::as_str)
                .unwrap_or("")
                .trim();
            if !text.is_empty() {
                message.get_or_insert_with(|| text.to_string());
            }
        }
    }
    Err(Error::NotFound(match message {
        Some(m) => format!("klasa {class}: {m}"),
        None => format!("brak ceny klasy {class}"),
    }))
}

#[derive(Debug, PartialEq)]
pub struct Sklad {
    pub wagons: Vec<i64>,
    pub schema: std::collections::HashMap<i64, String>,
    pub class1: Vec<i64>,
    pub class2: Vec<i64>,
}

pub fn parse_sklad(v: &Value) -> Option<Sklad> {
    let nums = |k: &str| -> Vec<i64> {
        v.get(k)
            .and_then(Value::as_array)
            .map(|a| a.iter().filter_map(as_i64).collect())
            .unwrap_or_default()
    };
    let wagons = v
        .get("wagony")?
        .as_array()?
        .iter()
        .filter_map(as_i64)
        .collect();
    let schema = v
        .get("wagonySchemat")
        .and_then(Value::as_object)
        .map(|m| {
            m.iter()
                .filter_map(|(k, val)| {
                    let id = k.parse::<i64>().ok()?;
                    let sv = val
                        .as_str()
                        .map(str::to_string)
                        .or_else(|| val.as_i64().map(|n| n.to_string()))?;
                    Some((id, sv))
                })
                .collect()
        })
        .unwrap_or_default();
    Some(Sklad {
        wagons,
        schema,
        class1: nums("klasa1"),
        class2: nums("klasa2"),
    })
}

fn endpoint(service: &str) -> String {
    format!("{GATEWAY}/server/public/endpoint/{service}")
}

pub fn fetch_stations(transport: &dyn Transport) -> Result<Value> {
    let v = fetch_json(
        transport,
        "POST",
        &endpoint("Aktualizacja"),
        Some(&stations_payload()),
    )?;
    if v.get("stacje").is_none() {
        return Err(Error::Parse("brak pola `stacje`".into()));
    }
    Ok(v)
}

pub fn search_connections(
    transport: &dyn Transport,
    date: &str,
    from_kod: u32,
    to_kod: u32,
) -> Result<Vec<Train>> {
    if dates::iso_to_compact(&format!("{date} 00:00:00")).is_none() {
        return Err(Error::Arg(format!(
            "data `{date}`, wymagany format YYYY-MM-DD"
        )));
    }
    let v = fetch_json(
        transport,
        "POST",
        &endpoint("Pociagi"),
        Some(&search_payload(date, from_kod, to_kod)),
    )?;
    parse_connections(&v)
}

pub fn train_route(
    transport: &dyn Transport,
    train: &Train,
    from_eva: u32,
    to_eva: u32,
) -> Result<Vec<Stop>> {
    let v = fetch_json(
        transport,
        "POST",
        &endpoint("Pociagi"),
        Some(&route_payload(train, from_eva, to_eva)),
    )?;
    parse_route(&v)
}

pub fn ticket_price(
    transport: &dyn Transport,
    train: &Train,
    class: i64,
    discount_code: i32,
) -> Result<f64> {
    let v = fetch_json(
        transport,
        "POST",
        &endpoint("Sprzedaz"),
        Some(&price_payload(train, discount_code)),
    )?;
    price_for_class(&v, class)
}

pub fn grm_available(transport: &dyn Transport, nr: i64, date_compact: &str) -> Result<bool> {
    let v = fetch_json(transport, "GET", &available_url(nr, date_compact), None)?;
    Ok(v.get("available").and_then(Value::as_bool).unwrap_or(false))
}

pub struct SegmentQuery<'a> {
    pub category: &'a str,
    pub train_nr: i64,
    pub from_epa: u32,
    pub to_epa: u32,
    pub dep: &'a str,
    pub arr: &'a str,
    pub class: Option<u8>,
    pub exclude_special: bool,
    pub delay: Duration,
    pub concurrency: usize,
}

struct Pacer {
    next: Mutex<Instant>,
    gap: Duration,
}

impl Pacer {
    fn new(gap: Duration) -> Self {
        Pacer {
            next: Mutex::new(Instant::now()),
            gap,
        }
    }

    fn wait(&self) {
        if self.gap.is_zero() {
            return;
        }
        let slot = {
            let mut n = self.next.lock().unwrap_or_else(|e| e.into_inner());
            let start = (*n).max(Instant::now());
            *n = start + self.gap;
            start
        };
        let now = Instant::now();
        if slot > now {
            sleep(slot - now);
        }
    }
}

struct WagonJob {
    wagon: i64,
    schema: String,
    default_class: u8,
}

fn fetch_wagon(
    transport: &dyn Transport,
    query: &SegmentQuery,
    job: &WagonJob,
    pacer: &Pacer,
    warn: &Mutex<Vec<String>>,
) -> Result<Vec<WagonSeats>> {
    let note = |m: String| warn.lock().unwrap_or_else(|e| e.into_inner()).push(m);
    let url = wagon_svg_url(
        query.category,
        query.train_nr,
        job.wagon,
        &job.schema,
        query.from_epa,
        query.to_epa,
        query.dep,
        query.arr,
    );
    let mut attempt = 0;
    let svg = loop {
        pacer.wait();
        match fetch_text(transport, "GET", &url, None) {
            Ok(svg) => break svg,
            Err(e @ Error::Blocked(_)) => return Err(e),
            Err(Error::Transport(m)) if attempt == 0 => {
                note(format!("wagon {}: błąd sieci ({m}), ponawiam", job.wagon));
                attempt += 1;
                sleep(Duration::from_millis(1500));
            }
            Err(e) => {
                note(format!("wagon {} pominięty: {e}", job.wagon));
                return Ok(Vec::new());
            }
        }
    };
    if svg.is_empty() {
        note(format!("wagon {}: pusty schemat SVG", job.wagon));
        return Ok(Vec::new());
    }
    let mut rows = match parse_wagon_svg(&svg, job.default_class, query.exclude_special) {
        Ok(r) => r,
        Err(e) => {
            note(format!("wagon {}: {e}", job.wagon));
            return Ok(Vec::new());
        }
    };
    if rows.is_empty() {
        note(format!("wagon {}: w schemacie brak miejsc", job.wagon));
    }
    rows.retain(|ws| !query.class.is_some_and(|c| c != ws.class));
    for ws in &mut rows {
        ws.wagon = job.wagon as i32;
    }
    Ok(rows)
}

pub struct SegmentSeats {
    pub rows: Vec<WagonSeats>,
    pub warnings: Vec<String>,
}

pub fn seats_for_segment(
    transport: &dyn Transport,
    query: &SegmentQuery,
) -> Result<Vec<WagonSeats>> {
    seats_for_segment_ex(transport, query).map(|r| r.rows)
}

pub fn seats_for_segment_ex(
    transport: &dyn Transport,
    query: &SegmentQuery,
) -> Result<SegmentSeats> {
    let warnings: Mutex<Vec<String>> = Mutex::new(Vec::new());
    let note = |m: String| warnings.lock().unwrap_or_else(|e| e.into_inner()).push(m);
    let url = sklad_url(
        query.category,
        query.train_nr,
        query.from_epa,
        query.to_epa,
        query.dep,
        query.arr,
    );
    let sklad = match fetch_json(transport, "GET", &url, None) {
        Ok(v) => match parse_sklad(&v) {
            Some(s) => s,
            None => {
                note("skład: odpowiedź bez pola `wagony`".into());
                return Ok(SegmentSeats {
                    rows: Vec::new(),
                    warnings: warnings.into_inner().unwrap_or_default(),
                });
            }
        },
        Err(e @ Error::Blocked(_)) => return Err(e),
        Err(e) => {
            note(format!("skład niedostępny: {e}"));
            return Ok(SegmentSeats {
                rows: Vec::new(),
                warnings: warnings.into_inner().unwrap_or_default(),
            });
        }
    };
    if sklad.wagons.is_empty() {
        note("skład: pusta lista wagonów".into());
    }

    let jobs: Vec<WagonJob> = sklad
        .wagons
        .iter()
        .filter_map(|&w| {
            let Some(schema) = sklad.schema.get(&w).cloned() else {
                note(format!("wagon {w}: brak schematu graficznego"));
                return None;
            };
            let in1 = sklad.class1.contains(&w);
            let in2 = sklad.class2.contains(&w);
            if query.class == Some(1) && !in1 || query.class == Some(2) && !in2 {
                return None;
            }
            Some(WagonJob {
                wagon: w,
                schema,
                default_class: if in1 && !in2 { 1 } else { 2 },
            })
        })
        .collect();

    let pacer = Pacer::new(query.delay);
    let results: Vec<Mutex<Option<Result<Vec<WagonSeats>>>>> =
        jobs.iter().map(|_| Mutex::new(None)).collect();
    let next = AtomicUsize::new(0);
    let abort = AtomicBool::new(false);
    let workers = query.concurrency.clamp(1, 8).min(jobs.len().max(1));

    let work = || loop {
        let i = next.fetch_add(1, Ordering::SeqCst);
        if i >= jobs.len() || abort.load(Ordering::SeqCst) {
            break;
        }
        let r = fetch_wagon(transport, query, &jobs[i], &pacer, &warnings);
        if matches!(r, Err(Error::Blocked(_))) {
            abort.store(true, Ordering::SeqCst);
        }
        *results[i].lock().unwrap_or_else(|e| e.into_inner()) = Some(r);
    };
    if workers <= 1 {
        work();
    } else {
        std::thread::scope(|sc| {
            for _ in 0..workers {
                sc.spawn(&work);
            }
        });
    }

    let mut rows = Vec::new();
    for slot in results {
        match slot.into_inner().unwrap_or_else(|e| e.into_inner()) {
            Some(Ok(mut r)) => rows.append(&mut r),
            Some(Err(e)) => return Err(e),
            None => {}
        }
    }
    Ok(SegmentSeats {
        rows,
        warnings: warnings.into_inner().unwrap_or_default(),
    })
}
