use crate::error::{Error, Result};
use crate::model::{Decor, Layout, Position, Seat, WagonSeats};
use std::collections::BTreeMap;

const SPECIAL_KEYWORDS: [&str; 9] = [
    "wózk",
    "wozk",
    "ozn",
    "niepełn",
    "niepeln",
    "wheelchair",
    "prm",
    "opiekun",
    "inwalid",
];

fn has_keyword(s: &str) -> bool {
    let text = s.to_lowercase();
    SPECIAL_KEYWORDS
        .iter()
        .any(|keyword| text.contains(keyword))
}

fn is_special(g: roxmltree::Node) -> bool {
    if g.attribute("aria-label").map(has_keyword).unwrap_or(false) {
        return true;
    }
    for child in g.children().filter(|c| c.is_element()) {
        let tag = child.tag_name().name().to_lowercase();
        if tag.contains("title") && has_keyword(child.text().unwrap_or("")) {
            return true;
        }
        if tag.contains("special") {
            let text = child.text().unwrap_or("");
            let pl = child.attribute("pl").unwrap_or("");
            let en = child.attribute("en").unwrap_or("");
            if has_keyword(text) || has_keyword(pl) || has_keyword(en) {
                return true;
            }
        }
    }
    false
}

fn number_from_aria(aria: &str) -> Option<u16> {
    let label = aria.to_lowercase();
    let rest = &label[label.find("miejsce")? + "miejsce".len()..];
    if !rest.starts_with(char::is_whitespace) {
        return None;
    }
    let digits: String = rest
        .trim_start()
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect();
    digits.parse().ok()
}

fn seat_number(g: roxmltree::Node, aria: &str) -> Option<u16> {
    let text = g
        .descendants()
        .find(|n| n.is_element() && n.tag_name().name() == "text")
        .and_then(|n| n.text())
        .map(str::trim)
        .unwrap_or("");
    if !text.is_empty() && text.chars().all(|c| c.is_ascii_digit()) {
        return text.parse().ok();
    }
    number_from_aria(aria)
}

fn seat_xy(g: roxmltree::Node) -> Option<(i32, i32)> {
    let pick = |n: roxmltree::Node| -> Option<(i32, i32)> {
        let x: f64 = n.attribute("x")?.parse().ok()?;
        let y: f64 = n.attribute("y")?.parse().ok()?;
        Some((x.round() as i32, y.round() as i32))
    };
    let by_class = |tag: &str, class: &str| {
        g.descendants().find(|n| {
            n.is_element()
                && n.tag_name().name() == tag
                && n.attribute("class")
                    .is_some_and(|c| c.split_whitespace().any(|x| x == class))
        })
    };
    by_class("rect", "place-rect")
        .or_else(|| by_class("image", "place"))
        .and_then(pick)
}

const XLINK: &str = "http://www.w3.org/1999/xlink";

fn parse_layout(doc: &roxmltree::Document) -> Layout {
    let root = doc.root_element();
    let dim = |name: &str| {
        root.attribute(name)
            .and_then(|v| v.trim_end_matches("px").parse::<f64>().ok())
            .map_or(0, |v| v.round() as i32)
    };
    let num = |n: roxmltree::Node, a: &str| {
        n.attribute(a)
            .and_then(|v| v.parse::<f64>().ok())
            .map_or(0, |v| v.round() as i32)
    };
    let mut decor = Vec::new();
    for img in doc
        .descendants()
        .filter(|n| n.is_element() && n.tag_name().name() == "image")
    {
        let kind = match img.attribute("class") {
            Some("sign") => "sign",
            Some("internal") => "internal",
            _ => continue,
        };
        let href = img
            .attribute((XLINK, "href"))
            .or_else(|| img.attribute("href"))
            .unwrap_or("");
        let code = href
            .rsplit('/')
            .next()
            .unwrap_or("")
            .trim_end_matches(".png")
            .to_string();
        let title = img
            .parent()
            .and_then(|g| {
                g.children()
                    .find(|c| c.is_element() && c.tag_name().name() == "title")
            })
            .and_then(|t| t.text())
            .unwrap_or("")
            .trim()
            .to_string();
        decor.push(Decor {
            kind: kind.into(),
            code,
            x: num(img, "x"),
            y: num(img, "y"),
            w: num(img, "width"),
            h: num(img, "height"),
            title,
        });
    }
    Layout {
        width: dim("width"),
        height: dim("height"),
        decor,
    }
}

pub fn parse_wagon_svg(
    svg: &str,
    default_class: u8,
    exclude_special: bool,
) -> Result<Vec<WagonSeats>> {
    let doc = roxmltree::Document::parse(svg).map_err(|e| Error::Parse(format!("SVG: {e}")))?;
    let layout = parse_layout(&doc);
    let mut by_class: BTreeMap<u8, BTreeMap<u16, Seat>> = BTreeMap::new();

    for g in doc
        .descendants()
        .filter(|n| n.is_element() && n.tag_name().name() == "g")
    {
        let aria = g.attribute("aria-label").unwrap_or("");
        let aria_l = aria.to_lowercase();
        if !(aria_l.contains("miejsce") || aria_l.contains("seat")) {
            continue;
        }
        let Some(number) = seat_number(g, aria) else {
            continue;
        };
        let special = is_special(g);
        if exclude_special && special {
            continue;
        }

        let data_class = g.attribute("data-class").unwrap_or("").to_lowercase();
        let class = if aria_l.contains("klasa 1") || data_class.contains("first") {
            1
        } else if aria_l.contains("klasa 2") || data_class.contains("second") {
            2
        } else {
            default_class
        };

        let free = (aria_l.contains("wolne") || aria_l.contains("free"))
            && !aria_l.contains("niedostepne");
        let position = if aria_l.contains("okno") {
            Position::Window
        } else if aria_l.contains("korytarz") {
            Position::Aisle
        } else {
            Position::Unknown
        };

        let entry = by_class.entry(class).or_default();
        let seat = Seat {
            number,
            free,
            position,
            special,
            xy: seat_xy(g),
        };
        entry
            .entry(number)
            .and_modify(|s| {
                if seat.free && !s.free {
                    *s = seat;
                }
            })
            .or_insert(seat);
    }

    Ok(by_class
        .into_iter()
        .filter(|(_, m)| !m.is_empty())
        .map(|(class, m)| WagonSeats {
            class,
            wagon: 0,
            seats: m.into_values().collect(),
            layout: layout.clone(),
        })
        .collect())
}
