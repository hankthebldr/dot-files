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

struct Category {
    name: String,
    items: Vec<Item>,
}

struct App {
    categories: Vec<Category>,
    cat_state: ListState,
    item_state: ListState,
    focus_items: bool,
    readout: Vec<(String, String)>,
    outcome: Outcome,
    quit: bool,
    active_logo: Vec<Line<'static>>,
}

impl App {
    fn new() -> Self {
        let categories = build_categories();
        let mut cat_state = ListState::default();
        cat_state.select(Some(0));
        let mut item_state = ListState::default();
        item_state.select(Some(0));
        let readout = gather_readout();
        
        let mut app = App {
            categories,
            cat_state,
            item_state,
            focus_items: false,
            readout,
            outcome: Outcome::None,
            quit: false,
            active_logo: vec![],
        };
        app.update_logo();
        app
    }

    fn step_category(&mut self, dir: i32) {
        let n = self.categories.len();
        if n == 0 { return; }
        let idx = self.cat_state.selected().unwrap_or(0) as i32;
        let next_idx = (idx + dir).rem_euclid(n as i32) as usize;
        self.cat_state.select(Some(next_idx));
        self.item_state.select(Some(0));
        self.update_logo();
    }

    fn step_item(&mut self, dir: i32) {
        if let Some(cat_idx) = self.cat_state.selected() {
            let n = self.categories[cat_idx].items.len();
            if n == 0 { return; }
            let idx = self.item_state.selected().unwrap_or(0) as i32;
            let next_idx = (idx + dir).rem_euclid(n as i32) as usize;
            self.item_state.select(Some(next_idx));
            self.update_logo();
        }
    }

    fn current_item(&self) -> Option<&Item> {
        let cat_idx = self.cat_state.selected()?;
        let item_idx = self.item_state.selected()?;
        self.categories.get(cat_idx)?.items.get(item_idx)
    }

    fn update_logo(&mut self) {
        if let Some(item) = self.current_item() {
            match item.kind {
                Kind::Profile => {
                    self.active_logo = load_logo(&item.key);
                }
                Kind::Action => {
                    let key = match item.key.as_str() {
                        "ai" => "ai",
                        "tun" | "tunnels" => "tunnels",
                        "homelab" => "homelab",
                        _ => "default",
                    };
                    self.active_logo = load_logo(key);
                }
                _ => {
                    self.active_logo = load_logo("default");
                }
            }
        } else {
            self.active_logo = load_logo("default");
        }
    }

    fn confirm(&mut self) {
        if let Some(it) = self.current_item() {
            self.outcome = match it.kind {
                Kind::Profile => Outcome::Profile(it.key.clone()),
                Kind::Action => Outcome::Action(it.key.clone()),
                Kind::Header => return,
            };
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

fn build_categories() -> Vec<Category> {
    let mut core = Category { name: "⭐ Core Profiles".into(), items: vec![] };
    let mut domain = Category { name: "☁️ Domain Expertise".into(), items: vec![] };
    let mut knowledge = Category { name: "📓 Ideation & Knowledge".into(), items: vec![] };
    let mut visual = Category { name: "🎨 Visual & Customer".into(), items: vec![] };
    let mut hardware = Category { name: "📡 Hardware & Ops".into(), items: vec![] };
    let mut actions = Category { name: "⚡ Direct Actions".into(), items: vec![] };
    let mut system = Category { name: "🛠️ System Tools".into(), items: vec![] };

    let profiles = discover_profiles();
    for p in profiles {
        let it = Item::profile(&p);
        match p.as_str() {
            "default" | "local" | "claude" => core.items.push(it),
            "cloud" | "devops" | "security" | "cortex" | "ai" | "research" => domain.items.push(it),
            "vault" | "brainstorm" | "pmo" => knowledge.items.push(it),
            "deck" | "design" | "demo" => visual.items.push(it),
            "homelab" | "blackwell" | "tunnels" => hardware.items.push(it),
            _ => core.items.push(it),
        }
    }

    actions.items = vec![
        Item::action("doctor", "⚕ doctor       system + active-profile health"),
        Item::action("ai", "✦ ai           local AI stack (ollama/aichat)"),
        Item::action("tun", "⇄ tunnels      SSH tunnel manager"),
        Item::action("mcp", "◆ mcp          MCP server manager"),
        Item::action("homelab", "⌂ homelab      SSH topology"),
        Item::action("update", "↑ update       full system update"),
    ];

    system.items = vec![
        Item::action("onboard", "🕹 onboard      80s arcade profile setup"),
        Item::action("integrity", "🛡 integrity    install/tamper audit"),
        Item::action("tmux", "🪟 tmux         attach/new session"),
        Item::action("yazi", "📂 yazi         TUI file browser"),
        Item::action("doc", "📖 doc          CLI docs & help"),
        Item::action("top", "📊 top          system monitor"),
        Item::action("skip", "↩ skip         exit to bare shell"),
    ];

    vec![core, domain, knowledge, visual, hardware, actions, system]
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

// Dynamically parses lines in logo.txt, replacing templates ($1-$6) and keeping ANSI formatting
fn parse_line(line: &str) -> Line<'static> {
    let mut spans = Vec::new();
    let mut current_text = String::new();
    let mut current_style = Style::default();

    let colors = [
        theme::muted(),
        theme::blue(),
        theme::purple(),
        theme::green(),
        theme::orange(),
        theme::red(),
    ];

    let chars: Vec<char> = line.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        if chars[i] == '$' && i + 1 < chars.len() && chars[i+1].is_digit(10) {
            let digit = chars[i+1].to_digit(10).unwrap() as usize;
            if digit >= 1 && digit <= 6 {
                if !current_text.is_empty() {
                    spans.push(Span::styled(current_text.clone(), current_style));
                    current_text.clear();
                }
                current_style = current_style.fg(colors[digit - 1]);
                i += 2;
                continue;
            }
        }

        if chars[i] == '\x1b' && i + 1 < chars.len() && chars[i+1] == '[' {
            let mut j = i + 2;
            let mut found_m = false;
            while j < chars.len() {
                if chars[j] == 'm' {
                    found_m = true;
                    break;
                }
                j += 1;
            }
            if found_m {
                let seq: String = chars[i+2..j].iter().collect();
                if !current_text.is_empty() {
                    spans.push(Span::styled(current_text.clone(), current_style));
                    current_text.clear();
                }
                current_style = apply_ansi_sequence(current_style, &seq);
                i = j + 1;
                continue;
            }
        }

        current_text.push(chars[i]);
        i += 1;
    }
    if !current_text.is_empty() {
        spans.push(Span::styled(current_text, current_style));
    }
    Line::from(spans)
}

fn apply_ansi_sequence(mut style: Style, seq: &str) -> Style {
    if seq == "0" || seq.is_empty() {
        return Style::default();
    }
    let parts: Vec<&str> = seq.split(';').collect();
    let mut p = 0;
    while p < parts.len() {
        match parts[p] {
            "0" => {
                style = Style::default();
                p += 1;
            }
            "1" => {
                style = style.add_modifier(Modifier::BOLD);
                p += 1;
            }
            "38" => {
                if p + 1 < parts.len() {
                    match parts[p+1] {
                        "2" => {
                            if p + 4 < parts.len() {
                                let r = parts[p+2].parse::<u8>().unwrap_or(0);
                                let g = parts[p+3].parse::<u8>().unwrap_or(0);
                                let b = parts[p+4].parse::<u8>().unwrap_or(0);
                                style = style.fg(Color::Rgb(r, g, b));
                                p += 5;
                            } else {
                                p += 2;
                            }
                        }
                        "5" => {
                            if p + 2 < parts.len() {
                                if let Ok(val) = parts[p+2].parse::<u8>() {
                                    style = style.fg(Color::Indexed(val));
                                }
                                p += 3;
                            } else {
                                p += 2;
                            }
                        }
                        _ => p += 2,
                    }
                } else {
                    p += 1;
                }
            }
            "48" => {
                if p + 1 < parts.len() {
                    match parts[p+1] {
                        "2" => {
                            if p + 4 < parts.len() {
                                let r = parts[p+2].parse::<u8>().unwrap_or(0);
                                let g = parts[p+3].parse::<u8>().unwrap_or(0);
                                let b = parts[p+4].parse::<u8>().unwrap_or(0);
                                style = style.bg(Color::Rgb(r, g, b));
                                p += 5;
                            } else {
                                p += 2;
                            }
                        }
                        "5" => {
                            if p + 2 < parts.len() {
                                if let Ok(val) = parts[p+2].parse::<u8>() {
                                    style = style.bg(Color::Indexed(val));
                                }
                                p += 3;
                            } else {
                                p += 2;
                            }
                        }
                        _ => p += 2,
                    }
                } else {
                    p += 1;
                }
            }
            s => {
                if let Ok(code) = s.parse::<u8>() {
                    match code {
                        30..=37 => style = style.fg(ansi_std_color(code - 30)),
                        40..=47 => style = style.bg(ansi_std_color(code - 40)),
                        90..=97 => style = style.fg(ansi_bright_color(code - 90)),
                        100..=107 => style = style.bg(ansi_bright_color(code - 100)),
                        _ => {}
                    }
                }
                p += 1;
            }
        }
    }
    style
}

fn ansi_std_color(code: u8) -> Color {
    match code {
        0 => Color::Black,
        1 => Color::Red,
        2 => Color::Green,
        3 => Color::Yellow,
        4 => Color::Blue,
        5 => Color::Magenta,
        6 => Color::Cyan,
        _ => Color::White,
    }
}

fn ansi_bright_color(code: u8) -> Color {
    match code {
        0 => Color::DarkGray,
        1 => Color::LightRed,
        2 => Color::LightGreen,
        3 => Color::LightYellow,
        4 => Color::LightBlue,
        5 => Color::LightMagenta,
        6 => Color::LightCyan,
        _ => Color::White,
    }
}

fn load_logo(profile: &str) -> Vec<Line<'static>> {
    let dots = std::env::var("DOTFILES_DIR").unwrap_or_else(|_| {
        format!("{}/.dotfiles", std::env::var("HOME").unwrap_or_default())
    });

    let paths = [
        format!("{}/config/.config/fastfetch/logo-{}.txt", dots, profile),
        format!("{}/shell/profiles/{}/logo.txt", dots, profile),
        format!("{}/config/.config/fastfetch/logo.txt", dots),
    ];

    for path in &paths {
        if let Ok(content) = std::fs::read_to_string(path) {
            let lines: Vec<Line<'static>> = content.lines().map(parse_line).collect();
            if !lines.is_empty() {
                return lines;
            }
        }
    }

    // Absolute fallback - corrected spelling
    vec![
        Line::from(Span::styled("  █▀█ █▀█ █▀▀ █▄░█   █▀▀ █░░ ▄▀█ █░█░█", theme::pointer())),
        Line::from(Span::styled("  █▄█ █▀▀ ██▄ █░▀█   █▄▄ █▄▄ █▀█ ▀▄▀▄▀", theme::pointer())),
        Line::from(Span::styled("     OPEN CLAW", theme::title())),
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
                    KeyCode::Down | KeyCode::Char('j') => {
                        if app.focus_items {
                            app.step_item(1);
                        } else {
                            app.step_category(1);
                        }
                    }
                    KeyCode::Up | KeyCode::Char('k') => {
                        if app.focus_items {
                            app.step_item(-1);
                        } else {
                            app.step_category(-1);
                        }
                    }
                    KeyCode::Right | KeyCode::Char('l') | KeyCode::Tab => {
                        app.focus_items = true;
                    }
                    KeyCode::Left | KeyCode::Char('h') | KeyCode::BackTab => {
                        app.focus_items = false;
                    }
                    KeyCode::Enter => {
                        if !app.focus_items {
                            app.focus_items = true;
                        } else {
                            app.confirm();
                        }
                    }
                    _ => {}
                }
            }
        }
    }
    Ok(())
}

fn ui(f: &mut Frame, app: &mut App) {
    let root = Layout::vertical([
        Constraint::Length(15), // logo and readout (the header block)
        Constraint::Min(5),    // category and item panes (the menu block)
        Constraint::Length(1)   // footer status bar
    ]).split(f.area());

    let head = Layout::horizontal([
        Constraint::Length(34), // dynamic logo width
        Constraint::Min(30)    // readout table
    ]).split(root[0]);

    // 1. Render Logo Pane
    let logo_widget = Paragraph::new(app.active_logo.clone());
    f.render_widget(logo_widget, head[0]);

    // 2. Render Readout Info Table
    let rows: Vec<Row> = app.readout.iter().take(12).map(|(k, v)| {
        Row::new(vec![
            Span::styled(k.clone(), theme::key()),
            Span::styled(v.clone(), theme::value()),
        ])
    }).collect();
    let table = Table::new(rows, [Constraint::Length(12), Constraint::Min(10)])
        .block(Block::default().borders(Borders::LEFT).border_style(Style::default().fg(theme::rule())));
    f.render_widget(table, head[1]);

    // 3. Render Categorized Menu Split
    let menu_split = Layout::horizontal([
        Constraint::Percentage(40), // Left: Categories
        Constraint::Percentage(60)  // Right: Items
    ]).split(root[1]);

    // Render Categories List
    let cat_items: Vec<ListItem> = app.categories.iter().map(|cat| {
        ListItem::new(Line::from(Span::styled(format!("  {}", cat.name), theme::value())))
    }).collect();

    let cat_block = Block::default()
        .borders(Borders::ALL)
        .title(" Categories ")
        .border_style(Style::default().fg(if !app.focus_items { theme::blue() } else { theme::rule() }));

    let cat_style = if !app.focus_items {
        theme::selected()
    } else {
        Style::default().add_modifier(Modifier::BOLD)
    };

    let cat_list = List::new(cat_items)
        .block(cat_block)
        .highlight_style(cat_style)
        .highlight_symbol("❯ ");
    f.render_stateful_widget(cat_list, menu_split[0], &mut app.cat_state);

    // Render Items List
    let current_cat_idx = app.cat_state.selected().unwrap_or(0);
    let items_in_cat = &app.categories[current_cat_idx].items;

    let item_list_items: Vec<ListItem> = items_in_cat.iter().map(|it| {
        let style = match it.kind {
            Kind::Action => Style::default().fg(theme::orange()),
            Kind::Profile => theme::value(),
            Kind::Header => theme::title(),
        };
        ListItem::new(Line::from(Span::styled(it.label.clone(), style)))
    }).collect();

    let item_block = Block::default()
        .borders(Borders::ALL)
        .title(format!(" {} Items ", app.categories[current_cat_idx].name))
        .border_style(Style::default().fg(if app.focus_items { theme::blue() } else { theme::rule() }));

    let item_style = if app.focus_items {
        theme::selected()
    } else {
        Style::default().add_modifier(Modifier::BOLD)
    };

    let item_list = List::new(item_list_items)
        .block(item_block)
        .highlight_style(item_style)
        .highlight_symbol("❯ ");
    f.render_stateful_widget(item_list, menu_split[1], &mut app.item_state);

    // 4. Render Footer Status Bar
    let bar = Paragraph::new(Line::from(vec![
        Span::styled("  ←/→", theme::pointer()), Span::styled(" switch pane  ", theme::value()),
        Span::styled("↑/↓", theme::pointer()), Span::styled(" navigate  ", theme::value()),
        Span::styled("⏎", theme::pointer()), Span::styled(" select  ", theme::value()),
        Span::styled("esc", theme::pointer()), Span::styled(" bare shell", theme::value()),
    ])).style(Style::default().fg(theme::muted()));
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
        assert!(!pairs.iter().any(|(k, _)| k == " WiFi"));
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
        assert_eq!(first_selectable(&items), Some(1));
    }

    #[test]
    fn build_items_has_headers_and_actions() {
        let v = build_items();
        assert!(matches!(v[0].kind, Kind::Header));
        assert!(v.iter().any(|i| matches!(i.kind, Kind::Profile)));
        assert!(v.iter().any(|i| matches!(i.kind, Kind::Action) && i.key == "doctor"));
    }

    #[test]
    fn header_not_selectable() {
        assert!(!Item::header("x").selectable());
        assert!(Item::profile("p").selectable());
        assert!(Item::action("a", "l").selectable());
    }

    #[test]
    fn parse_line_handles_templates_and_ansi() {
        let line = parse_line("$2BlueText$1MutedText\x1b[38;2;255;0;0mRedText");
        assert_eq!(line.spans.len(), 3);
        assert_eq!(line.spans[0].content, "BlueText");
        assert_eq!(line.spans[1].content, "MutedText");
        assert_eq!(line.spans[2].content, "RedText");
        
        // Assert color styling
        assert_eq!(line.spans[0].style.fg, Some(theme::blue()));
        assert_eq!(line.spans[1].style.fg, Some(theme::muted()));
        assert_eq!(line.spans[2].style.fg, Some(Color::Rgb(255, 0, 0)));
    }
}
