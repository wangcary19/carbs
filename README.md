# 🌱 carbs

A dead-simple macOS menu-bar app that shows your **net carbon output (g CO₂e)** from two sources:

1. **Device** — your Mac's electricity use × live local grid carbon intensity
2. **Models** — your personal AI model usage, auto-detected by tailing local agent transcripts (cloud models). Local models (Ollama/LM Studio) need no accounting — their energy is already inside the device watt signal.

Display-only. No optimization, no nudges, no charts. Standalone app — **not** an extension of any agent.

```text
CO₂ 142g
```

(menu-bar icon is customizable in Settings — CO₂ is the default)

## Build & run

```sh
swift build                 # compile check
Scripts/bundle.sh           # produces Carbs.app (LSUIElement: menu-bar only)
open Carbs.app
```

Or run unpackaged during development: `swift run carbs` (location permission and menu-bar-only behavior require the bundled app).

## How it works

| Signal | Source | Cadence |
| --- | --- | --- |
| Device watts | IOKit `AppleSmartBattery` (Voltage × InstantAmperage). No sudo. | 60 s |
| Grid intensity | Priority chain: Electricity Maps (token) → NESO GB (keyless) → bundled zone average → global fallback | hourly, 6 h stale cache |
| Agent tokens | Poll-tail of `~/.pi/agent/sessions/**` (pi), `~/.claude/projects/**` (Claude Code), `~/.codex/sessions/**` (Codex CLI) with persisted byte offsets | 10 s |

**Zone resolution** (priority): manual `grid.zone` in config → CoreLocation one-shot → Mac region for single-zone countries → unresolved. Location is requested once and never stored. The GPS step has two modes: **with a token**, coords go to the Electricity Maps API, which resolves the zone server-side (live data); **without a token**, coords are reverse-geocoded *on-device* (CLGeocoder) to country + state/province and matched against the bundled estimate table (e.g. `US-CA`, `CA-ON`, `DE`) — no server call.

**Math:**

- `device_g = Σ kWh × grid_intensity(g/kWh)` — intensity follows the estimation chain below when no live data
- `model_g = tokens × wh_per_1M_tokens(model) / 1e6 × dc_intensity / 1000`
- Tokens counted: `input + output + reasoning` (+ cache tokens × `cache_token_weight`, default 0)

Model energy factors are **rough, editable placeholders** (per-token energy is an order-of-magnitude research debate, not a constant). Edit `~/.carbs/config.json`:

```json
{
  "dc_intensity_g_per_kwh": 350,
  "fallback_grid_intensity_g_per_kwh": 400,
  "cache_token_weight": 0.0,
  "grid": { "provider": "electricitymaps", "zone": "auto", "use_location": true, "token": "" },
  "model_factors_wh_per_1M_tokens": { "default": 1500, "light:*": 500, "heavy:*": 5000 }
}
```

Optional manual feed: append lines like
`{"ts":"2026-06-01T14:23:00Z","provider":"openai","model":"gpt-5.2","tokens_in":12000,"tokens_out":3400}`
to `~/.carbs/usage.jsonl` for anything without a watcher. Nothing depends on it.

Data lives in `~/.carbs/` (append-only daily JSONL, offsets, grid cache). No telemetry, no network beyond one GET/hour.

## Grid intensity without a token (estimation spec)

Live grid data is nice-to-have, not a requirement. The device stream always gets a
number, from this priority chain:

| Tier | Source | Needs | Dropdown label |
| --- | --- | --- | --- |
| 1. Live | Electricity Maps `/v3/carbon-intensity/latest` | free personal token (one zone, hourly) | `238 g/kWh (CA-ON · gps)` |
| 2. Live, keyless | [NESO Carbon Intensity API](https://carbonintensity.org.uk) — GB only, half-hourly, **no key, no registration** | zone = GB | `170 g/kWh (GB · region)` |
| 3. Estimate | Bundled annual averages (`StaticIntensity.swift`): US states (EPA eGRID), CA provinces/territories (ECCC), Europe + RoW national (Ember), rounded 2023–24 | a resolved zone/subdivision | `~230 g/kWh (US-CA · gps · estimate)` |
| 4. Estimate | `fallback_grid_intensity_g_per_kwh` (default 400, editable) | nothing | `~400 g/kWh (global avg · estimate)` |

Rules:

- **GB users get live data with zero setup** — with no EM token configured and zone = GB,
  carbs automatically uses the keyless NESO API.
- **State/province-level without a token**: allow location once and the on-device reverse
  geocode resolves your subdivision (`US-CA`, `CA-ON`, …) — Quebec (~10) and Alberta (~600)
  no longer share a number. Decline → national estimate for single-zone countries,
  global average otherwise.
- A stale live cache (6 h) still outranks estimates. Anything from tiers 3–4 is shown
  with `~` and an `· estimate` tag.
- Static averages are *order-of-magnitude honest* (France ~50 vs Poland ~700), same
  philosophy as the model energy factors — a token in `~/.carbs/config.json` replaces
  them with live data immediately.

The dropdown is display-only. Everything actionable lives in **Settings (⌘,)**: menu-bar icon, **Launch at Login** (SMAppService), Open Config Folder, **Export CSV…** (per-day device/model grams), Reset Totals.

## Distribution (why other Macs don't warn)

Apps downloaded from the internet carry the quarantine xattr. Gatekeeper opens them
without warnings only when they are **Developer ID signed + notarized + stapled**
(ad-hoc signing always warns on other machines). One-time setup:

1. Apple Developer Program membership ($99/yr)
2. Xcode → Settings → Accounts → Manage Certificates → **Developer ID Application** and **Developer ID Installer**
3. Store notarization credentials once:
   `xcrun notarytool store-credentials "carbs-notary" --apple-id you@example.com --team-id ABCDE12345 --password <app-specific-password>`

Then:

```sh
Scripts/release.sh   # build → sign → notarize → staple → Carbs.zip + carbs-installer.pkg
```

Distribute the **zip** (unzip → drag to /Applications; standard for menu-bar apps) or the
**pkg** (double-click installer wizard). Both are signed and notarized; the pkg variant is
built with `pkgbuild --component Carbs.app --install-location /Applications --sign "Developer ID Installer: …"`.
Verify on a fresh machine with `spctl -a -vv Carbs.app` → `accepted source=Notarized Developer ID`.

## Known limitations (v1)

- Battery-rail power undercounts when plugged in with a full battery (amperage ≈ 0)
- First sight of a transcript file skips its history (only new usage is counted)
- Browser-based chat (ChatGPT/Claude web) leaves no local trace — invisible
- Codex CLI parser written to the public rollout format but **unverified on the dev machine** (codex not installed); fails safe if the format differs
- Agent transcript formats drift; parsers are versioned and fail safe

Roadmap: Claude/Codex parser hardening against real transcripts, per-process attribution, embodied emissions. See `PLAN.md`.

Status vs PLAN.md milestones: M1–M5 code complete (launch-at-login ✅, CSV export ✅); notarized release pending an Apple Developer account — `Scripts/release.sh` automates it end-to-end.
