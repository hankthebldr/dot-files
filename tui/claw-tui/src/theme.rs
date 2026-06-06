//! GitHub macOS Dark palette — the single source of truth for TUI styling.
use ratatui::style::{Color, Modifier, Style};

pub const BLUE:   Color = Color::Rgb(0x58, 0xa6, 0xff);
pub const GREEN:  Color = Color::Rgb(0x3f, 0xb9, 0x50);
pub const PURPLE: Color = Color::Rgb(0xbc, 0x8c, 0xff);
pub const ORANGE: Color = Color::Rgb(0xd2, 0x99, 0x22);
#[allow(dead_code)] // palette completeness — used by error states in later screens
pub const RED:    Color = Color::Rgb(0xff, 0x7b, 0x72);
pub const MUTED:  Color = Color::Rgb(0x8b, 0x94, 0x9e);
pub const FG:     Color = Color::Rgb(0xc9, 0xd1, 0xd9);
pub const SEL_BG: Color = Color::Rgb(0x16, 0x1b, 0x22);
pub const RULE:   Color = Color::Rgb(0x30, 0x36, 0x3d);

pub fn key() -> Style { Style::default().fg(BLUE) }
pub fn value() -> Style { Style::default().fg(FG) }
pub fn title() -> Style { Style::default().fg(PURPLE).add_modifier(Modifier::BOLD) }
pub fn selected() -> Style { Style::default().fg(FG).bg(SEL_BG).add_modifier(Modifier::BOLD) }
pub fn pointer() -> Style { Style::default().fg(GREEN).add_modifier(Modifier::BOLD) }
