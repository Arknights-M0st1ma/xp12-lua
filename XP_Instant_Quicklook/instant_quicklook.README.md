# Instant Quick-Looks (X-Plane 12 / FlyWithLua)

Make "Go to saved 3-D cockpit location" **snap instantly** instead of gliding.

- **Script:** `instant_quicklook.lua`  (recall only -- saving stays X-Plane's own)
- **Storage:** X-Plane's own `<aircraft>_prefs.txt` (in the aircraft folder). The
  script keeps no file of its own; it only **reads** the saved views.
- **Platform:** X-Plane 12, FlyWithLua (X-Friese build, 2023+)

## How it works

- **Save** with X-Plane as usual (Ctrl+Numpad / the stock `quick_look_N_mem`
  bindings). The script does **not** save.
- **Recall** (`FlyWithLua/quicklook/recall_N`): jumps instantly to saved view N.
  It reads the pose from `<aircraft>_prefs.txt` and writes `pilots_head_x/y/z`
  and `pilots_head_psi/the` directly -- a direct write does not ease.

Restores **head position + look angle**, instantly. Command N maps to X-Plane
"location #N" = stock slot (N-1).

## How to use

1. Reload scripts: Plugins → FlyWithLua → **Reload all Lua scripts** (or restart).
2. Settings → Keyboard / Joystick, search **`quicklook`** — you'll find 20 commands
   `FlyWithLua/quicklook/recall_1..20`.
3. Bind your view keys to `recall_N` **instead of** `sim/view/quick_look_(N-1)`.
   Keep saving views the normal X-Plane way.

## Zoom

The cockpit zoom is X-Plane's internal `zoom_rat`. Testing confirmed it is
**neither readable nor writable** as a dataref, and the global FOV datarefs
(`field_of_view_deg` / `vertical_field_of_view_deg`) are the **global graphics
setting** (writing them resets your global/vertical FOV) -- so zoom cannot be set
directly from Lua.

Default: zoom is left untouched (fully instant position + angle).

For the **few views that need a specific zoom**, list them in `ZOOM_SLOTS` at the
top of the script, e.g. `local ZOOM_SLOTS = { [2] = true }`. For those slots,
recall:

1. fires the **stock** `sim/view/quick_look_(N-1)`, which restores that view's zoom
   (and pos/angle) **natively** -- gliding over ~0.5s; then
2. overrides `pilots_head_*` every frame for `OVERRIDE_SECS` (~0.7s), so position +
   angle **snap instantly** while only the zoom glides to target.

This keeps all native camera physics/effects (no camera takeover). Zoom is not
instant on those slots -- it eases in ~0.5s like a stock quick-look. Truly-instant
zoom would need the C/`XPLMControlCamera` route (which loses native physics).

If position/angle still glide on a `ZOOM_SLOTS` view, the per-frame override
(`instant_quicklook_hold`) is losing the timing race; try moving it to
`do_every_draw` or increasing `OVERRIDE_SECS`.

### Tip: one shared zoom, the data-side way

If you just want all views at one zoom level, edit `<aircraft>_prefs.txt` (with
X-Plane closed) and set every `_iql_zoom_rat_N` to the same value (e.g. copy the
one from your favourite view). Then no `ZOOM_SLOTS` glide is needed at all -- every
view is already at that zoom. (Re-saving a view in-sim afterward overwrites its
zoom again.)

## The problem / the trick

`sim/view/quick_look_0..19` ("Go to saved 3-D cockpit location #1..20") **ease**
the camera over ~0.5s, and there is **no native setting or dataref** to disable
that (confirmed by grepping `Resources/plugins/DataRefs.txt` + `Commands.txt` and
by web search). But the 3-D cockpit pose **is** writable:

| Dataref | Meaning |
|---|---|
| `sim/graphics/view/pilots_head_x` / `_y` / `_z` | head position vs CG (m) |
| `sim/graphics/view/pilots_head_psi` / `_the` | heading / pitch (deg) |

Writing them moves the camera instantly. Recall fires
`sim/view/3d_cockpit_cmnd_look` first to ensure the 3-D cockpit, then snaps the
pose. (Roll isn't used -- quick-looks don't store it.)

## Why this design (decisions log)

- **Why not just disable the animation?** No native switch exists (see above).
- **Why our own `recall_N` instead of intercepting the stock command?** This
  FlyWithLua build **cannot** hook existing commands -- verified by scanning
  `win_x64/FlyWithLua.xpl`: no `replace_command` / `wrap_command`. So the key must
  point at our own command, which means rebinding the recall keys.
- **Why not save from the script too?** Earlier versions wrapped the stock save to
  add an on-screen confirmation; removed as unused. Saving is left entirely to
  X-Plane, which is the single source of truth.
- **Why FlyWithLua over a compiled plugin?** Update-resilient (a fix is a text edit
  + reload, never a recompile) and zero steady-state cost. Trade-off: you rebind
  the recall keys.

## Known caveats

- **Flush timing:** X-Plane may only write `_prefs.txt` on aircraft-change / exit,
  not on every save. So a view you save **this session** may not be readable by
  recall until the file is flushed (reload aircraft / restart). Views from earlier
  sessions work fine.
- **Zoom:** not restored except for `ZOOM_SLOTS` (see Zoom). We never write the
  global FOV datarefs, so your custom/vertical FOV is never disturbed.
- **External-view slots:** only 3-D cockpit views (`v_3dc`) are restored as
  intended; orbit/external slots aren't handled.

## If we ever go the C route (future)

A compiled plugin using `XPLMControlCamera` could do instant position + angle +
**zoom**, the way X-Camera / A Better Camera do. Cost: an X-Plane SDK + C toolchain
(you have VS2019; the SDK would need downloading), and every fix is a rebuild.
A full takeover also loses native physics/head-shake/look-around unless
reimplemented -- which is why we stayed in Lua.

## Files

```
Scripts/
  instant_quicklook.lua                 the script
  instant_quicklook.README.md           this file

<aircraft folder>/                      e.g. Aircraft/.../FlightFactor 777.../
  <aircraft>_prefs.txt                  X-Plane's OWN prefs (we only READ it)
```

## X-Plane's native quick-look storage (reference)

Per slot N (0..19) in `<aircraft>_prefs.txt`:

```
_iql_view_type_N   v_3dc        view type (3-D cockpit)
_iql_pe_x_N/_y_N/_z_N           pilot-eye position   -> our pilots_head_x/y/z
_iql_look_os_psi_N/_the_N       look heading/pitch   -> our pilots_head_psi/the
_iql_zoom_rat_N                 zoom RATIO (multiplier, NOT degrees; not writable)
_iql_circ_psi/the/dis_N         orbit params (external views only)
_iql_pscroll_x/y_pix_N          2-D panel scroll position
```

## Reference datarefs/commands (XP12)

- `sim/view/quick_look_0..19` — stock "go to saved location" (animated)
- `sim/view/quick_look_0..19_mem` — stock "memorize" (use this to save)
- `sim/view/3d_cockpit_cmnd_look` — enter 3-D cockpit
- `sim/graphics/view/pilots_head_*` — the writable pose datarefs we snap
