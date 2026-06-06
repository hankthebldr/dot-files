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
    fn emit(&self) {
        match self {
            Outcome::Profile(k) => println!("PROFILE\t{}", k),
            Outcome::Action(k) => println!("ACTION\t{}", k),
            Outcome::None => println!("NONE"),
        }
    }
}

struct App {
    items: Vec<Item>,
    state: ListState,
    readout: Vec<(String, String, String, String)>,
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

fn gather_readout() -> Vec<(String, String, String, String)> {
    let os = std::fs::read_to_string("/etc/os-release").ok()
        .and_then(|s| s.lines().find(|l| l.starts_with("PRETTY_NAME="))
            .map(|l| l.trim_start_matches("PRETTY_NAME=").trim_matches('"').to_string()))
        .unwrap_or_else(|| std::env::consts::OS.to_string());
    let host = std::env::var("HOSTNAME").or_else(|_| std::env::var("HOST")).unwrap_or_else(|_| "—".into());
    let shell = std::env::var("SHELL").unwrap_or_default();
    let term = std::env::var("TERM_PROGRAM").or_else(|_| std::env::var("TERM")).unwrap_or_default();
    let user = std::env::var("USER").unwrap_or_default();
    vec![
        (" OS".into(), os, " Arch".into(), std::env::consts::ARCH.into()),
        (" Host".into(), host, " User".into(), user),
        (" Shell".into(), shell, " Term".into(), term),
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
    let root = Layout::vertical([Constraint::Length(7), Constraint::Min(5), Constraint::Length(1)]).split(f.area());
    let head = Layout::horizontal([Constraint::Length(20), Constraint::Min(30)]).split(root[0]);

    let logo = Paragraph::new(vec![
        Line::from(Span::styled("  ▄▀█ █▀█ █▀▀ █▄░█", theme::key())),
        Line::from(Span::styled("  █▀▀ █░░ ▄▀█ █░█░█", theme::pointer())),
        Line::from(Span::styled("  █▄▄ █▄▄ █▀█ ▀▄▀▄▀", theme::pointer())),
        Line::from(Span::styled("     OPEN CLAW", theme::title())),
    ]);
    f.render_widget(logo, head[0]);

    let rows: Vec<Row> = app.readout.iter().map(|(lk, lv, rk, rv)| {
        Row::new(vec![
            Span::styled(lk.clone(), theme::key()),
            Span::styled(lv.clone(), theme::value()),
            Span::styled("│", Style::default().fg(theme::RULE)),
            Span::styled(rk.clone(), theme::key()),
            Span::styled(rv.clone(), theme::value()),
        ])
    }).collect();
    let table = Table::new(rows, [
        Constraint::Length(8), Constraint::Length(20), Constraint::Length(1),
        Constraint::Length(8), Constraint::Min(8),
    ]).block(Block::default().borders(Borders::LEFT).border_style(Style::default().fg(theme::RULE)));
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
