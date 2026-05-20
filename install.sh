#!/usr/bin/env bash
#
#   Mira — your interface mirror
#   https://miraworld.net
#
#   One-line install:
#       curl -sSL https://miraworld.net/install.sh | bash
#
#   What this does:
#     1. Clones github.com/borademircan/mip INTO THE CURRENT DIRECTORY
#        (falls back to a ./mira/ subdir if the current dir isn't empty)
#     2. Installs pnpm if missing, then `pnpm install`
#     3. Asks four short questions:
#         - your name (defaults to $USER)
#         - your email
#         - color palette (10 well-known design-system themes)
#         - preferred AI provider + model + API key (or local Ollama URL)
#     4. Writes the answers into the right files:
#         - data/users.json           (owner name, email, theme preference)
#         - data/themes/default-theme.json   (primary color → palette)
#         - data/connections.json     (AI provider connection, activates the app)
#     5. Starts both dev servers in the background and opens your browser.
#
#   No sudo. Reads use /dev/tty so this works through `curl | bash`.
#

set -euo pipefail

REPO="https://github.com/borademircan/mip.git"

# ── tiny color helpers (no-op when not a tty) ────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_CYAN=$'\033[36m'; C_MAG=$'\033[35m'; C_LIME=$'\033[92m'; C_AMB=$'\033[93m'
  C_DIM=$'\033[2m';   C_BOLD=$'\033[1m'; C_RED=$'\033[31m'; C_RESET=$'\033[0m'
else
  C_CYAN=""; C_MAG=""; C_LIME=""; C_AMB=""; C_DIM=""; C_BOLD=""; C_RED=""; C_RESET=""
fi

say()  { printf "%s%s%s\n" "$C_CYAN" "$1" "$C_RESET"; }
ok()   { printf "%s✓%s %s\n" "$C_LIME" "$C_RESET" "$1"; }
warn() { printf "%s!%s %s\n" "$C_AMB" "$C_RESET" "$1"; }
die()  { printf "%s✗%s %s\n" "$C_RED" "$C_RESET" "$1" >&2; exit 1; }
ask()  { local var=$1 prompt=$2 def=${3:-}; local val; read -r -p "$(printf "  %s%s%s%s" "$C_DIM" "$prompt" "$([ -n "$def" ] && echo " [$def]")" "$C_RESET ")" val </dev/tty || true; printf -v "$var" "%s" "${val:-$def}"; }
ask_secret() { local var=$1 prompt=$2; local val; read -r -s -p "$(printf "  %s%s%s " "$C_DIM" "$prompt" "$C_RESET")" val </dev/tty || true; echo; printf -v "$var" "%s" "$val"; }

# ── banner ───────────────────────────────────────────────────────────
printf "\n"
printf "  %s▲ MIRA%s   %s— your interface mirror%s\n" "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
printf "  %sa two-column conversation with AI · MIP + MCP%s\n" "$C_DIM" "$C_RESET"
printf "\n"

# ── prereqs ──────────────────────────────────────────────────────────
say "→ Checking prerequisites…"
command -v git  >/dev/null || die "git is required."
command -v node >/dev/null || die "Node.js (>= 20) is required. https://nodejs.org"
NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
[ "$NODE_MAJOR" -ge 18 ] || die "Node.js >= 20 required (you have v$(node --version))."
command -v npm >/dev/null || die "npm is required (ships with Node.js)."

# pnpm bootstrap: try corepack, validate it actually works, fall back to
# `npm i -g pnpm`. Some Node 20.x builds have a broken corepack shim
# (ERR_VM_DYNAMIC_IMPORT_CALLBACK_MISSING) which silently returns an empty
# version string — we detect that and fix it.
ensure_pnpm() {
  if command -v pnpm >/dev/null && pnpm --version >/dev/null 2>&1; then
    PNPM_VERSION=$(pnpm --version 2>/dev/null)
    [ -n "$PNPM_VERSION" ] && return 0
  fi
  warn "pnpm not found (or broken on this Node) — installing…"

  # try corepack first
  if command -v corepack >/dev/null; then
    corepack enable >/dev/null 2>&1 || true
    corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true
  fi

  # validate corepack-installed pnpm actually runs
  if command -v pnpm >/dev/null && pnpm --version >/dev/null 2>&1; then
    PNPM_VERSION=$(pnpm --version 2>/dev/null)
    [ -n "$PNPM_VERSION" ] && return 0
  fi

  # corepack shim is broken (known bug on some Node 20.x) — bypass it
  warn "corepack pnpm shim isn't working — switching to npm-installed pnpm"
  rm -rf "${HOME:-/root}/.cache/node/corepack" 2>/dev/null || true
  hash -r 2>/dev/null || true
  npm install -g pnpm >/dev/null 2>&1 || die "npm i -g pnpm failed. Install pnpm manually: https://pnpm.io/installation"

  PNPM_VERSION=$(pnpm --version 2>/dev/null || true)
  [ -n "$PNPM_VERSION" ] || die "pnpm is installed but '$(command -v pnpm) --version' fails. Try: rm -rf ~/.cache/node/corepack && npm i -g pnpm"
  return 0
}
ensure_pnpm
ok "git, node $(node --version), pnpm $PNPM_VERSION"

# ── pick install target (current dir if possible, else ./mira) ───────
TARGET="$PWD"
NEED_SUBDIR=0
if [ -n "$(ls -A 2>/dev/null | grep -v '^\.$\|^\.\.$' || true)" ]; then
  warn "Current directory '$PWD' is not empty."
  ANSWER=""
  ask ANSWER "Install Mira here anyway? files won't be overwritten unless they conflict (y/N)" "N"
  case "${ANSWER,,}" in
    y|yes) NEED_SUBDIR=0 ;;
    *)
      NEED_SUBDIR=1
      TARGET="$PWD/mira"
      [ -e "$TARGET" ] && die "'$TARGET' already exists. Move it aside or set MIRA_DIR=alt-name."
      ;;
  esac
fi

# ── clone ────────────────────────────────────────────────────────────
if [ "$NEED_SUBDIR" -eq 1 ]; then
  say "→ Cloning Mira into $TARGET…"
  git clone --depth 1 "$REPO" "$TARGET" >/dev/null 2>&1
  cd "$TARGET"
else
  say "→ Cloning Mira into current directory…"
  TMP=$(mktemp -d)
  git clone --depth 1 "$REPO" "$TMP" >/dev/null 2>&1
  # move everything (including dotfiles) into current dir without clobbering
  shopt -s dotglob
  for entry in "$TMP"/*; do
    [ "$(basename "$entry")" = ".git" ] && continue
    base=$(basename "$entry")
    [ -e "$PWD/$base" ] && { warn "skipping existing $base"; continue; }
    mv "$entry" "$PWD/"
  done
  # carry over .git so the install dir is a working clone
  if [ ! -e "$PWD/.git" ]; then mv "$TMP/.git" "$PWD/.git"; fi
  rm -rf "$TMP"
  shopt -u dotglob
fi
ok "cloned $REPO"

# ── install deps ─────────────────────────────────────────────────────
say "→ Installing workspace dependencies (this can take a minute)…"
if ! pnpm install --reporter=append-only 2>&1; then
  die "pnpm install failed. See the output above for the error. Common fixes:
    · delete node_modules and retry: rm -rf node_modules && pnpm install
    · Node version too old: node --version (need >= 20)
    · permission issue: don't run as root if you're in your own home dir"
fi
ok "dependencies installed"

# ── interactive setup ────────────────────────────────────────────────
printf "\n"
printf "  %sLet's set up your install.%s  All answers are saved locally — nothing leaves your machine.\n" "$C_BOLD" "$C_RESET"
printf "\n"

# 1. name + email
DEFAULT_NAME="${USER:-}"
[ -n "$DEFAULT_NAME" ] && DEFAULT_NAME=$(echo "$DEFAULT_NAME" | sed -e 's/.*/\u&/')
ask USER_NAME  "Your name"   "$DEFAULT_NAME"
ask USER_EMAIL "Your email"  ""
[ -z "$USER_NAME"  ] && USER_NAME="Owner"
[ -z "$USER_EMAIL" ] && USER_EMAIL="owner@example.com"

# 2. color palette — the same 10 design-system themes the in-app picker offers,
#    so after install the Appearance picker highlights the active one (vs.
#    showing "Custom"). Mapping lives in data/themes/<id>-theme.json — strings
#    here must match those filenames.
printf "\n  %sPick a palette:%s  %s(same 10 themes you'll find in Settings → Appearance)%s\n" "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
printf "    1)  %sMira · Dark%s          neon cyan · the Mira default\n"            "$C_CYAN" "$C_RESET"
printf "    2)  %sLinear · Dark%s        indigo on near-black · calm dev surface\n" "$C_CYAN" "$C_RESET"
printf "    3)  %sVercel · Dark%s        pure black + white · minimal contrast\n"   "$C_BOLD" "$C_RESET"
printf "    4)  %sCatppuccin · Mocha%s   pastel purple on warm dark\n"              "$C_MAG"  "$C_RESET"
printf "    5)  %sTokyo Night%s          soft blue on indigo · editor favorite\n"   "$C_CYAN" "$C_RESET"
printf "    6)  %sNord · Dark%s          frost cyan on cool slate · Arctic\n"       "$C_CYAN" "$C_RESET"
printf "    7)  %sDracula%s              purple + pink on slate · classic dev\n"    "$C_MAG"  "$C_RESET"
printf "    8)  %sOne Dark%s             blue on graphite · balanced, readable\n"   "$C_CYAN" "$C_RESET"
printf "    9)  %sTailwind · Light%s     blue-500 on slate-50 · crisp modern\n"     "$C_CYAN" "$C_RESET"
printf "    10) %sSolarized · Light%s    cream paper + deep cyan · the classic\n"   "$C_AMB"  "$C_RESET"
ask PALETTE_CHOICE "Palette [1-10]" "1"
case "$PALETTE_CHOICE" in
  2)  PAL_NAME="linear-dark"      ;;
  3)  PAL_NAME="vercel-dark"      ;;
  4)  PAL_NAME="catppuccin-mocha" ;;
  5)  PAL_NAME="tokyo-night"      ;;
  6)  PAL_NAME="nord-dark"        ;;
  7)  PAL_NAME="dracula"          ;;
  8)  PAL_NAME="one-dark"         ;;
  9)  PAL_NAME="tailwind-light"   ;;
  10) PAL_NAME="solarized-light"  ;;
  *)  PAL_NAME="mira-dark"        ;;
esac
PAL_FILE="data/themes/${PAL_NAME}-theme.json"
if [ ! -f "$PAL_FILE" ]; then
  warn "theme file $PAL_FILE missing — falling back to mira-dark"
  PAL_NAME="mira-dark"
  PAL_FILE="data/themes/mira-dark-theme.json"
fi
# Pull the primary color out for the final status printout
PAL_PRIMARY=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$PAL_FILE','utf8')).colors.primary)" 2>/dev/null || echo "")
ok "palette: $PAL_NAME ($PAL_PRIMARY)"

# 3. preferred AI provider
printf "\n  %sPreferred AI provider:%s\n" "$C_BOLD" "$C_RESET"
printf "    1) %sAnthropic%s  · Claude Haiku 4.5 / Sonnet / Opus  (cloud, API key)\n" "$C_CYAN" "$C_RESET"
printf "    2) %sOpenAI%s     · GPT-4o / GPT-4.1 / o-series       (cloud, API key)\n" "$C_CYAN" "$C_RESET"
printf "    3) %sGemini%s     · Gemini 2.5 Flash / Pro            (cloud, API key)\n" "$C_CYAN" "$C_RESET"
printf "    4) %sOllama%s     · local model (Qwen / Llama / Mistral) — full privacy\n" "$C_LIME" "$C_RESET"
ask AI_CHOICE "Provider [1-4]" "1"

case "$AI_CHOICE" in
  2)
    APP_ID="openai";  APP_NAME="OpenAI";    AUTH_TYPE="apiKey"
    BASE_URL="https://api.openai.com"
    printf "    Models: 1) gpt-4o-mini  2) gpt-4o  3) gpt-4.1-mini  4) gpt-4.1  5) o3-mini\n"
    ask MODEL_CHOICE "Model [1-5]" "1"
    case "$MODEL_CHOICE" in
      2) AI_MODEL="gpt-4o" ;; 3) AI_MODEL="gpt-4.1-mini" ;;
      4) AI_MODEL="gpt-4.1" ;; 5) AI_MODEL="o3-mini" ;;
      *) AI_MODEL="gpt-4o-mini" ;;
    esac
    ask_secret API_KEY "OpenAI API key (sk-…)"
    ;;
  3)
    APP_ID="gemini";  APP_NAME="Google Gemini";  AUTH_TYPE="apiKey"
    BASE_URL="https://generativelanguage.googleapis.com"
    printf "    Models: 1) gemini-2.5-flash  2) gemini-2.5-pro  3) gemini-2.0-flash\n"
    ask MODEL_CHOICE "Model [1-3]" "1"
    case "$MODEL_CHOICE" in
      2) AI_MODEL="gemini-2.5-pro" ;; 3) AI_MODEL="gemini-2.0-flash" ;;
      *) AI_MODEL="gemini-2.5-flash" ;;
    esac
    ask_secret API_KEY "Gemini API key (AIza…)"
    ;;
  4)
    APP_ID="openai";  APP_NAME="Ollama (local)";  AUTH_TYPE="none"
    ask BASE_URL  "Ollama base URL"  "http://localhost:11434/v1"
    ask AI_MODEL  "Local model name (e.g. qwen2.5:14b)" "qwen2.5:14b-instruct"
    API_KEY="ollama"  # ollama accepts any string
    ;;
  *)
    APP_ID="anthropic";  APP_NAME="Anthropic";  AUTH_TYPE="apiKey"
    BASE_URL="https://api.anthropic.com"
    printf "    Models: 1) Haiku 4.5 (recommended for visual authoring)\n"
    printf "            2) Sonnet 4.6     3) Sonnet 4.5     4) Opus 4.7     5) Opus 4.5\n"
    ask MODEL_CHOICE "Model [1-5]" "1"
    case "$MODEL_CHOICE" in
      2) AI_MODEL="claude-sonnet-4-6" ;;
      3) AI_MODEL="claude-sonnet-4-5-20250929" ;;
      4) AI_MODEL="claude-opus-4-7" ;;
      5) AI_MODEL="claude-opus-4-5-20251101" ;;
      *) AI_MODEL="claude-haiku-4-5-20251001" ;;
    esac
    ask_secret API_KEY "Anthropic API key (sk-ant-…)"
    ;;
esac
[ -n "$API_KEY" ] || warn "no API key entered — you can add it later via the Connections page"
ok "$APP_NAME · $AI_MODEL"

# ── write config files (via node so we don't need jq) ────────────────
say "→ Writing your config…"

# Make sure the target files exist (they do in a fresh clone, but be defensive)
[ -f data/users.json ] || die "data/users.json missing — repo looks incomplete."
[ -f data/connections.json ] || echo '{"connections": []}' > data/connections.json
[ -f data/themes/default-theme.json ] || die "data/themes/default-theme.json missing."

# Pass user choices into node via env vars so we can use a *quoted*
# heredoc — that way bash leaves the JS untouched (no ${...} expansion,
# no backtick traps) and the JS reads everything from process.env.
USER_NAME="$USER_NAME" \
USER_EMAIL="$USER_EMAIL" \
PAL_NAME="$PAL_NAME" \
APP_ID="$APP_ID" \
APP_NAME="$APP_NAME" \
BASE_URL="$BASE_URL" \
AI_MODEL="$AI_MODEL" \
API_KEY="$API_KEY" \
node - <<'NODESCRIPT'
const fs = require("fs");
const e = process.env;

// ─── users.json: update the superadmin entry ─────────────────────────
{
  const path = "data/users.json";
  const j = JSON.parse(fs.readFileSync(path, "utf8"));
  const owner = (j.users || []).find(u => u.superadmin) || j.users[0];
  if (owner) {
    owner.name = e.USER_NAME;
    owner.email = e.USER_EMAIL;
    owner.preferences = Object.assign({}, owner.preferences, {
      theme: e.PAL_NAME,
      defaultProvider: e.APP_ID,
      defaultModel: e.AI_MODEL,
    });
  }
  fs.writeFileSync(path, JSON.stringify(j, null, 2) + "\n");
  console.log("  · data/users.json — owner =", owner ? owner.name : "(none)");
}

// ─── default-theme.json: copy the chosen preset verbatim ─────────────
// data/themes/<palette>-theme.json files ship with the full coherent
// color set (primary, background, surface, text, success, warning,
// danger), correct mode (dark/light), typography, radius, density.
// Strip the picker-only id/name/description fields when writing into
// the runtime default-theme.json so its schema stays minimal.
{
  const palette = e.PAL_NAME;
  const srcPath = "data/themes/" + palette + "-theme.json";
  const dstPath = "data/themes/default-theme.json";
  if (fs.existsSync(srcPath)) {
    const preset = JSON.parse(fs.readFileSync(srcPath, "utf8"));
    const { id, name, description, ...rest } = preset;
    fs.writeFileSync(dstPath, JSON.stringify(rest, null, 2) + "\n");
    console.log("  · data/themes/default-theme.json — copied from", srcPath, "· mode =", rest.mode);
  } else {
    console.log("  · data/themes/default-theme.json — preset", srcPath, "not found, leaving as-is");
  }
}

// ─── connections.json: append the AI provider connection ─────────────
{
  const path = "data/connections.json";
  const j = JSON.parse(fs.readFileSync(path, "utf8"));
  j.connections = j.connections || [];

  // remove any prior installer-managed AI connection so re-runs stay clean
  j.connections = j.connections.filter(c => c.id !== "conn-ai-default");

  // Pull endpoints from data/apps/<appId>/endpoints.json if it exists, so
  // the Connections page Test button works without the user having to
  // configure anything manually.
  let appEndpoints = [];
  const epPath = "data/apps/" + e.APP_ID + "/endpoints.json";
  try {
    if (fs.existsSync(epPath)) {
      const ep = JSON.parse(fs.readFileSync(epPath, "utf8"));
      appEndpoints = (ep.endpoints || []).map((ent) => ({
        id: ent.id,
        label: ent.label,
        method: ent.method,
        path: ent.path,
        mapPath: ent.mapPath || "$.data",
        description: ent.description || "",
        queryParams: [],
        headers: [],
        ...(ent.body ? { body: ent.body } : {}),
      }));
    }
  } catch (_) { /* ignore — fallback to empty list */ }

  const conn = {
    id: "conn-ai-default",
    name: e.APP_NAME,
    appId: e.APP_ID,
    scope: "global",
    config: {
      baseUrl: e.BASE_URL,
      model: e.AI_MODEL,
      ...(e.API_KEY ? { apiKey: e.API_KEY } : {}),
    },
    settings: {
      providerId: e.APP_ID,
      endpoints: appEndpoints,
      scope: "global",
    },
    enabledForAssistant: true,
    createdAt: new Date().toISOString(),
    createdBy: "installer",
  };
  j.connections.push(conn);
  fs.writeFileSync(path, JSON.stringify(j, null, 2) + "\n");
  console.log("  · data/connections.json — added", conn.appId, "(" + conn.config.model + ") with", appEndpoints.length, "endpoint(s)");
}
NODESCRIPT

ok "config written"

# ── Postgres: detect, provision if reachable, hint if not ─────────────
# Mira keeps runtime state (dashboards, AI conversations, app catalogs,
# connections) in Postgres. If it's running we run migrations + seed now
# so the choices the user just made (name, palette, AI provider) land in
# the DB. If not, we print a clear hint and let them continue — the
# frontend gracefully falls back to localStorage.
say "→ Checking Postgres…"
PG_READY=0
if command -v pg_isready >/dev/null 2>&1; then
  pg_isready -h 127.0.0.1 -p 5432 -q && PG_READY=1
fi
if [ "$PG_READY" -eq 0 ] && (echo > /dev/tcp/127.0.0.1/5432) 2>/dev/null; then
  PG_READY=1
fi

if [ "$PG_READY" -eq 1 ]; then
  ok "Postgres reachable on :5432"

  # Make sure .env exists so @mip/db reads DATABASE_URL correctly.
  if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
    ok ".env created from .env.example"
  fi

  # createdb is idempotent-ish (errors if it already exists, that's fine).
  if command -v createdb >/dev/null 2>&1; then
    createdb mip 2>/dev/null && ok "createdb mip" || ok "mip database already exists"
  else
    warn "createdb not on PATH — skipping. Run manually if migrations fail: createdb mip"
  fi

  say "→ Running migrations + seeding data/ into Postgres (this can take ~30s)…"
  if pnpm db:migrate >/dev/null 2>&1; then
    ok "schema migrated"
    if pnpm db:seed >/dev/null 2>&1; then
      ok "data/ seeded into Postgres — your choices are persisted"
    else
      warn "pnpm db:seed failed — chat sessions still work via localStorage. Re-run with: pnpm db:seed"
    fi
  else
    warn "pnpm db:migrate failed — chat sessions will work via localStorage only"
    warn "Re-run by hand: pnpm db:migrate && pnpm db:seed"
  fi
else
  warn "Postgres is NOT running on :5432"
  printf "\n"
  printf "  %sMira works without Postgres%s — chat sessions and connections will save to\n" "$C_BOLD" "$C_RESET"
  printf "  your browser's localStorage. For server-side persistence (cross-device,\n"
  printf "  cross-browser, durable), install Postgres now:\n\n"
  printf "    %s# macOS — Homebrew (recommended)%s\n" "$C_DIM" "$C_RESET"
  printf "    %sbrew install postgresql@16 && brew services start postgresql@16%s\n\n" "$C_CYAN" "$C_RESET"
  printf "    %s# Linux / WSL%s\n" "$C_DIM" "$C_RESET"
  printf "    %ssudo apt install postgresql-16 && sudo systemctl enable --now postgresql%s\n\n" "$C_CYAN" "$C_RESET"
  printf "    %s# Anywhere — Docker%s\n" "$C_DIM" "$C_RESET"
  printf "    %sdocker run --name mip-pg -e POSTGRES_HOST_AUTH_METHOD=trust -p 5432:5432 -d postgres:16%s\n\n" "$C_CYAN" "$C_RESET"
  printf "  Then, back in this directory:\n\n"
  printf "    %screatedb mip && pnpm db:migrate && pnpm db:seed%s\n\n" "$C_CYAN" "$C_RESET"
  printf "  The dev servers will start in a moment with localStorage fallback in the meantime.\n"
  printf "\n"
fi

# ── start the dev servers in the background ──────────────────────────
say "→ Starting Mira on http://localhost:5173 …"

mkdir -p .mira-runtime
PROXY_LOG=".mira-runtime/data-proxy.log"
FRONT_LOG=".mira-runtime/dashboard-react.log"

# tear down anything we previously started, so re-runs are clean
if [ -f .mira-runtime/pids ]; then
  while IFS= read -r pid; do kill "$pid" 2>/dev/null || true; done < .mira-runtime/pids
  rm -f .mira-runtime/pids
fi

(pnpm --filter @mip/data-proxy dev >"$PROXY_LOG" 2>&1 &) ; PROXY_PID=$!
(pnpm --filter @mip/dashboard-react dev >"$FRONT_LOG" 2>&1 &) ; FRONT_PID=$!
echo "$PROXY_PID" >  .mira-runtime/pids
echo "$FRONT_PID" >> .mira-runtime/pids

# wait for port 5173 (max 30s)
for i in $(seq 1 30); do
  if (echo > /dev/tcp/127.0.0.1/5173) 2>/dev/null; then ok "frontend up on :5173"; break; fi
  sleep 1
  [ "$i" -eq 30 ] && warn "frontend didn't bind in 30s — check $FRONT_LOG"
done

# best-effort open browser
URL="http://127.0.0.1:5173/"
if command -v open >/dev/null; then open "$URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null; then xdg-open "$URL" 2>/dev/null || true
fi

# ── done ─────────────────────────────────────────────────────────────
printf "\n"
printf "  %s▲ Mira is live.%s  %s%s%s\n" "$C_BOLD$C_LIME" "$C_RESET" "$C_CYAN" "$URL" "$C_RESET"
printf "\n"
printf "  %sLogs:%s          tail -f $PROXY_LOG  ·  tail -f $FRONT_LOG\n" "$C_DIM" "$C_RESET"
printf "  %sStop servers:%s  kill \$(cat .mira-runtime/pids)\n" "$C_DIM" "$C_RESET"
printf "  %sRe-run setup:%s  delete .mira-runtime/ and re-run the install command\n" "$C_DIM" "$C_RESET"
printf "\n"
printf "  %sBrand:%s        %s · %s\n" "$C_DIM" "$C_RESET" "$USER_NAME" "$USER_EMAIL"
printf "  %sPalette:%s      %s · primary %s\n" "$C_DIM" "$C_RESET" "$PAL_NAME" "$PAL_PRIMARY"
printf "  %sAI provider:%s  %s · %s\n" "$C_DIM" "$C_RESET" "$APP_NAME" "$AI_MODEL"
if [ "$PG_READY" -eq 1 ]; then
  printf "  %sPersistence:%s  Postgres on :5432 (durable, cross-device)\n" "$C_DIM" "$C_RESET"
else
  printf "  %sPersistence:%s  browser localStorage only — install Postgres for server-side sync\n" "$C_DIM" "$C_RESET"
fi
printf "\n"
printf "  %sDocs · roadmap · architecture:%s  %shttps://github.com/borademircan/mip%s\n" "$C_DIM" "$C_RESET" "$C_MAG" "$C_RESET"
printf "  %sLanding · positioning · pitch:%s  %shttps://miraworld.net%s\n" "$C_DIM" "$C_RESET" "$C_MAG" "$C_RESET"
printf "\n"
