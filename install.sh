#!/usr/bin/env bash
#
#   Mira — your interface mirror
#   https://borademircan.com/mira
#
#   One-line install:
#       curl -sSL https://borademircan.com/mira/install.sh | bash
#
#   What this does:
#     1. Clones github.com/borademircan/mip into ./mira (or $MIRA_DIR)
#     2. Ensures pnpm is available
#     3. Installs workspace dependencies
#     4. Prints the next two commands you run yourself
#
#   No sudo. No global modifications outside of `npm i -g pnpm` if
#   pnpm isn't already on your PATH. Bring your own Postgres and AI
#   provider (or local LLM); see the printed instructions.
#

set -euo pipefail

REPO="https://github.com/borademircan/mip.git"
DIR="${MIRA_DIR:-mira}"

# ── tiny color helpers (gracefully no-op when stdout isn't a tty) ──
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_CYAN=$'\033[36m'; C_MAG=$'\033[35m'; C_LIME=$'\033[92m'
  C_DIM=$'\033[2m';   C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_CYAN=""; C_MAG=""; C_LIME=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

say()  { printf "%s%s%s\n" "$C_CYAN" "$1" "$C_RESET"; }
ok()   { printf "%s✓%s %s\n" "$C_LIME" "$C_RESET" "$1"; }
warn() { printf "%s!%s %s\n" "$C_MAG" "$C_RESET" "$1"; }
die()  { printf "%s✗%s %s\n" $'\033[31m' "$C_RESET" "$1" >&2; exit 1; }

# ── banner ───────────────────────────────────────────────────────────
printf "\n"
printf "  %s▲ MIRA%s   %s— your interface mirror%s\n" "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
printf "  %sa two-column conversation with AI · MIP + MCP%s\n" "$C_DIM" "$C_RESET"
printf "\n"

# ── prereqs ──────────────────────────────────────────────────────────
say "→ Checking prerequisites…"
command -v git  >/dev/null || die "git is required. Install it first."
command -v node >/dev/null || die "Node.js is required (>= 20). https://nodejs.org"

if ! command -v pnpm >/dev/null; then
  warn "pnpm not found — installing via corepack (or npm i -g pnpm fallback)"
  if command -v corepack >/dev/null; then
    corepack enable && corepack prepare pnpm@latest --activate
  else
    npm install -g pnpm
  fi
fi
ok "git, node $(node --version), pnpm $(pnpm --version)"

# ── clone ────────────────────────────────────────────────────────────
say "→ Cloning Mira into ./$DIR…"
if [ -e "$DIR" ]; then
  die "Directory '$DIR' already exists. Move it aside or set MIRA_DIR=other-name."
fi
git clone --depth 1 "$REPO" "$DIR" >/dev/null 2>&1
ok "cloned $REPO"

# ── install ──────────────────────────────────────────────────────────
say "→ Installing workspace dependencies (this can take a minute)…"
cd "$DIR"
pnpm install --silent
ok "dependencies installed"

# ── next steps ───────────────────────────────────────────────────────
printf "\n"
printf "  %sReady.%s Two more steps you run yourself:\n" "$C_LIME" "$C_RESET"
printf "\n"
printf "  %s# 1. start the Hono data proxy on :8787%s\n" "$C_DIM" "$C_RESET"
printf "  %scd %s && pnpm --filter @mip/data-proxy dev%s\n" "$C_CYAN" "$DIR" "$C_RESET"
printf "\n"
printf "  %s# 2. in another terminal, start the Vite frontend on :5173%s\n" "$C_DIM" "$C_RESET"
printf "  %scd %s && pnpm --filter @mip/dashboard-react dev%s\n" "$C_CYAN" "$DIR" "$C_RESET"
printf "\n"
printf "  %sThen open the URL Vite prints and add an AI provider via Connections.%s\n" "$C_DIM" "$C_RESET"
printf "  %sLocal-first: point Mira at a 16–31B open model (Qwen, Llama, DeepSeek)%s\n" "$C_DIM" "$C_RESET"
printf "  %sserved via Ollama / vLLM / LM Studio — no tokens leave your machine.%s\n" "$C_DIM" "$C_RESET"
printf "\n"
printf "  %sDocs · roadmap · architecture decisions:%s\n" "$C_DIM" "$C_RESET"
printf "  %shttps://github.com/borademircan/mip%s\n" "$C_MAG" "$C_RESET"
printf "  %shttps://borademircan.com/mira%s\n" "$C_MAG" "$C_RESET"
printf "\n"
