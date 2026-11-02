use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum Error {
    Arg(String),
    Transport(String),
    Blocked(i32),
    Http(i32),
    Parse(String),
    NotFound(String),
}

pub type Result<T> = std::result::Result<T, Error>;

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Arg(s) => write!(f, "niepoprawny argument: {s}"),
            Error::Transport(s) => write!(f, "błąd transportu: {s}"),
            Error::Blocked(c) => write!(f, "blokada Akamai (HTTP {c})"),
            Error::Http(c) => write!(f, "błąd HTTP {c}"),
            Error::Parse(s) => write!(f, "błąd parsowania: {s}"),
            Error::NotFound(s) => write!(f, "nie znaleziono: {s}"),
        }
    }
}

impl std::error::Error for Error {}
