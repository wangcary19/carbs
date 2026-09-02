# carbs

carbs is a macOS menu bar app that estimates your computer's carbon output for the day. It adds up two things:

- your Mac's electricity use, converted with the carbon intensity of your local grid
- your cloud AI usage, read from local agent transcripts (pi, Claude Code, Codex CLI)

Local models (Ollama, LM Studio) don't need separate accounting. Their energy is already inside your Mac's power draw, so carbs just notes that they're installed.

The menu bar shows a running total for today:

```text
CO₂ 142g
```

Click it for the breakdown. It's a meter, not a coach: no goals, no nudges, one weekly graph.

## Requirements

- macOS 13 or later
- A Swift toolchain (Xcode or Command Line Tools)
- Optional: a free [Electricity Maps](https://www.electricitymaps.com/) API token for live grid data

## Build and run

```sh
git clone https://github.com/wangcary19/carbs.git
cd carbs
Scripts/bundle.sh
open Carbs.app
```

`swift run carbs` works for development. Day to day you want the bundled app: it's menu-bar only (no dock icon) and can ask for location permission.

## Setup

You don't have to configure anything. Without a token, carbs estimates your grid's carbon intensity from bundled regional averages (see below) and tracks everything else the same way.

For live grid data:

1. Sign up for a free personal token at Electricity Maps (one zone, hourly updates).
2. Open the dropdown → Settings → paste the token → Save Token.
3. Allow location access once when asked, or set your zone by hand in `~/.carbs/config.json`:

```json
"grid": { "provider": "electricitymaps", "zone": "US-CAL-CISO", "use_location": true, "token": "..." }
```

Settings also has the menu bar icon (default `CO₂`), launch at login, a config folder shortcut, CSV export, and reset totals.

## What you'll see

- **Dropdown** — today's total, device vs. models split, which grid source is in use, which agents were detected, week and month totals.
- **Stats** — a Screen Time-style graph of the past week (device and models stacked, daily average line).
- **Menu bar** — today's running total next to your icon.

## How grid intensity works

Live data is nice to have, not required. carbs picks the best available source in this order:

| Tier | Source | Needs | Label in dropdown |
| --- | --- | --- | --- |
| 1. Live | Electricity Maps, hourly | free personal token | `238 g/kWh (CA-ON · gps)` |
| 2. Live, no key | [NESO](https://carbonintensity.org.uk), GB only, half-hourly | zone = GB | `170 g/kWh (GB · region)` |
| 3. Estimate | Bundled averages: US states (EPA eGRID), Canadian provinces (ECCC), national elsewhere (Ember) | a resolved zone | `~230 g/kWh (US-CA · gps · estimate)` |
| 4. Estimate | Global fallback (default 400, editable) | nothing | `~400 g/kWh (global avg · estimate)` |

Zone resolution order: manual config → one-shot GPS → Mac region setting → tier 4. GPS has two modes: with a token, your coordinates go to Electricity Maps to resolve the zone; without one, macOS reverse-geocodes them on-device to your state or province and matches the bundled table. Either way, location is used once and never stored.

GB users get live data out of the box; tier 2 needs no account at all.

Estimates are honest placeholders. France runs ~50 g/kWh, West Virginia ~700, and anything from tiers 3–4 is shown with `~` and an `· estimate` tag.

## How agents are tracked

carbs watches known transcript locations and counts new token usage as it appears. Byte offsets are persisted, so restarts never double-count.

| Agent | Location | Notes |
| --- | --- | --- |
| pi | `~/.pi/agent/sessions/**` | input + output + reasoning tokens |
| Claude Code | `~/.claude/projects/**` | field names per public transcript format |
| Codex CLI | `~/.codex/sessions/**` | per public rollout format; not yet exercised locally |
| Ollama / LM Studio | model dirs | display-only (energy already counted in device draw) |

Only token counts are read. Message contents are never stored or sent anywhere. Transcript formats change without notice; parsers skip anything they don't recognize rather than crashing.

Cloud tokens are converted with editable rough factors in `~/.carbs/config.json`:

```json
"model_factors_wh_per_1M_tokens": { "default": 1500, "light:*": 500, "heavy:*": 5000 }
```

Per-token energy is an active research debate, so treat the Models number as order-of-magnitude, not a measurement.

## Data and privacy

Everything lives in `~/.carbs/`: daily JSONL logs, byte offsets, the grid cache. No telemetry. The only network traffic is one GET per hour to your grid provider. Location coordinates are never written to disk.

## Releasing

Unsigned builds trip Gatekeeper on other Macs. To distribute you need an Apple Developer account ($99/yr), Developer ID Application and Installer certificates, and a notarization profile:

```sh
xcrun notarytool store-credentials "carbs-notary" \
  --apple-id you@example.com --team-id ABCDE12345 --password <app-specific-password>

Scripts/release.sh   # build → sign → notarize → staple → Carbs.zip + carbs-installer.pkg
```

Distribute the zip (drag to /Applications) or the pkg (installer wizard). Verify on another Mac with `spctl -a -vv Carbs.app`.

## Known limitations

- Plugged in with a full battery, the power reading undercounts (battery-rail amperage ≈ 0).
- The first time carbs sees a transcript, only new usage is counted; history is skipped.
- Browser-based chat (ChatGPT or Claude in a web tab) leaves no local trace, so it's invisible.
- The Codex parser follows the public format but hasn't been tested against a real install.
- Estimates are estimates. Live data replaces them as soon as a token is set.

See PLAN.md for the design doc and milestone history.
