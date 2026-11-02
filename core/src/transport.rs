use crate::error::{Error, Result};
use std::cell::Cell;

thread_local! {
    static LAST_HTTP_STATUS: Cell<i32> = const { Cell::new(0) };
}

pub fn last_http_status() -> i32 {
    LAST_HTTP_STATUS.with(Cell::get)
}

#[derive(Debug, Clone)]
pub struct HttpResponse {
    pub status: i32,
    pub body: String,
}

pub trait Transport: Sync {
    fn request(&self, method: &str, url: &str, body: Option<&str>) -> Result<HttpResponse>;
}

pub(crate) fn fetch_text(
    t: &dyn Transport,
    method: &str,
    url: &str,
    body: Option<&str>,
) -> Result<String> {
    let resp = t.request(method, url, body)?;
    LAST_HTTP_STATUS.with(|status| status.set(resp.status));
    if resp.status == 403 || resp.status == 429 {
        return Err(Error::Blocked(resp.status));
    }
    let lower = resp.body.to_lowercase();
    if lower.contains("captcha") || (lower.contains("challenge") && resp.status != 200) {
        return Err(Error::Blocked(resp.status));
    }
    if !(200..300).contains(&resp.status) {
        return Err(Error::Http(resp.status));
    }
    Ok(resp.body)
}

pub(crate) fn fetch_json(
    t: &dyn Transport,
    method: &str,
    url: &str,
    body: Option<&serde_json::Value>,
) -> Result<serde_json::Value> {
    let body_s = body.map(|b| b.to_string());
    let text = fetch_text(t, method, url, body_s.as_deref())?;
    serde_json::from_str(&text).map_err(|e| Error::Parse(format!("{url}: {e}")))
}
