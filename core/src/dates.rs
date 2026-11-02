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
    let year = c[0..4].parse::<i64>().ok()?;
    let month = c[4..6].parse::<i64>().ok()?;
    let day = c[6..8].parse::<i64>().ok()?;
    let hour = c[8..10].parse::<i64>().ok()?;
    let minute = c[10..12].parse::<i64>().ok()?;
    if !(1..=12).contains(&month) || !(1..=31).contains(&day) || hour > 23 || minute > 59 {
        return None;
    }
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let day_of_year = (153 * (if month > 2 { month - 3 } else { month + 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    let days = era * 146097 + day_of_era - 719468;
    Some(days * 1440 + hour * 60 + minute)
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
