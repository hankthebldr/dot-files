# Research Profile
# Loadout for Data Exploration, OSINT, Scraping, and Text Analytics
export CLAW_PROFILE_THEME="research"

export RESEARCH_WORKSPACE="$HOME/research"
mkdir -p "$RESEARCH_WORKSPACE" 2>/dev/null

# ==========================================
# ALIASES — short, unprefixed, value-add only
# ==========================================
# (de-prefixed 2026-04-28: dropped pure renames res-jq=jq, res-rg=ripgrep,
#  res-grep=grep -rn, res-curl=curl -s, res-pup=pup, res-pandoc=pandoc.
#  Use the real binary names. Compositions kept under short mnemonics.)

# --- Quiet HTTP fetchers ---
alias curls="curl -s"
alias wgetc="wget -qO-"

# --- Pipelines worth keeping ---
# Take an API endpoint's JSON array, output id+title CSV
alias json2csv="jq -r '.[] | [.id, .title] | @csv' | csvformat"
# yt-dlp metadata dump (for scraping video info, not downloading)
alias ytj="yt-dlp --dump-json"

# Note: jq, csvkit, ripgrep, grep, awk, sed, pup, htmlq, httpie, pandoc
# are used by their real binary names — they're already short and well-known.

# ==========================================
# QUICK REFERENCE
# ==========================================
research-help() {
  local orange='\e[38;2;210;153;34m'
  local purple='\e[38;2;188;140;255m'
  local dim='\e[38;2;139;148;158m'
  local white='\e[38;2;201;209;217m'
  local bold='\e[1m'
  local reset='\e[0m'

  echo ""
  echo -e "  ${purple}╭──────────────────────────────────────────────────────────╮${reset}"
  echo -e "  ${purple}│${reset}  ${bold}${orange}RESEARCH PROFILE${reset} ${dim}— Quick Reference${reset}                      ${purple}│${reset}"
  echo -e "  ${purple}╰──────────────────────────────────────────────────────────╯${reset}"
  echo ""
  echo -e "  ${bold}${orange}Quiet HTTP fetchers${reset}"
  echo -e "    ${white}curls${reset}      ${dim}curl -s (silent, body to stdout)${reset}"
  echo -e "    ${white}wgetc${reset}      ${dim}wget -qO- (silent, body to stdout)${reset}"
  echo ""
  echo -e "  ${bold}${orange}Pipelines${reset}"
  echo -e "    ${white}json2csv${reset}   ${dim}JSON array → id,title CSV${reset}"
  echo -e "    ${white}ytj${reset}        ${dim}yt-dlp --dump-json (metadata only)${reset}"
  echo ""
  echo -e "  ${bold}${orange}Use directly${reset} ${dim}(no profile prefix needed)${reset}"
  echo -e "    ${dim}jq · csvkit · rg (ripgrep) · grep · awk · sed${reset}"
  echo -e "    ${dim}httpie (http) · pup · htmlq · pandoc · yt-dlp${reset}"
  echo ""
}

# ==========================================
# TOOL AVAILABILITY CHECK
# ==========================================
_research_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;248;81;73m'
  local dim='\e[38;2;139;148;158m'
  local white='\e[38;2;201;209;217m'
  local bold='\e[1m'
  local orange='\e[38;2;210;153;34m'
  local reset='\e[0m'

  local tools=(curl httpie jq csvkit rg awk pup htmlq yt-dlp pandoc python3)
  local found=0 missing=0

  echo ""
  echo -e "  ${bold}${orange}Research Toolchain Status${reset}"
  echo -e "  ${dim}─────────────────────────${reset}"
  for tool in "${tools[@]}"; do
    if command -v "$tool" &> /dev/null; then
      echo -e "    ${green}●${reset} ${white}${tool}${reset}"
      ((found++))
    else
      echo -e "    ${red}✗${reset} ${dim}${tool}${reset}  ${red}not found${reset}"
      ((missing++))
    fi
  done
  echo ""
  echo -e "  ${dim}Summary:${reset} ${green}${found} installed${reset}  ${red}${missing} missing${reset}  ${dim}(${#tools[@]} total)${reset}"
  echo ""
}

# Profile banner handled by fastfetch (config-research.jsonc)
