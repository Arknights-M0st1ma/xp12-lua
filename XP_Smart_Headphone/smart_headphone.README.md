# Smart Headphone (X-Plane 12 / FlyWithLua)

A noise-cancelling headphone for the cockpit: hit one hotkey and the
low-frequency drone fades away, while ATC, voices and warnings stay crystal
clear -- the way a real ANR headset feels.

- **Script:** `smart_headphone.lua`
- **Platform:** X-Plane 12, FlyWithLua (X-Friese build, 2023+)
- **Hotkey:** `FlyWithLua/smart_headphone/toggle` -- you bind the key yourself
- **Writes:** `%APPDATA%\xplane_smart_headphone.state` (on/off + your volume mix)
- **Touches:** X-Plane's own sound-channel volumes. Nothing else.

## What it does, honestly

FlyWithLua has **no access to X-Plane's audio mixer or its sample stream**, so a
real low-frequency filter (biquad, high-pass, ...) cannot be patched into the
sim's sound output from Lua. What *is* available is X-Plane's own sound-channel
volumes -- the sliders in Settings → Sound -- and the engine drone lives in the
interior / exterior aircraft channels.

So the script reproduces what the headset **feels** like: the channels that
carry the drone fade down, the channels that carry information stay at full
volume.

| Sound channel | Dataref | While ANR is on |
|---|---|---|
| Interior aircraft (the drone in the cockpit) | `sim/operation/sound/interior_volume_ratio` | × 0.20 (−14 dB) |
| Exterior aircraft (the engine from outside) | `sim/operation/sound/exterior_volume_ratio` | × 0.15 (−16 dB) |
| Environment (wind / rain / airport rumble) | `sim/operation/sound/environment_volume_ratio` | × 0.50 (−6 dB) |
| Dedicated engine / prop channels, if your build has them | `.../engine_volume_ratio`, `.../prop_volume_ratio` | × 0.15 |
| Radio (ATC + voices), copilot, UI, master | — | untouched |

Those factors are config, not magic -- see **Tuning**.

## Install

1. Copy `smart_headphone.lua` into

   ```
   <X-Plane 12>/Resources/plugins/FlyWithLua/Scripts/
   ```

2. Plugins → FlyWithLua → **Reload all Lua scripts** (or restart X-Plane).

## Bind your hotkey

Settings → **Keyboard** (or **Joystick**), search **`smartheadphone`**:

| Command | Use it for |
|---|---|
| `FlyWithLua/smart_headphone/toggle` | the key you normally bind -- flip ANR on/off |
| `FlyWithLua/smart_headphone/on` | a dedicated "ANR on" button |
| `FlyWithLua/smart_headphone/off` | a dedicated "ANR off" button |
| `FlyWithLua/smart_headphone/reset` | escape hatch: full volume back, forget the mix |

X-Plane gives plugins **no API to bind a key on their behalf**, so this is a
one-time manual binding. It is saved with your other key assignments and
survives updates and reloads.

## Tuning

Everything you might want to change is in the `CONFIG` block at the top of the
script.

```lua
local FADE_SECS = 0.8      -- set 0 for an instant snap
local SHOW_TOAST = true    -- brief "ANR on / off" message on screen

local CHANNELS = {
    { path = "sim/operation/sound/interior_volume_ratio",    factor = 0.20 },
    { path = "sim/operation/sound/exterior_volume_ratio",    factor = 0.15 },
    { path = "sim/operation/sound/environment_volume_ratio", factor = 0.50 },
    ...
}
```

`factor` is how much of that channel survives while ANR is on:

| factor | 0.5 | 0.25 | 0.15 | 0.10 | 0.05 |
|---|---|---|---|---|---|
| cut | −6 dB | −12 dB | −16 dB | −20 dB | −26 dB |

- **Deeper silence:** lower the factors (0.10 ≈ real-headset levels).
- **Switch a channel off:** set its factor to `1.0`.
- **Only the cockpit drone:** delete the exterior and environment rows.
- **Everything but ATC:** add `master_volume_ratio` at ~0.2. (Not recommended:
  it takes warning sounds with it.)

## The fine print

- **While ANR is on, the script owns those sliders.** Don't fight it from
  Settings → Sound: turn ANR off, change your mix, turn ANR on again -- the new
  mix becomes the baseline. It never re-asserts the level every frame, so a
  slider you move in the sim always wins.
- **Your mix is remembered, not reset.** If your interior volume was 0.9, ANR
  gives you 0.18 and hands 0.9 back afterwards -- it never assumes 1.0.
- **The state survives aircraft changes.** FlyWithLua reloads every script when
  you load an aircraft; the script saves "ANR on/off" plus your mix to
  `%APPDATA%\xplane_smart_headphone.state`, so a reload neither forgets ANR nor
  strands the sliders at the faded level (and never double-attenuates).
- **Nothing to write? It still works.** If `%APPDATA%` isn't writable the script
  falls back to session-only memory and says so in the log.
- **Stuck sound?** Run the `reset` command, or delete the state file. That puts
  the watched channels back to 1.0 and forgets the remembered mix.
- **Missing channels** are listed in the log with the reason (`not present` /
  `read-only`) and simply skipped -- a wrong dataref name never breaks the
  script. To see what your build really offers:

  ```
  findstr /i volume_ratio "<X-Plane 12>\Resources\plugins\DataRefs.txt"
  ```

  Add whatever you find to `CHANNELS`. The log lives in
  `Resources/plugins/FlyWithLua/FlyWithLua_debug.txt`.
- **Handling warnings** come from the aircraft's own systems (many write the
  `interior` channel), so a very deep interior cut can make a GPWS call quieter.
  Combine with the EQ approach below if you want the drone gone but the warnings
  pinned.

## Genuine low-frequency filtering (the real thing)

If you want actual low-frequency *energy* removed rather than a channel mix
change, that has to happen to the Windows audio output, outside X-Plane:

- **[Equalizer APO](https://sourceforge.net/projects/equalizerapo/)** (+ Peace
  GUI) on your output device: put a high-pass or a low-shelf around 80–150 Hz
  and the drone really disappears -- for **all** sim audio.
- **Voicemeeter** with a VST/graphic EQ does the same and can be toggled with
  its own hotkey while flying.

Trade-off: an EQ filters everything, so it cannot tell engine drone from radio
speech -- cut deep and ATC goes muddy. `smart_headphone` is the complement: it
keeps the *information* channels at full level while dropping the drone. Both
together is the pragmatic best of both worlds.

## Why this design (decisions log)

- **Why not a real filter?** Lua has no access to the mixer or the audio
  stream; the only sound datarefs X-Plane exposes are volume ratios. Anything
  more needs a compiled plugin *and* still no hook into FMOD's output -- hence
  the system-EQ route above.
- **Why interior/exterior instead of master?** Master takes ATC and warnings
  with it. The ANR metaphor is "noise gone, information kept".
- **Why a fade and not a snap?** Real headsets ramp. 0.8 s with an ease-out
  reads as "the headphones settling in" instead of a glitch. `FADE_SECS = 0`
  if you disagree.
- **Why remember the user's mix?** Restoring to 1.0 would silently destroy a
  mix you had set. The script stores the level it found and gives it back --
  and a channel that already sits at our own faded level is recognised, so a
  reload cannot latch the faded value as the new baseline.
- **Why a state file?** Without one, FlyWithLua's reload-on-aircraft-load would
  leave the sliders faded while the script believed ANR was off. That is a
  user-visible bug, so it gets a file.
- **Why probe the datarefs at runtime?** A wrong name must degrade into a log
  line, not a script that fails to load. Both the low-level XPLM API
  (`XPLMFindDataRef` / `XPLMCanWriteDataRef`) and FlyWithLua's own `dataref()`
  binding are tried; read-only channels are skipped instead of erroring on
  every frame.
- **Why does the toggle latch instead of just debouncing?** Which
  `create_command` callback slot fires on press, and which one fires on every
  frame while the key is held, differs between FlyWithLua builds. A plain
  debounce would toggle *again* as soon as you held the key past the window.
  So the toggle latches instead: once it has fired it stays disarmed until the
  command has been quiet for 0.4 s -- a press, a long hold and key auto-repeat
  all mean exactly one toggle.
- **No hold-to-listen ("talk-through")**: that would need the hold-callback
  semantics that vary between builds. Left out rather than shipped flaky.

## Verification

The script's logic was exercised offline against a stubbed FlyWithLua / X-Plane
API (`texlua`, no sim required): 37 checks covering the fade curve, the
remembered-mix maths, the reload-with-ANR-on path, a pressed-and-held key,
read-only and missing datarefs, the `reset` escape hatch, and a machine where
nothing is writable -- in **both** dataref-binding modes.

What that cannot prove is the naming of X-Plane's own datarefs on your build
(none of this was tested against a real X-Plane install). That is exactly why
the channels are probed at load and the result is written to the log: if your
build names a channel differently, the log says so and `CHANNELS` is one edit
away.

## Files

```
Scripts/
  smart_headphone.lua                   the script
  smart_headphone.README.md             this file
  smart_headphone.README.zh-CN.md       the Chinese version

%APPDATA%\
  xplane_smart_headphone.state          on/off + your volume mix (the only file it writes)
```
