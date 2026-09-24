# Nearby METAR & Time (X-Plane 12 / FlyWithLua)

One key, one small panel in the top left corner: the METAR of the three nearest
usable airports, plus the time zone you are flying in and the Zulu (GMT) and
local clock. Everything comes from inside the simulator -- no weather website,
no internet request, no external data file.

- **Script:** `nearby_weather.lua`
- **Platform:** X-Plane 12 + FlyWithLua NG (X-Friese build, 2023+)
- **Hotkey:** `FlyWithLua/nearby_weather/toggle` -- you bind the key yourself
- **Reads:** `XPLMGetMETARForAirport`, `apt.dat`, `sim/time/*` datarefs
- **Writes:** nothing at all

## What the panel shows

```
NEARBY METAR & TIME
────────────────────────────────────────────────────────────────
KSEA  Seattle-Tacoma Intl                        0.0 NM  000
VFR   241953Z 18005KT 10SM FEW020 SCT250 18/12 A3012     5 min
      RMK AO2 SLP132
      RWY 11,892 ft asphalt    elev 433 ft
────────────────────────────────────────────────────────────────
KBFI  Boeing Field King Co Intl                  4.8 NM  005
MVFR  241953Z 20008KT 4SM BR BKN012 OVC025 12/10 A3005    5 min
      RWY 9,995 ft asphalt    elev 21 ft
────────────────────────────────────────────────────────────────
KS50  Auburn Muni                                7.0 NM  211
LIFR  241953Z 00000KT 1/2SM FG VV002 08/08 A3000         5 min
      RWY 3,903 ft concrete    elev 20 ft
────────────────────────────────────────────────────────────────
Zulu (UTC)  19:58:03Z              Local   11:58:03
Zone        UTC-08:00  US Pacific
```

- **Flight category** (VFR green / MVFR blue / IFR red / LIFR magenta) is
  decoded from visibility and ceiling with the usual thresholds, so a glance
  tells you whether the field is worth planning for. `SPECI` reports say so.
- **Age** is how long ago the report was issued, compared with the simulator's
  own clock. `ahead of clock` means you moved the sim time into the past while
  Real Weather is on; `stale` means the station stopped updating.
- **Distance and bearing** are great-circle values from your present position.

## Where the data comes from

| Item | Source | Notes |
|---|---|---|
| METAR text | `XPLMGetMETARForAirport(ICAO)` | X-Plane's own last downloaded report -- the same data its Real Weather mode is built from |
| Nearest airports | `Resources/default scenery/default apt dat/Earth nav data/apt.dat` | X-Plane's airport database (apt.dat 12.00), streamed in the background |
| Runway surface/length | same apt.dat, runway rows | used for the filtering below |
| Zulu / local time | `sim/time/zulu_time_sec`, `sim/time/local_time_sec` | the time zone is derived from the difference of the two |

`XPLMGetMETARForAirport` is a C API, so the script calls it through the LuaJIT
FFI that ships with FlyWithLua NG (`XPLM_64` / `XPLM_64.so` /
`XPLM.framework`). Nothing is downloaded; the panel only ever *reads* the
weather X-Plane has already fetched. If FlyWithLua's FFI is unavailable the
panel says `METAR source unavailable` and keeps showing everything else.

**Real Weather must have been used at least once in the session.** In static
weather mode X-Plane has no METAR to hand out and returns empty strings; the
panel then tells you `no METAR data (Real Weather off?)` instead of inventing
numbers. X-Plane's own documentation is explicit that a METAR is not the
simulated weather: the sim blends the point report with a regional forecast, so
what you feel in the air will differ from the report you read here.

## Which airports are listed

Candidates come from the global airport database and are then filtered:

| Rule | Why |
|---|---|
| Land airport only (apt.dat row code 1) | heliports (17) and seaplane bases (16) are skipped outright |
| At least one **paved** runway | asphalt/concrete, including the apt.dat 12.00 shade codes 20-38 and 50-57; turf, dirt, gravel, dry lakebed, water and snow/ice fields are dropped |
| That runway is at least 2,000 ft long | keeps the list to fields you can realistically use |
| A 4-character ICAO-style code | the `icao_id` from row 1302 is preferred, the header ID is only a fallback; private strips with local identifiers are dropped |
| It actually reports a METAR | the ten nearest candidates are checked and the nearest ones *with* a report win; if fewer than three report, the remaining slots are filled with the nearest airports and marked `no METAR reported by X-Plane for this station` |

Every number above is a setting (see **Tuning**), and the panel names the exact
runway it used: `RWY 11,892 ft asphalt`.

## Install

1. Copy `nearby_weather.lua` into

   ```
   <X-Plane 12>/Resources/plugins/FlyWithLua/Scripts/
   ```

2. Plugins → FlyWithLua → **Reload all Lua scripts** (or restart X-Plane).

## Bind your hotkey

Settings → **Keyboard** (or **Joystick**), search **`nearby weather`**:

| Command | Use it for |
|---|---|
| `FlyWithLua/nearby_weather/toggle` | the key you want -- show/hide the panel |

There is also a Plugins menu entry, *FlyWithLua → Nearby METAR & time:
show/hide*, and a macro named the same. X-Plane gives plugins no API to bind a
key on their behalf, so this is a one-time manual binding; it is stored with
your other key assignments and survives updates and reloads.

## Tuning

Everything lives in the `CFG` block at the top of the script.

```lua
local CFG = {
    panel_width     = 560,     -- pixels
    margin_x        = 28,      -- from the left border
    margin_y        = 28,      -- from the top border
    start_visible   = false,   -- show it as soon as X-Plane loads?
    font            = "proportional",   -- or "helvetica18" on 4K displays

    airport_count        = 3,     -- how many airports to list
    min_paved_runway_ft  = 2000,  -- drop fields with nothing longer
    require_icao_code    = true,  -- 4-character codes only
    search_radius_nm     = 150,
    candidate_limit      = 10,    -- stations examined when looking for reports
    prefer_reporting     = true,

    scan_on_load         = true,  -- build the airport list right away
    scan_max_lines       = 4000,  -- apt.dat lines parsed per frame
    scan_budget_sec      = 0.004, -- ... and never more than this per frame
    repick_seconds       = 45,
    repick_distance_nm   = 20,
    metar_refresh_sec    = 300,
    zone_table           = true,
    debug                = false,
}
```

Common tweaks:

- **Want the panel open all the time?** `start_visible = true`.
- **Only big airports?** Raise `min_paved_runway_ft` (e.g. `6000`).
- **Hate false positives from odd little fields?** Keep `require_icao_code`
  true and raise the runway minimum; the METAR requirement already removes
  everything that does not report weather.
- **Want airports further out?** Raise `search_radius_nm` and `candidate_limit`.
- **On a 4K screen** the panel may look small, because plugin text does not
  scale with X-Plane's UI slider. Set `font = "helvetica18"` for a larger
  built-in font, and/or raise `panel_width`.
- **The panel text is English on purpose**: X-Plane's plugin fonts have no CJK
  glyphs, so Chinese strings would render as blanks.

## Background cost

apt.dat is roughly a million lines. It is read once per X-Plane session in
small slices inside the flight loop (default: at most 4,000 lines *and* 4 ms of
CPU per frame), so it costs a few seconds of spread-out work and never stalls a
frame. If you open the panel before the scan finishes, the header shows
`scanning airports 42%` and the list fills in as soon as it is ready.

The parsed list is cached in a global, so loading a different aircraft or
airport -- which makes FlyWithLua re-run every script -- does not read apt.dat
again. Set `scan_on_load = false` if you would rather pay that cost only when
you first open the panel.

## Honest limits

- **No METAR without Real Weather.** The report is whatever X-Plane last
  downloaded for that station, which can be an hour old; that is why the age is
  printed next to it.
- **Custom scenery airports matter.** Only FlyWithLua's default apt.dat is
  read. If a third-party scenery replaces an airport with a different runway
  set, the panel may describe the default version of it.
- **The region label is approximate.** `US Pacific`, `China`, `India` and
  friends come from a small built-in table of coarse boxes; a label is only
  shown when the simulator's own UTC offset matches the box, so it can never
  contradict the clocks. The offset itself is exactly what X-Plane uses. Set
  `zone_table = false` to show the offset only.
- **Tested offline, not in the sim.** The script was developed and verified
  against a mock of the FlyWithLua API (see below); the author could not run it
  on a real X-Plane 12 installation while writing it.

## Verification

Since the author's machine has no X-Plane installation, the script was run
against a mocked FlyWithLua environment (Lua VM + fake `draw_string`,
`measure_string`, `dataref`, `create_command`, GL calls and a fake FFI) with a
synthetic apt.dat containing paved, grass, gravel, water, heliport, seaplane
and private strips. About sixty assertions covered:

- filtering and distance ordering, including XP12 surface codes 24 and 53;
- METAR decoding: VFR/MVFR/IFR/LIFR, `10SM`/`P6SM`/`1/2SM`/`1 1/2SM`/`M1/4SM`,
  metric visibility (`8000`, `9999`), ceilings from `BKN`/`OVC`/`VV`, `CAVOK`,
  `SPECI`, missing reports, and reports whose time is ahead of the sim clock;
- the time zone maths, including a UTC+8 rollover past midnight and a
  half-hour offset (UTC+05:30);
- the panel layout: every drawn string measured against the panel rectangle, so
  nothing can overflow it, plus long RMK reports that must wrap;
- background loading: 20,000-line file sliced over several frames with the
  progress line visible, then a complete panel;
- failure paths: no FFI, missing apt.dat, fewer than three airports.

What it cannot prove is how your installation behaves -- the exact apt.dat
layout of your X-Plane build and the METAR strings your weather mode downloads.
If something looks off, set `debug = true` and read
`Resources/plugins/FlyWithLua/Log.txt`; the script logs what it read.

## Files

```
XP_Nearby_Weather/
  nearby_weather.lua                 the script
  nearby_weather.README.md           this file
  nearby_weather.README.zh-CN.md     中文说明
```
