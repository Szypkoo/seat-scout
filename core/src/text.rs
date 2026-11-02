use std::ffi::CString;
use std::os::raw::{c_char, c_uint};

extern "C" {
    fn tc_normalize(utf8: *const c_char, out: *mut c_char, cap: usize, flags: c_uint) -> usize;
    fn tc_edit_distance(
        a: *const c_char,
        alen: usize,
        b: *const c_char,
        blen: usize,
        max: usize,
    ) -> usize;
}

pub const NORM_ABBREV: u32 = 1;
pub const NORM_PARTIAL_LAST: u32 = 2;

pub fn normalize(s: &str, flags: u32) -> String {
    let s = s.split('\0').next().unwrap_or("");
    let c = CString::new(s).expect("bez NUL");
    let mut buf = vec![0u8; 512];
    let n = unsafe {
        tc_normalize(
            c.as_ptr(),
            buf.as_mut_ptr() as *mut c_char,
            buf.len(),
            flags,
        )
    };
    buf.truncate(n.min(buf.len() - 1));
    String::from_utf8(buf).unwrap_or_default()
}

pub fn station_key(name: &str) -> String {
    normalize(name, NORM_ABBREV)
}

pub fn edit_distance(a: &str, b: &str, max: usize) -> usize {
    unsafe {
        tc_edit_distance(
            a.as_ptr() as *const c_char,
            a.len(),
            b.as_ptr() as *const c_char,
            b.len(),
            max,
        )
    }
}
