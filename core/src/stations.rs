use crate::error::{Error, Result};
use crate::text::station_key;
use serde_json::Value;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[derive(Debug, Clone, PartialEq)]
pub struct StationRecord {
    pub kod: u32,
    pub epa: u32,
    pub eva: u32,
    pub lat: f32,
    pub lon: f32,
    pub name: String,
}

const HDR: usize = 24;
const ENT: usize = 32;

fn num(v: &Value) -> u32 {
    v.as_u64()
        .and_then(|number| u32::try_from(number).ok())
        .or_else(|| v.as_str().and_then(|s| s.trim().parse().ok()))
        .unwrap_or(0)
}

pub fn records_from_json(v: &Value) -> Result<Vec<StationRecord>> {
    let arr = v
        .get("stacje")
        .and_then(Value::as_array)
        .ok_or_else(|| Error::Parse("brak pola `stacje`".into()))?;
    Ok(arr
        .iter()
        .filter_map(|s| {
            let name = s.get("nazwa")?.as_str()?.trim().to_string();
            if name.is_empty() {
                return None;
            }
            Some(StationRecord {
                kod: num(s.get("kod").unwrap_or(&Value::Null)),
                epa: num(s.get("kodEPA").unwrap_or(&Value::Null)),
                eva: num(s.get("kodEVA").unwrap_or(&Value::Null)),
                lat: s.get("szerokoscGeo").and_then(Value::as_f64).unwrap_or(0.0) as f32,
                lon: s.get("dlugoscGeo").and_then(Value::as_f64).unwrap_or(0.0) as f32,
                name,
            })
        })
        .collect())
}

pub fn pack(records: &[StationRecord]) -> Vec<u8> {
    let mut items: Vec<(String, &StationRecord)> =
        records.iter().map(|r| (station_key(&r.name), r)).collect();
    items.retain(|(k, _)| !k.is_empty());
    items.sort_by(|a, b| {
        a.0.as_bytes()
            .cmp(b.0.as_bytes())
            .then_with(|| a.1.name.cmp(&b.1.name))
    });

    let mut pool: Vec<u8> = Vec::new();
    let mut table: Vec<u8> = Vec::with_capacity(items.len() * ENT);
    let add = |pool: &mut Vec<u8>, s: &str| -> u32 {
        let off = pool.len() as u32;
        pool.extend(s.bytes().filter(|b| *b != 0));
        pool.push(0);
        off
    };
    for (key, r) in &items {
        let ko = add(&mut pool, key);
        let no = add(&mut pool, &r.name);
        for v in [
            ko,
            no,
            r.kod,
            r.epa,
            r.eva,
            r.lat.to_bits(),
            r.lon.to_bits(),
            0,
        ] {
            table.extend(v.to_le_bytes());
        }
    }

    let table_off = HDR as u32;
    let pool_off = table_off + table.len() as u32;
    let mut out = Vec::with_capacity(HDR + table.len() + pool.len());
    out.extend(b"TCST");
    for v in [
        1u32,
        items.len() as u32,
        table_off,
        pool_off,
        pool.len() as u32,
    ] {
        out.extend(v.to_le_bytes());
    }
    out.extend(table);
    out.extend(pool);
    out
}

#[repr(C)]
#[derive(Clone, Copy)]
struct RawStation {
    kod: u32,
    epa: u32,
    eva: u32,
    lat: f32,
    lon: f32,
    name: *const c_char,
    key: *const c_char,
}

extern "C" {
    fn tc_stations_open(path: *const c_char) -> *mut std::ffi::c_void;
    fn tc_stations_close(s: *mut std::ffi::c_void);
    fn tc_stations_count(s: *const std::ffi::c_void) -> usize;
    fn tc_stations_find(s: *const std::ffi::c_void, q: *const c_char, out: *mut RawStation) -> i32;
    fn tc_stations_suggest(
        s: *const std::ffi::c_void,
        q: *const c_char,
        out: *mut RawStation,
        cap: usize,
    ) -> usize;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MatchKind {
    Exact = 1,
    Prefix = 2,
    Contains = 3,
    Fuzzy = 4,
}

pub struct Stations(*mut std::ffi::c_void);

unsafe impl Send for Stations {}
unsafe impl Sync for Stations {}

impl Stations {
    pub fn open(path: &str) -> Result<Self> {
        let c = CString::new(path).map_err(|_| Error::Arg("ścieżka z NUL".into()))?;
        let p = unsafe { tc_stations_open(c.as_ptr()) };
        if p.is_null() {
            Err(Error::Parse(format!(
                "nie można otworzyć słownika `{path}`"
            )))
        } else {
            Ok(Stations(p))
        }
    }

    pub fn len(&self) -> usize {
        unsafe { tc_stations_count(self.0) }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn find(&self, query: &str) -> Option<(StationRecord, MatchKind)> {
        let q = CString::new(query.split('\0').next()?).ok()?;
        let mut raw = RawStation {
            kod: 0,
            epa: 0,
            eva: 0,
            lat: 0.0,
            lon: 0.0,
            name: std::ptr::null(),
            key: std::ptr::null(),
        };
        let kind = unsafe { tc_stations_find(self.0, q.as_ptr(), &mut raw) };
        let kind = match kind {
            1 => MatchKind::Exact,
            2 => MatchKind::Prefix,
            3 => MatchKind::Contains,
            4 => MatchKind::Fuzzy,
            _ => return None,
        };
        Some((to_record(&raw), kind))
    }

    pub fn suggest(&self, query: &str, limit: usize) -> Vec<StationRecord> {
        let Some(first) = query.split('\0').next() else {
            return vec![];
        };
        let Ok(q) = CString::new(first) else {
            return vec![];
        };
        let cap = limit.min(64);
        let blank = RawStation {
            kod: 0,
            epa: 0,
            eva: 0,
            lat: 0.0,
            lon: 0.0,
            name: std::ptr::null(),
            key: std::ptr::null(),
        };
        let mut buf = vec![blank; cap];
        let n = unsafe { tc_stations_suggest(self.0, q.as_ptr(), buf.as_mut_ptr(), cap) };
        buf[..n].iter().map(to_record).collect()
    }
}

fn to_record(r: &RawStation) -> StationRecord {
    StationRecord {
        kod: r.kod,
        epa: r.epa,
        eva: r.eva,
        lat: r.lat,
        lon: r.lon,
        name: unsafe { CStr::from_ptr(r.name) }
            .to_string_lossy()
            .into_owned(),
    }
}

impl Drop for Stations {
    fn drop(&mut self) {
        unsafe { tc_stations_close(self.0) }
    }
}
