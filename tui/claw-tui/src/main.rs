//! claw-tui — Open Claw ratatui front-end.
//!
//! Architecture: a child binary cannot `source` a profile into the parent login
//! shell, so this binary **renders and selects**; the zsh wrapper **applies**.
//! On exit it prints ONE machine-readable line to stdout (the contract):
//!   PROFILE\t<key>     → wrapper: export CLAW_ACTIVE_PROFILE; source profile
//!   ACTION\t<id>       → wrapper: run a known action
//!   NONE               → bare shell (ESC / no selection)
//! The TUI draws to the alternate screen; stdout stays clean for the contract.
//!
//! M1 scope: welcome screen = logo + two-column system readout (alignment solved
//! natively by ratatui's Table) + profile picker. Falls back to the fzf path
//! whenever this binary is absent (the zsh wrapper guards on `command -v`).

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

/// What the user chose — emitted to stdout on exit (the zsh contract).
enum Outcome {
    Profile(String),
    None,
}
impl Outcome {
    fn emit(&self) {
        match self {
            Outcome::Profile(k) => println!("PROFILE\t{}", k),
            Outcome::None => println!("NONE"),
        }
    }
}

struct App {
    profiles: Vec<String>,
    state: ListState,
    readout: Vec<(String, String, String, String)>, // (licon+label, lval, ricon+label, rval)
    outcome: Outcome,
    quit: bool,
}

impl App {
    fn new() -> Self {
        let mut state = ListState::default();
        state.select(Some(0));
        App {
            profiles: discover_profiles(),
            state,
            readout: gather_readout(),
            outcome: Outcome::None,
            quit: false,
        }
    }
    fn next(&mut self) {
        let i = self.state.selected().unwrap_or(0);
        let n = self.profiles.len().max(1);
        self.state.select(Some((i + 1) % n));
    }
    fn prev(&mut self) {
        let i = self.state.selected().unwrap_or(0);
        let n = self.profiles.len().max(1);
        self.state.select(Some((i + n - 1) % n));
    }
    fn confirm(&mut self) {
        if let Some(i) = self.state.selected() {
            if let Some(p) = self.profiles.get(i) {
                self.outcome = Outcome::Profile(p.clone());
            }
        }
        self.quit = true;
    }
}

/// Profiles = subdirs of $DOTFILES_DIR/shell/profiles containing common.zsh.
fn discover_profiles() -> Vec<String> {
    let dots = std::env::var("DOTFILES_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| dirs_home().join(".dotfiles"));
    let dir = dots.join("shell/profiles");
    let mut v: Vec<String> = std::fs::read_dir(&dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.path().join("common.zsh").exists())
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    v.sort();
    // default first if present
    if let Some(p) = v.iter().position(|x| x == "default") {
        v.swap(0, p);
    }
    if v.is_empty() {
        v.push("default".into());
    }
    v
}

fn dirs_home() -> PathBuf {
    std::env::var("HOME").map(PathBuf::from).unwrap_or_else(|_| PathBuf::from("/"))
}

/// Minimal cross-platform readout. (Wave-4 M1+ swaps this for `fastfetch --format
/// json`; the point here is the ratatui Table does the column alignment.)
fn gather_readout() -> Vec<(String, String, String, String)> {
    let os = std::fs::read_to_string("/etc/os-release")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("PRETTY_NAME="))
                .map(|l| l.trim_start_matches("PRETTY_NAME=").trim_matches('"').to_string())
        })
        .unwrap_or_else(|| std::env::consts::OS.to_string());
    let host = std::env::var("HOSTNAME")
        .or_else(|_| std::env::var("HOST"))
        .unwrap_or_else(|_| "—".into());
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
    // Only the welcome screen is implemented; any other arg → NONE (safe default).
    let arg = std::env::args().nth(1).unwrap_or_else(|| "welcome".into());
    if arg != "welcome" {
        Outcome::None.emit();
        return Ok(());
    }
    // Not a TTY (scp/pipe) → never draw; emit NONE and exit (login-safety).
    if !std::io::stdout().is_terminal() {
        Outcome::None.emit();
        return Ok(());
    }

    let mut term = setup()?;
    let mut app = App::new();
    let res = run(&mut term, &mut app);
    restore(&mut term)?;
    res?;
    app.outcome.emit(); // contract printed AFTER the alt screen is torn down
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
                if k.kind != KeyEventKind::Press {
                    continue;
                }
                match k.code {
                    KeyCode::Char('q') | KeyCode::Esc => {
                        app.outcome = Outcome::None;
                        app.quit = true;
                    }
                    KeyCode::Down | KeyCode::Char('j') => app.next(),
                    KeyCode::Up | KeyCode::Char('k') => app.prev(),
                    KeyCode::Enter => app.confirm(),
                    _ => {}
                }
            }
        }
    }
    Ok(())
}

fn ui(f: &mut Frame, app: &mut App) {
    let root = Layout::vertical([
        Constraint::Length(8),  // header: logo + readout
        Constraint::Min(5),     // profile picker
        Constraint::Length(1),  // status bar
    ])
    .split(f.area());

    // ── Header: logo (left) | readout (right) ──
    let head = Layout::horizontal([Constraint::Length(20), Constraint::Min(30)]).split(root[0]);

    let logo = Paragraph::new(vec![
        Line::from(Span::styled("  ▄▀█ █▀█ █▀▀ █▄░█", theme::key())),
        Line::from(Span::styled("  █▄█ █▀▀ ██▄ █░▀█", theme::key())),
        Line::from(Span::styled("  █▀▀ █░░ ▄▀█ █░█░█", theme::pointer())),
        Line::from(Span::styled("  █▄▄ █▄▄ █▀█ ▀▄▀▄▀", theme::pointer())),
        Line::from(Span::styled("     OPEN CLAW", theme::title())),
    ]);
    f.render_widget(logo, head[0]);

    // Two-column readout — ratatui aligns columns natively (the alignment win).
    let rows: Vec<Row> = app
        .readout
        .iter()
        .map(|(lk, lv, rk, rv)| {
            Row::new(vec![
                Span::styled(lk.clone(), theme::key()),
                Span::styled(lv.clone(), theme::value()),
                Span::styled("│", Style::default().fg(theme::RULE)),
                Span::styled(rk.clone(), theme::key()),
                Span::styled(rv.clone(), theme::value()),
            ])
        })
        .collect();
    let table = Table::new(
        rows,
        [
            Constraint::Length(8),
            Constraint::Length(20),
            Constraint::Length(1),
            Constraint::Length(8),
            Constraint::Min(8),
        ],
    )
    .block(Block::default().borders(Borders::LEFT).border_style(Style::default().fg(theme::RULE)));
    f.render_widget(table, head[1]);

    // ── Profile picker ──
    let items: Vec<ListItem> = app
        .profiles
        .iter()
        .map(|p| ListItem::new(Line::from(format!("  {}", p))))
        .collect();
    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::TOP)
                .border_style(Style::default().fg(theme::RULE))
                .title(Span::styled(" profiles ", theme::title())),
        )
        .highlight_style(theme::selected())
        .highlight_symbol("❯ ");
    f.render_stateful_widget(list, root[1], &mut app.state);

    // ── Status bar ──
    let bar = Paragraph::new(Line::from(vec![
        Span::styled("  ↑/↓", theme::pointer()),
        Span::styled(" navigate  ", theme::value()),
        Span::styled("⏎", theme::pointer()),
        Span::styled(" load profile  ", theme::value()),
        Span::styled("esc", theme::pointer()),
        Span::styled(" bare shell", theme::value()),
    ]))
    .style(Style::default().fg(theme::MUTED));
    f.render_widget(bar, root[2]);
}
