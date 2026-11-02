use crate::error::{Error, Result};
use crate::model::{Stop, Train};
use serde_json::{json, Value};

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
