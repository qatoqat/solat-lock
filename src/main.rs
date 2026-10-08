//! solat-lock: syncs JAKIM (e-solat.gov.my) prayer times into the KDE lock
//! screen wallpaper plugin `solat.lockscreen`.
//!
//! The zone is chosen in System Settings → Screen Locking → Appearance and is
//! stored in kscreenlockerrc. This tool reads it, downloads the timetable, and
//! writes it back into the same config group as `PrayerData`. The lock screen
//! greeter is sandboxed with no network access, so it can only show times that
//! were downloaded ahead of time.

mod remind;

use std::process::{Command, ExitCode};

use chrono::{Datelike, Local, NaiveDate, NaiveTime, TimeDelta};
use serde::{Deserialize, Serialize};

const PLUGIN: &str = "solat.lockscreen";
const DEFAULT_ZONE: &str = "PRK02";
const API: &str = "https://www.e-solat.gov.my/index.php?r=esolatApi/TakwimSolat&period=duration&zone=";
/// How many days ahead to download.
const FETCH_AHEAD: i64 = 60;
/// Refetch once fewer than this many days remain cached.
const MIN_AHEAD: i64 = 14;

const NAMES: [&str; 7] = ["Imsak", "Subuh", "Syuruk", "Zohor", "Asar", "Maghrib", "Isyak"];

#[derive(Serialize, Deserialize)]
struct Store {
    zone: String,
    fetched: String,
    days: Vec<Day>,
}

#[derive(Serialize, Deserialize)]
struct Day {
    /// Gregorian date, YYYY-MM-DD.
    d: String,
    /// Hijri date, YYYY-MM-DD.
    h: String,
    /// imsak, fajr, syuruk, dhuhr, asr, maghrib, isha as HH:MM.
    t: [String; 7],
}

#[derive(Deserialize)]
struct ApiResponse {
    #[serde(rename = "prayerTime")]
    prayer_time: Option<Vec<ApiDay>>,
    status: Option<String>,
}

#[derive(Deserialize)]
struct ApiDay {
    hijri: String,
    date: String,
    imsak: String,
    fajr: String,
    syuruk: String,
    dhuhr: String,
    asr: String,
    maghrib: String,
    isha: String,
}

type Result<T> = std::result::Result<T, String>;

fn cfg_args(key: &str) -> Vec<&str> {
    vec![
        "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper",
        "--group", PLUGIN, "--group", "General", "--key", key,
    ]
}

fn read_cfg(key: &str) -> Option<String> {
    let out = Command::new("kreadconfig6").args(cfg_args(key)).output().ok()?;
    let s = String::from_utf8(out.stdout).ok()?.trim().to_string();
    (!s.is_empty()).then_some(s)
}

fn write_cfg(key: &str, value: &str) -> Result<()> {
    let status = Command::new("kwriteconfig6")
        .args(cfg_args(key))
        .arg(value)
        .status()
        .map_err(|e| format!("running kwriteconfig6: {e}"))?;
    status.success().then_some(()).ok_or_else(|| format!("kwriteconfig6 failed: {status}"))
}

fn valid_zone(z: &str) -> bool {
    z.len() == 5 && z[..3].bytes().all(|b| b.is_ascii_uppercase()) && z[3..].bytes().all(|b| b.is_ascii_digit())
}

fn current_zone() -> String {
    read_cfg("Zone").filter(|z| valid_zone(z)).unwrap_or_else(|| DEFAULT_ZONE.to_string())
}

fn load_store() -> Option<Store> {
    serde_json::from_str(&read_cfg("PrayerData")?).ok()
}

/// "08-Okt-2026" (Malay or English month abbreviations) → 2026-10-08.
fn parse_api_date(s: &str) -> Result<NaiveDate> {
    let mut it = s.split('-');
    let (Some(d), Some(m), Some(y)) = (it.next(), it.next(), it.next()) else {
        return Err(format!("bad date {s:?}"));
    };
    let month = match m.to_ascii_lowercase().as_str() {
        "jan" => 1, "feb" => 2, "mac" | "mar" => 3, "apr" => 4, "mei" | "may" => 5, "jun" => 6,
        "jul" => 7, "ogos" | "ogo" | "aug" => 8, "sep" => 9, "okt" | "oct" => 10, "nov" => 11,
        "dis" | "dec" => 12,
        _ => return Err(format!("unknown month in {s:?}")),
    };
    let parse = |v: &str| v.parse::<i32>().map_err(|_| format!("bad date {s:?}"));
    NaiveDate::from_ymd_opt(parse(y)?, month, parse(d)? as u32).ok_or_else(|| format!("bad date {s:?}"))
}

/// "05:42:00" → "05:42".
fn hhmm(s: &str) -> String {
    s.get(..5).unwrap_or(s).to_string()
}

fn fetch_range(zone: &str, start: NaiveDate, end: NaiveDate) -> Result<Vec<Day>> {
    let resp = ureq::post(&format!("{API}{zone}"))
        .timeout(std::time::Duration::from_secs(30))
        .send_form(&[
            ("datestart", &start.format("%Y-%m-%d").to_string()),
            ("dateend", &end.format("%Y-%m-%d").to_string()),
        ])
        .map_err(|e| format!("request failed: {e}"))?
        .into_string()
        .map_err(|e| format!("reading response: {e}"))?;
    let parsed: ApiResponse =
        serde_json::from_str(&resp).map_err(|e| format!("unexpected response ({e}): {:.200}", resp))?;
    let days = parsed
        .prayer_time
        .filter(|v| !v.is_empty())
        .ok_or_else(|| format!("no prayer times returned (status: {})", parsed.status.unwrap_or_default()))?;
    days.into_iter()
        .map(|a| {
            Ok(Day {
                d: parse_api_date(&a.date)?.format("%Y-%m-%d").to_string(),
                h: a.hijri,
                t: [&a.imsak, &a.fajr, &a.syuruk, &a.dhuhr, &a.asr, &a.maghrib, &a.isha].map(|s| hhmm(s)),
            })
        })
        .collect()
}

/// The API rejects ranges that cross a year boundary, so split per year.
fn fetch(zone: &str, start: NaiveDate, end: NaiveDate) -> Result<Vec<Day>> {
    let mut days = Vec::new();
    let mut from = start;
    while from <= end {
        let year_end = NaiveDate::from_ymd_opt(from.year(), 12, 31).unwrap();
        let to = end.min(year_end);
        days.extend(fetch_range(zone, from, to)?);
        from = to + TimeDelta::days(1);
    }
    Ok(days)
}

fn covers(store: &Store, zone: &str, today: NaiveDate) -> bool {
    let fmt = |d: NaiveDate| d.format("%Y-%m-%d").to_string();
    let (first, last) = match (store.days.first(), store.days.last()) {
        (Some(f), Some(l)) => (&f.d, &l.d),
        _ => return false,
    };
    store.zone == zone && *first <= fmt(today) && *last >= fmt(today + TimeDelta::days(MIN_AHEAD))
}

fn sync(mut force: bool) -> Result<()> {
    // Loop because the zone may be changed in System Settings while a download
    // is in flight; systemd won't re-trigger a service that is still running.
    loop {
        let zone = current_zone();
        let today = Local::now().date_naive();
        if !force && load_store().is_some_and(|s| covers(&s, &zone, today)) {
            println!("{zone}: cached data is up to date");
            return Ok(());
        }
        force = false;
        let days = fetch(&zone, today - TimeDelta::days(1), today + TimeDelta::days(FETCH_AHEAD))?;
        let store = Store { zone: zone.clone(), fetched: Local::now().format("%Y-%m-%d %H:%M").to_string(), days };
        write_cfg("PrayerData", &serde_json::to_string(&store).unwrap())?;
        println!(
            "{zone}: saved {} days ({} → {})",
            store.days.len(),
            store.days.first().map_or("", |d| &d.d),
            store.days.last().map_or("", |d| &d.d)
        );
    }
}

fn show() -> Result<()> {
    let store = load_store().ok_or("no cached data yet, run `solat-lock sync` first")?;
    let now = Local::now();
    let today = now.format("%Y-%m-%d").to_string();
    let day = store.days.iter().find(|d| d.d == today).ok_or("today is not in the cache, run `solat-lock sync`")?;
    println!("Zone {}  ·  {}  ·  Hijri {}  (fetched {})", store.zone, day.d, day.h, store.fetched);
    let now_t = now.time();
    let done = remind::done_on(now.date_naive());
    let mut marked = false;
    for (i, (name, t)) in NAMES.iter().zip(&day.t).enumerate() {
        let upcoming = !marked && *name != "Imsak" && NaiveTime::parse_from_str(t, "%H:%M").is_ok_and(|t| t > now_t);
        marked |= upcoming;
        let check = if done.contains(&i) { "✓" } else { "" };
        println!("{} {name:<8} {t}  {check}", if upcoming { "→" } else { " " });
    }
    Ok(())
}

fn set_zone(zone: &str) -> Result<()> {
    let zone = zone.to_ascii_uppercase();
    if !valid_zone(&zone) {
        return Err(format!("{zone:?} is not a JAKIM zone code (e.g. PRK02, WLY01)"));
    }
    write_cfg("Zone", &zone)?;
    sync(false)
}

fn run(cmd: &str, args: &[&str]) -> Result<()> {
    let status = Command::new(cmd).args(args).status().map_err(|e| format!("running {cmd}: {e}"))?;
    status.success().then_some(()).ok_or_else(|| format!("{cmd} {} failed: {status}", args.join(" ")))
}

/// Per-user setup after installing: enables the services and switches the
/// lock screen to the plugin.
fn setup() -> Result<()> {
    run("systemctl", &["--user", "daemon-reload"])?;
    run(
        "systemctl",
        &["--user", "enable", "--now", "solat-lock.timer", "solat-lock.path", "solat-lock-notify.service"],
    )?;
    run("kwriteconfig6", &["--file", "kscreenlockerrc", "--group", "Greeter", "--key", "WallpaperPlugin", PLUGIN])?;
    sync(false)?;
    println!("Done. Pick your zone in System Settings → Screen Locking → Configure Appearance…");
    Ok(())
}

fn mark(i: usize, done: bool) -> Result<()> {
    remind::set_done(Local::now().date_naive(), i, done)?;
    println!("{} {}", NAMES[i], if done { "✓" } else { "unmarked" });
    Ok(())
}

const USAGE: &str = "\
usage: solat-lock [command]

  setup            enable the user services and use the plugin on the lock screen
  sync [--force]   download prayer times for the configured zone (default)
  show             print today's cached prayer times
  zone [CODE]      print or set the zone (also settable in System Settings)
  done [PRAYER]    mark a prayer done today (default: the current one)
  undo PRAYER      unmark a prayer for today
  daemon           send prayer-time notifications (run by systemd)";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let result = match args.as_slice() {
        [] | ["sync"] => sync(false),
        ["sync", "--force"] | ["--force"] => sync(true),
        ["show"] => show(),
        ["zone"] => Ok(println!("{}", current_zone())),
        ["zone", z] => set_zone(z),
        ["done"] => remind::latest_prayer(Local::now()).and_then(|i| mark(i, true)),
        ["done", p] => remind::prayer_index(p).and_then(|i| mark(i, true)),
        ["undo", p] => remind::prayer_index(p).and_then(|i| mark(i, false)),
        ["daemon"] => remind::daemon(),
        ["setup"] => setup(),
        _ => {
            eprintln!("{USAGE}");
            return ExitCode::from(2);
        }
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("solat-lock: {e}");
            ExitCode::FAILURE
        }
    }
}
