//! Theme — loads the ACTIVE Open Claw palette at runtime so the ratatui TUI
//! follows `claw theme set X` / profile theming like every other surface.
//! Precedence (same contract as theme.sh / claw-dashboard.py):
//!   CLAW_THEME env → $XDG_STATE_HOME/claw/theme → refined-dark defaults.
//! Palettes are parsed from $DOTFILES_DIR/config/themes/<slug>/palette.theme
//! (falling back to the legacy flat <slug>.theme layout).
use ratatui::style::{Color, Modifier, Style};
use std::sync::OnceLock;

struct Palette {
    blue: Color,
    green: Color,
    purple: Color,
    amber: Color,
    muted: Color,
    red: Color,
    fg: Color,
    sel_bg: Color,
    rule: Color,
}

impl Default for Palette {
    // Refined GitHub Dark — identical to the old compile-time constants.
    fn default() -> Self {
        Palette {
            blue: Color::Rgb(0x58, 0xa6, 0xff),
            green: Color::Rgb(0x3f, 0xb9, 0x50),
            purple: Color::Rgb(0xbc, 0x8c, 0xff),
            amber: Color::Rgb(0xe3, 0xb3, 0x41),
            muted: Color::Rgb(0x8b, 0x94, 0x9e),
            red: Color::Rgb(0xff, 0x7b, 0x72),
            fg: Color::Rgb(0xc9, 0xd1, 0xd9),
            sel_bg: Color::Rgb(0x16, 0x1b, 0x22),
            rule: Color::Rgb(0x30, 0x36, 0x3d),
        }
    }
}

fn hex(s: &str) -> Option<Color> {
    let s = s.trim().trim_start_matches('#');
    if s.len() != 6 {
        return None;
    }
    let r = u8::from_str_radix(&s[0..2], 16).ok()?;
    let g = u8::from_str_radix(&s[2..4], 16).ok()?;
    let b = u8::from_str_radix(&s[4..6], 16).ok()?;
    Some(Color::Rgb(r, g, b))
}

fn load() -> Palette {
    let mut p = Palette::default();
    let dots = std::env::var("DOTFILES_DIR")
        .unwrap_or_else(|_| format!("{}/.dotfiles", std::env::var("HOME").unwrap_or_default()));
    // active slug: CLAW_THEME env → state file → default
    let slug = std::env::var("CLAW_THEME").ok().filter(|s| !s.is_empty()).or_else(|| {
        let state = std::env::var("XDG_STATE_HOME")
            .unwrap_or_else(|_| format!("{}/.local/state", std::env::var("HOME").unwrap_or_default()));
        std::fs::read_to_string(format!("{state}/claw/theme"))
            .ok()
            .and_then(|s| s.lines().next().map(|l| l.trim().to_string()))
            .filter(|s| !s.is_empty())
    });
    let Some(slug) = slug else { return p };
    let dir_path = format!("{dots}/config/themes/{slug}/palette.theme");
    let flat_path = format!("{dots}/config/themes/{slug}.theme");
    let Ok(body) = std::fs::read_to_string(&dir_path)
        .or_else(|_| std::fs::read_to_string(&flat_path))
    else {
        return p;
    };
    for line in body.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else { continue };
        let Some(c) = hex(v) else { continue };
        match k.trim() {
            "blue" => p.blue = c,
            "green" => p.green = c,
            "purple" => p.purple = c,
            "amber" => p.amber = c,
            "muted" => p.muted = c,
            "red" => p.red = c,
            "fg" => p.fg = c,
            "bg_alt" => p.sel_bg = c,
            "divider" => p.rule = c,
            _ => {}
        }
    }
    p
}

fn pal() -> &'static Palette {
    static PAL: OnceLock<Palette> = OnceLock::new();
    PAL.get_or_init(load)
}

pub fn orange() -> Color { pal().amber }
pub fn muted() -> Color { pal().muted }
pub fn rule() -> Color { pal().rule }

pub fn blue() -> Color { pal().blue }
pub fn green() -> Color { pal().green }
pub fn purple() -> Color { pal().purple }
pub fn red() -> Color { pal().red }

pub fn key() -> Style { Style::default().fg(pal().blue) }
pub fn value() -> Style { Style::default().fg(pal().fg) }
pub fn title() -> Style { Style::default().fg(pal().purple).add_modifier(Modifier::BOLD) }
pub fn selected() -> Style { Style::default().fg(pal().fg).bg(pal().sel_bg).add_modifier(Modifier::BOLD) }
pub fn pointer() -> Style { Style::default().fg(pal().green).add_modifier(Modifier::BOLD) }

#[cfg(test)]
mod theme_tests {
    #[test]
    fn hex_parses_six_digit() {
        // guards the palette hex parser used by both layouts
        assert!(super::hex("#58a6ff").is_some());
        assert!(super::hex("nope").is_none());
    }
}
