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

echo -e "\n\033[38;5;166m[!] Research Profile Loaded. Initialized Workspace: $RESEARCH_WORKSPACE\033[0m\n"
