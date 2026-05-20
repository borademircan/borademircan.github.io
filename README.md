# borademircan.com — Mira landing page

Single-file, zero-build landing page for [Mira](https://github.com/borademircan/mip) — the conversational AI surface built on the open Model Interface Protocol.

- **`index.html`** — the whole page (HTML + CSS + a touch of inline SVG). Open it directly in a browser to preview locally.
- **`assets/`** — the two hero screenshots (Mira visualizes / Mira explains).
- **`CNAME`** — custom-domain mapping to `borademircan.com`, picked up by GitHub Pages.

## Style

Cyberpunk dark — black background, cyan / magenta / violet accents, faint scan-lines, subtle grid, neon glows on the hero wordmark. Typography is Space Grotesk + JetBrains Mono via Google Fonts.

## Story arc

1. **Hero** — logo, wordmark, tagline, two-column screenshots (visualize + explain).
2. **The protocol** — sheet-music analogy + the 3-line MIP demo.
3. **The triangle** — SVG diagram of the three-participant feedback loop.
4. **The numbers** — three big stats + the full comparison table.
5. **The levels** — Mira·One → Mira·Eureka, with status badges.
6. **The tracks** — A/B/C/D capability tracks as a card grid.
7. **The research** — brush strokes vs. pixels.
8. **CTA** — GitHub + run-it-locally.

## Deploy

Hosted via GitHub Pages on the `main` branch. To point `borademircan.com` at it, set the following DNS records at your domain registrar:

```
A    @  185.199.108.153
A    @  185.199.109.153
A    @  185.199.110.153
A    @  185.199.111.153
AAAA @  2606:50c0:8000::153
AAAA @  2606:50c0:8001::153
AAAA @  2606:50c0:8002::153
AAAA @  2606:50c0:8003::153
CNAME www borademircan.github.io.
```

Then in the repo settings → Pages → enable HTTPS once GitHub finishes provisioning the cert (a few minutes after DNS resolves).
