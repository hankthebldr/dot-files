# Research Profile
# Loadout for Data Exploration, OSINT, Scraping, and Text Analytics
export CLAW_PROFILE_THEME="research"

# ==========================================
# ENVIRONMENT VARIABLES
# ==========================================
export RESEARCH_WORKSPACE="$HOME/research"
mkdir -p "$RESEARCH_WORKSPACE"

# ==========================================
# CATEGORIZED ALIASES & PIPELINES
# ==========================================

# --- Scraping & HTTP ---
alias res-curl="curl -s"
alias res-http="httpie"
alias res-wget="wget -qO-"

# --- JSON/Data Pipelines ---
alias res-jq="jq"
alias res-csv="csvkit"
# Example pipeline alias: Take an API endpoint and convert its JSON to CSV
alias res-json2csv="jq -r '.[] | [.id, .title] | @csv' | csvformat"

# --- Corpus Search ---
alias res-rg="ripgrep"
alias res-grep="grep -rn"
alias res-awk="awk"
alias res-sed="sed"

# --- Asset Extraction ---
alias res-yt="yt-dlp --dump-json"
alias res-pup="pup"
alias res-pandoc="pandoc"

# ==========================================
# HELPER FUNCTIONS
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
  echo -e "  ${bold}${orange}Scraping & HTTP${reset}"
  echo -e "    ${white}res-curl${reset}       ${dim}Silent curl request${reset}"
  echo -e "    ${white}res-http${reset}       ${dim}HTTPie client${reset}"
  echo -e "    ${white}res-wget${reset}       ${dim}Quiet wget to stdout${reset}"
  echo ""
  echo -e "  ${bold}${orange}JSON/Data Pipelines${reset}"
  echo -e "    ${white}res-jq${reset}         ${dim}jq JSON processor${reset}"
  echo -e "    ${white}res-csv${reset}        ${dim}csvkit toolkit${reset}"
  echo -e "    ${white}res-json2csv${reset}   ${dim}Convert JSON array to CSV${reset}"
  echo ""
  echo -e "  ${bold}${orange}Corpus Search${reset}"
  echo -e "    ${white}res-rg${reset}         ${dim}ripgrep search${reset}"
  echo -e "    ${white}res-grep${reset}       ${dim}Recursive grep with line numbers${reset}"
  echo -e "    ${white}res-awk${reset}        ${dim}AWK processing${reset}"
  echo -e "    ${white}res-sed${reset}        ${dim}sed stream editor${reset}"
  echo ""
  echo -e "  ${bold}${orange}Asset Extraction${reset}"
  echo -e "    ${white}res-yt${reset}         ${dim}yt-dlp JSON metadata dump${reset}"
  echo -e "    ${white}res-pup${reset}        ${dim}HTML parsing with pup${reset}"
  echo -e "    ${white}res-pandoc${reset}     ${dim}Document conversion${reset}"
  echo ""
}

_research_tool_check() {
  local green='\e[38;2;63;185;80m'
  local red='\e[38;2;248;81;73m'
  local dim='\e[38;2;139;148;158m'
  local white='\e[38;2;201;209;217m'
  local bold='\e[1m'
  local orange='\e[38;2;210;153;34m'
  local reset='\e[0m'

  local tools=(curl httpie jq csvkit rg awk pup htmlq yt-dlp pandoc python3)
  local found=0
  local missing=0

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
