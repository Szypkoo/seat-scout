fn digits(s: &str) -> String {
    s.chars().filter(|c| c.is_ascii_digit()).collect()
}

pub fn iso_to_compact(s: &str) -> Option<String> {
    let b = s.as_bytes();
    if b.len() >= 16
        && b[4] == b'-'
        && b[7] == b'-'
        && (b[10] == b' ' || b[10] == b'T')
        && b[13] == b':'
    {
        let d = digits(s.get(..16)?);
        if d.len() == 12 {
            return Some(d);
        }
    }
    None
}

pub fn java_to_compact(s: &str) -> Option<String> {
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    let parts: Vec<&str> = s.split_whitespace().collect();
    if parts.len() < 6 {
        return None;
    }
    let mon = MONTHS.iter().position(|m| *m == parts[1])? + 1;
    let day: u32 = parts[2].parse().ok()?;
    let hm = parts[3].get(..5)?;
    let (h, m) = hm.split_once(':')?;
    let (h, m): (u32, u32) = (h.parse().ok()?, m.parse().ok()?);
    let year: u32 = parts[5].parse().ok()?;
    Some(format!("{year:04}{mon:02}{day:02}{h:02}{m:02}"))
}

pub fn compact_to_minutes(c: &str) -> Option<i64> {
    if c.len() != 12 || !c.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let n = |r: std::ops::Range<usize>| c[r].parse::<i64>().ok();
    let (y, mo, d, h, mi) = (n(0..4)?, n(4..6)?, n(6..8)?, n(8..10)?, n(10..12)?);
    if !(1..=12).contains(&mo) || !(1..=31).contains(&d) || h > 23 || mi > 59 {
        return None;
    }
    let y = if mo <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (if mo > 2 { mo - 3 } else { mo + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146097 + doe - 719468;
    Some(days * 1440 + h * 60 + mi)
}

pub fn to_minutes(s: &str) -> Option<i64> {
    to_compact(s).and_then(|c| compact_to_minutes(&c))
}

pub fn to_compact(s: &str) -> Option<String> {
    iso_to_compact(s).or_else(|| java_to_compact(s))
}

pub fn hhmm(s: &str) -> String {
    let b = s.as_bytes();
    for i in 0..b.len().saturating_sub(4) {
        if b[i].is_ascii_digit()
            && b[i + 1].is_ascii_digit()
            && b[i + 2] == b':'
            && b[i + 3].is_ascii_digit()
            && b[i + 4].is_ascii_digit()
        {
            return s[i..i + 5].to_string();
        }
    }
    String::new()
}

pub fn date_compact(date: &str) -> String {
    date.replace('-', "")
}
