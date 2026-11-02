fn main() {
    cc::Build::new()
        .files(["c/tc_text.c", "c/tc_stations.c"])
        .include("include")
        .flag_if_supported("-std=c11")
        .define("_POSIX_C_SOURCE", "200809L")
        .compile("station_search");
    println!("cargo:rerun-if-changed=c");
    println!("cargo:rerun-if-changed=include");
}
