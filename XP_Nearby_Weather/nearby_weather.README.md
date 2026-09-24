# Nearby METAR & Time (X-Plane 12 / FlyWithLua)

One key opens a small X-Plane window: the METAR of the three nearest usable
airports, plus the time zone you are flying in and the Zulu (GMT) and local
clock. Everything comes from inside the simulator -- no weather website, no
internet request, no external data file.

- **Script:** `nearby_weather.lua`
- **Platform:** X-Plane 12 + FlyWithLua NG+ (**2.8.x**, the build with ImGui
  floating windows); older FlyWithLua builds say so in the log
- **Hotkey:** `FlyWithLua/nearby_weather/toggle` -- you bind the key yourself
- **The window:** a real X-Plane floating window: X-Plane draws its frame and
  title bar, drag it with the mouse, resize it by its edges, close it with the
  cross (or press your key again)
- **Reads:** `XPLMGetMETARForAirport`, `apt.dat`, `sim/time/*`
- **Writes:** nothing at all

## What the window shows

```
Nearby METAR & Time                                     _  X     <- X-Plane title bar
────────────────────────────────────────────────────────────────
NEARBY METAR & TIME
KSEA  Seattle-Tacoma Intl                        0.0 NM  000
VFR   241953Z 18005KT 10SM FEW020 SCT250 18/12 A3012 RMK AO2 SLP132
      5 min ago    RWY 11,892 ft asphalt    elev 433 ft
KBFI  Boeing Field King Co Intl                  4.8 NM  005
MVFR  241953Z 20008KT 4SM BR BKN012 OVC025 12/10 A3005
      5 min ago    RWY 9,995 ft asphalt    elev 21 ft
KS50  Auburn Muni                                7.0 NM  211
LIFR  241953Z 00000KT 1/2SM FG VV002 08/08 A3000
      5 min ago    RWY 3,903 ft concrete    elev 20 ft
Zulu (UTC)  19:58:03Z
Local       11:58:03
Zone        UTC-08:00  US Pacific
```

- **Flight category** (VFR green / MVFR blue / IFR red / LIFR magenta) is
  decoded from visibility and ceiling with the usual thresholds, so a glance
  tells you whether the field is worth planning for. `SPECI` reports say so.
- **Age** is how long ago the report was issued, compared with the simulator's
  own clock. `ahead of clock` means you moved the sim time into the past while
  Real Weather is on; `stale` means the station stopped updating.
- **Distance and bearing** are great-circle values from your present position.
- Long remarks wrap onto a second line instead of running out of the window.

## Size and readability

X-Plane's plugin windows are measured in *boxels* (device independent pixels),
so the same font size that is comfortable on a laptop is unreadable on a 4K
screen. The script therefore scales the whole panel -- text, padding and window
size -- with the height of your display:

| Display height | Scale | Window | Base text |
|---|---|---|---|
| 1080p | 1.25 | 750 x 425 | ~16 px |
| 1440p | 1.44 | 864 x 490 | ~19 px |
| 4K | 2.16 | 1296 x 734 | ~28 px |

Want it bigger or smaller anyway? Set `text_scale` in the settings block at the
top of the script (e.g. `text_scale = 1.8`), or resize the window with the
mouse -- the content re-flows to the new width.

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
| `FlyWithLua/nearby_weather/toggle` | the key you want -- show/hide the window |

There is also a Plugins menu entry, *FlyWithLua → Nearby METAR & time:
show/hide*, and a macro named the same. X-Plane gives plugins no API to bind a
key on their behalf, so this is a one-time manual binding; it is stored with
your other key assignments and survives updates and reloads.

## Tuning

Everything lives in the `CFG` block at the top of the script.

```lua
local CFG = {
    window_width   = 600,     -- logical size; multiplied by text_scale
    window_height  = 340,
    margin_left    = 30,      -- where it appears: from the left screen edge
    margin_top     = 30,      -- ... and from the top edge
    text_scale     = 0,       -- 0 = automatic for your display, or e.g. 1.8
    start_visible  = false,   -- false: hidden until you press your key
    resizable      = true,

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
- **Text still too small on your screen?** Set `text_scale = 2.0` (or higher);
  the window grows with it. You can also just drag the window edges.
- **Only big airports?** Raise `min_paved_runway_ft` (e.g. `6000`).
- **Hate false positives from odd little fields?** Keep `require_icao_code`
  true and raise the runway minimum; the METAR requirement already removes
  everything that does not report weather.
- **Want airports further out?** Raise `search_radius_nm` and `candidate_limit`.
- **The panel text is English on purpose**: X-Plane's plugin fonts have no CJK
  glyphs, so Chinese strings would render as blanks.

## Background cost

apt.dat is roughly a million lines. It is read once per X-Plane session in
small slices inside the flight loop (default: at most 4,000 lines *and* 4 ms of
CPU per frame), so it costs a few seconds of spread-out work and never stalls a
frame. If you open the window before the scan finishes, the header shows
`scanning airports 42%` and the list fills in as soon as it is ready.

The parsed list is cached in a global, so loading a different aircraft or
airport -- which makes FlyWithLua re-run every script -- does not read apt.dat
again, and the open window is re-used instead of being duplicated. Set
`scan_on_load = false` if you would rather pay the scan cost only when you
first open the window.

## Honest limits

- **Needs FlyWithLua NG+ 2.8.x.** The window is an ImGui floating window; a
  FlyWithLua build without that support writes one line to the log and shows
  nothing, because there is no reliable way to draw a panel in X-Plane 12
  without it.
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
- **The window position lives for one session.** Hide and show keeps the place
  you dragged it to (as long as X-Plane is running); after restarting the sim
  it starts in the top left corner again.
- **Tested offline, not in the sim.** The script was developed and verified
  against a mock of the FlyWithLua API (see below); the author could not run it
  on a real X-Plane 12 installation while writing it.

## Verification

Since the author's machine has no X-Plane installation, the script was run
against a mocked FlyWithLua environment (a Lua VM with fake `float_wnd_*`
functions, a small ImGui layout engine that records every text item, a fake
FFI, and a synthetic apt.dat containing paved, grass, gravel, water, heliport,
seaplane and private strips). Around eighty assertions covered:

- filtering and distance ordering, including XP12 surface codes 24 and 53;
- METAR decoding: VFR/MVFR/IFR/LIFR, `10SM`/`P6SM`/`1/2SM`/`1 1/2SM`/`M1/4SM`,
  metric visibility (`8000`, `9999`), ceilings from `BKN`/`OVC`/`VV`, `CAVOK`,
  `SPECI` and missing reports;
- the time zone maths, including a UTC+8 rollover past midnight and a
  half-hour offset (UTC+05:30);
- the panel layout: every drawn string measured against the window, so nothing
  can overflow it, plus long RMK reports that must wrap;
- the window itself: created on the first key press, destroyed on the second,
  remembered position when shown again, closed by its cross, and *re-used*
  (not duplicated) when FlyWithLua reloads every script on an aircraft change;
- display scaling: 1080p, 1440p and 4K windows and text sizes;
- background loading: a 20,000-line file sliced over several frames with the
  progress line visible, then a complete panel;
- failure paths: no FFI, missing apt.dat, no floating window support in the
  FlyWithLua build, fewer than three airports.

What it cannot prove is how your installation behaves -- the exact apt.dat
layout of your X-Plane build, the METAR strings your weather mode downloads and
how ImGui renders on your GPU. If something looks off, set `debug = true` and
read `Resources/plugins/FlyWithLua/Log.txt`; the script logs what it read.

## Files

```
XP_Nearby_Weather/
  nearby_weather.lua                 the script
  nearby_weather.README.md           this file
  nearby_weather.README.zh-CN.md     中文说明
```
