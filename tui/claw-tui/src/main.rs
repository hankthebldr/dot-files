//! claw-tui — Open Claw ratatui front-end.
//!
//! A child binary cannot `source` a profile into the parent login shell, so this
//! binary **renders and selects**; the zsh wrapper **applies**. On exit it prints
//! ONE line to stdout (the contract):
//!   PROFILE\t<key>   → wrapper exports CLAW_ACTIVE_PROFILE + sources the profile
//!   ACTION\t<id>     → wrapper runs `claw <id>` (tunnels, mcp, ai, doctor, …)
//!   NONE             → bare shell (ESC / no selection)
//! The TUI draws to the alternate screen; stdout stays clean for the contract.
//!
//! M1 = welcome dashboard (logo + native two-column readout). M2 = profiles AND
//! actions in one picker. Opt-in via CLAW_TUI=1; the fzf path is the default.

use std::io::{self, IsTerminal, Stdout};
use std::path::PathBuf;
use std::time::Duration;

use anyhow::Result;
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    prelude::*,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Row, Table},
};

mod theme;

#[derive(Clone)]
enum Kind {
    Profile,
    Action,
    Header,
}
#[derive(Clone)]
struct Item {
    label: String,
    key: String,
    kind: Kind,
}
impl Item {
    fn profile(k: &str) -> Self { Item { label: format!("  {}", k), key: k.into(), kind: Kind::Profile } }
    fn action(k: &str, l: &str) -> Self { Item { label: format!("  {}", l), key: k.into(), kind: Kind::Action } }
    fn header(l: &str) -> Self { Item { label: l.into(), key: String::new(), kind: Kind::Header } }
    fn selectable(&self) -> bool { !matches!(self.kind, Kind::Header) }
}

enum Outcome { Profile(String), Action(String), None }
impl Outcome {
    /// The contract line the zsh wrapper parses (kept pure for testing).
    fn line(&self) -> String {
        match self {
            Outcome::Profile(k) => format!("PROFILE\t{}", k),
            Outcome::Action(k) => format!("ACTION\t{}", k),
            Outcome::None => "NONE".to_string(),
        }
    }
    fn emit(&self) { println!("{}", self.line()); }
}

struct App {
    items: Vec<Item>,
    state: ListState,
    readout: Vec<(String, String)>,
    outcome: Outcome,
    quit: bool,
}

impl App {
    fn new() -> Self {
        let items = build_items();
        let mut state = ListState::default();
        state.select(first_selectable(&items));
        App { items, state, readout: gather_readout(), outcome: Outcome::None, quit: false }
    }
    fn step(&mut self, dir: i32) {
        let n = self.items.len();
        if n == 0 { return; }
        let mut i = self.state.selected().unwrap_or(0) as i32;
        for _ in 0..n {
            i = (i + dir).rem_euclid(n as i32);
            if self.items[i as usize].selectable() { break; }
        }
        self.state.select(Some(i as usize));
    }
    fn confirm(&mut self) {
        if let Some(i) = self.state.selected() {
            if let Some(it) = self.items.get(i) {
                self.outcome = match it.kind {
                    Kind::Profile => Outcome::Profile(it.key.clone()),
                    Kind::Action => Outcome::Action(it.key.clone()),
                    Kind::Header => return,
                };
            }
        }
        self.quit = true;
    }
}

fn first_selectable(items: &[Item]) -> Option<usize> {
    items.iter().position(|i| i.selectable())
}

fn build_items() -> Vec<Item> {
    let mut v = vec![Item::header("  profiles")];
    for p in discover_profiles() { v.push(Item::profile(&p)); }
    v.push(Item::header("  actions"));
    for (k, l) in [
        ("doctor", "⚕ doctor       system + profile health"),
        ("ai", "✦ ai           local AI stack (ollama/aichat)"),
        ("tun", "⇄ tunnels      SSH tunnel manager"),
        ("mcp", "◆ mcp          MCP server manager"),
        ("homelab", "⌂ homelab      SSH topology"),
        ("update", "↑ update       full system update"),
    ] {
        v.push(Item::action(k, l));
    }
    v
}

fn discover_profiles() -> Vec<String> {
    let dots = std::env::var("DOTFILES_DIR").map(PathBuf::from)
        .unwrap_or_else(|_| home().join(".dotfiles"));
    let mut v: Vec<String> = std::fs::read_dir(dots.join("shell/profiles"))
        .into_iter().flatten().flatten()
        .filter(|e| e.path().join("common.zsh").exists())
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    v.sort();
    if let Some(p) = v.iter().position(|x| x == "default") { v.swap(0, p); }
    if v.is_empty() { v.push("default".into()); }
    v
}

fn home() -> PathBuf { std::env::var("HOME").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from("/")) }

/// (label, value) pairs. Converges on fastfetch's data — `fastfetch --format
/// json` is the same probe the shell readout uses — rendered natively by a
/// ratatui Table. Falls back to a std probe when fastfetch is absent.
fn gather_readout() -> Vec<(String, String)> {
    if let Some(out) = std::process::Command::new("fastfetch")
        .args(["--format", "json"])
        .output()
        .ok()
        .filter(|o| o.status.success())
    {
        if let Ok(text) = String::from_utf8(out.stdout) {
            let pairs = parse_fastfetch(&text);
            if !pairs.is_empty() {
                return pairs;
            }
        }
    }
    fallback_readout()
}

/// Parse `fastfetch --format json` ([{type, result}, …]) into display pairs.
/// Defensive: result is a string → used directly; an object → a few well-known
/// keys are stitched; otherwise skipped. Kept pure for unit testing.
fn parse_fastfetch(json: &str) -> Vec<(String, String)> {
    const WANT: &[&str] = &["OS", "Host", "Kernel", "Uptime", "CPU", "GPU", "Memory", "Disk", "LocalIp", "Shell"];
    let v: serde_json::Value = match serde_json::from_str(json) {
        Ok(v) => v,
        Err(_) => return vec![],
    };
    let mut out = vec![];
    for item in v.as_array().into_iter().flatten() {
        let ty = item.get("type").and_then(|t| t.as_str()).unwrap_or("");
        if !WANT.contains(&ty) {
            continue;
        }
        let res = match item.get("result") {
            Some(r) => r,
            None => continue,
        };
        let val = match res {
            serde_json::Value::String(s) => s.clone(),
            serde_json::Value::Object(o) => {
                // try common display keys, else join string-ish values
                ["name", "value", "version", "cpu", "pretty"]
                    .iter()
                    .find_map(|k| o.get(*k).and_then(|x| x.as_str()).map(String::from))
                    .unwrap_or_else(|| {
                        o.values()
                            .filter_map(|x| x.as_str())
                            .collect::<Vec<_>>()
                            .join(" ")
                    })
            }
            _ => continue,
        };
        if !val.is_empty() {
            out.push((format!(" {}", ty), val));
        }
    }
    out
}

fn fallback_readout() -> Vec<(String, String)> {
    let os = std::fs::read_to_string("/etc/os-release").ok()
        .and_then(|s| s.lines().find(|l| l.starts_with("PRETTY_NAME="))
            .map(|l| l.trim_start_matches("PRETTY_NAME=").trim_matches('"').to_string()))
        .unwrap_or_else(|| std::env::consts::OS.to_string());
    vec![
        (" OS".into(), os),
        (" Arch".into(), std::env::consts::ARCH.into()),
        (" Host".into(), std::env::var("HOSTNAME").or_else(|_| std::env::var("HOST")).unwrap_or_else(|_| "—".into())),
        (" Shell".into(), std::env::var("SHELL").unwrap_or_default()),
        (" Term".into(), std::env::var("TERM_PROGRAM").or_else(|_| std::env::var("TERM")).unwrap_or_default()),
        (" User".into(), std::env::var("USER").unwrap_or_default()),
    ]
}

fn main() -> Result<()> {
    let arg = std::env::args().nth(1).unwrap_or_else(|| "welcome".into());
    if arg != "welcome" || !std::io::stdout().is_terminal() {
        Outcome::None.emit();
        return Ok(());
    }
    let mut term = setup()?;
    let mut app = App::new();
    let res = run(&mut term, &mut app);
    restore(&mut term)?;
    res?;
    app.outcome.emit();
    Ok(())
}

fn setup() -> Result<Terminal<CrosstermBackend<Stdout>>> {
    enable_raw_mode()?;
    let mut out = io::stdout();
    execute!(out, EnterAlternateScreen)?;
    Ok(Terminal::new(CrosstermBackend::new(out))?)
}
fn restore(term: &mut Terminal<CrosstermBackend<Stdout>>) -> Result<()> {
    disable_raw_mode()?;
    execute!(term.backend_mut(), LeaveAlternateScreen)?;
    term.show_cursor()?;
    Ok(())
}

fn run(term: &mut Terminal<CrosstermBackend<Stdout>>, app: &mut App) -> Result<()> {
    while !app.quit {
        term.draw(|f| ui(f, app))?;
        if event::poll(Duration::from_millis(200))? {
            if let Event::Key(k) = event::read()? {
                if k.kind != KeyEventKind::Press { continue; }
                match k.code {
                    KeyCode::Char('q') | KeyCode::Esc => { app.outcome = Outcome::None; app.quit = true; }
                    KeyCode::Down | KeyCode::Char('j') => app.step(1),
                    KeyCode::Up | KeyCode::Char('k') => app.step(-1),
                    KeyCode::Enter => app.confirm(),
                    _ => {}
                }
            }
        }
    }
    Ok(())
}

fn ui(f: &mut Frame, app: &mut App) {
    let root = Layout::vertical([Constraint::Length(9), Constraint::Min(5), Constraint::Length(1)]).split(f.area());
    let head = Layout::horizontal([Constraint::Length(20), Constraint::Min(30)]).split(root[0]);

    let logo = Paragraph::new(vec![
        Line::from(Span::styled("  ▄▀█ █▀█ █▀▀ █▄░█", theme::key())),
        Line::from(Span::styled("  █▀▀ █░░ ▄▀█ █░█░█", theme::pointer())),
        Line::from(Span::styled("  █▄▄ █▄▄ █▀█ ▀▄▀▄▀", theme::pointer())),
        Line::from(Span::styled("     OPEN CLAW", theme::title())),
    ]);
    f.render_widget(logo, head[0]);

    let rows: Vec<Row> = app.readout.iter().take(8).map(|(k, v)| {
        Row::new(vec![
            Span::styled(k.clone(), theme::key()),
            Span::styled(v.clone(), theme::value()),
        ])
    }).collect();
    let table = Table::new(rows, [Constraint::Length(10), Constraint::Min(10)])
        .block(Block::default().borders(Borders::LEFT).border_style(Style::default().fg(theme::RULE)));
    f.render_widget(table, head[1]);

    let items: Vec<ListItem> = app.items.iter().map(|it| {
        let style = match it.kind {
            Kind::Header => theme::title(),
            Kind::Action => Style::default().fg(theme::ORANGE),
            Kind::Profile => theme::value(),
        };
        ListItem::new(Line::from(Span::styled(it.label.clone(), style)))
    }).collect();
    let list = List::new(items)
        .block(Block::default().borders(Borders::TOP).border_style(Style::default().fg(theme::RULE)))
        .highlight_style(theme::selected())
        .highlight_symbol("❯ ");
    f.render_stateful_widget(list, root[1], &mut app.state);

    let bar = Paragraph::new(Line::from(vec![
        Span::styled("  ↑/↓", theme::pointer()), Span::styled(" navigate  ", theme::value()),
        Span::styled("⏎", theme::pointer()), Span::styled(" select  ", theme::value()),
        Span::styled("esc", theme::pointer()), Span::styled(" bare shell", theme::value()),
    ])).style(Style::default().fg(theme::MUTED));
    f.render_widget(bar, root[2]);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_fastfetch_handles_string_and_object_results() {
        let j = r#"[
            {"type":"OS","result":{"name":"macOS","version":"26.6"}},
            {"type":"Kernel","result":"Darwin 25.6.0"},
            {"type":"CPU","result":{"cpu":"Apple M4 Pro"}},
            {"type":"WiFi","result":{"ssid":"ignored-not-in-want-list"}}
        ]"#;
        let pairs = parse_fastfetch(j);
        assert!(pairs.iter().any(|(k, v)| k == " OS" && v == "macOS"));
        assert!(pairs.iter().any(|(k, v)| k == " Kernel" && v == "Darwin 25.6.0"));
        assert!(pairs.iter().any(|(k, v)| k == " CPU" && v == "Apple M4 Pro"));
        assert!(!pairs.iter().any(|(k, _)| k == " WiFi"));   // not in WANT
    }

    #[test]
    fn parse_fastfetch_bad_json_is_empty() {
        assert!(parse_fastfetch("not json").is_empty());
    }

    #[test]
    fn outcome_contract_format() {
        assert_eq!(Outcome::Profile("security".into()).line(), "PROFILE\tsecurity");
        assert_eq!(Outcome::Action("doctor".into()).line(), "ACTION\tdoctor");
        assert_eq!(Outcome::None.line(), "NONE");
    }

    #[test]
    fn first_selectable_skips_headers() {
        let items = vec![Item::header("h"), Item::profile("default"), Item::action("a", "A")];
        assert_eq!(first_selectable(&items), Some(1)); // skips the header at 0
    }

    #[test]
    fn build_items_has_headers_and_actions() {
        let v = build_items();
        assert!(matches!(v[0].kind, Kind::Header));            // starts with a section header
        assert!(v.iter().any(|i| matches!(i.kind, Kind::Profile)));
        assert!(v.iter().any(|i| matches!(i.kind, Kind::Action) && i.key == "doctor"));
    }

    #[test]
    fn header_not_selectable() {
        assert!(!Item::header("x").selectable());
        assert!(Item::profile("p").selectable());
        assert!(Item::action("a", "l").selectable());
    }
}
