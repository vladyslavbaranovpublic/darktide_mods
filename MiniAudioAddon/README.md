# MiniAudioAddon

MiniAudioAddon is the shared Darktide helper that owns `miniaudio_dt.exe`. It launches and supervises the daemon, streams JSON payloads over the pipe/stdin bridge, exposes a registry-based Lua API, and ships in-game test commands so other mods can focus on *what* to play instead of *how* to talk to miniaudio.

---

## Requirements & File Layout

| Item | Notes |
| --- | --- |
| Darktide Local Server | Required. Provides process + filesystem helpers that MiniAudioAddon uses to launch / kill the daemon. |
| Load order | Put `MiniAudioAddon` after `DarktideLocalServer` and before any dependent mods. |
| Daemon files | Ship `Audio/bin/miniaudio_dt.exe` and `Audio/bin/miniaudio_dt.ctl` beside the addon (case-insensitive `audio/bin` is fine). If those files are missing the addon auto-creates a `.ctl` and searches `mods/Audio/bin` as a fallback. |
| Options | Enable **Spatial Mode** in the mod options page for any JSON/pipe communication. Toggle **Debug logging** + **Debug spheres** to control the on-screen helpers, pick a default rolloff/occlusion, and adjust the new **Distance scale** slider if you want builtin tests to stay audible farther away. |

When the addon launches the daemon, it changes the working directory to `MiniAudioAddon/audio/bin`, so every log (`miniaudio_dt_log.txt`, `miniaudio_dt_last_play.json`, staged payloads) stays in that folder.

---

## Capabilities

1. **Daemon lifecycle helpers**: `/miniaudio_*` commands and Lua helpers (`daemon_start/stop/update`) launch, monitor, and shut down the helper process.
2. **`MiniAudioAddon.api`**: a registry that tracks all active tracks (id/process, looping, speed, reverse, state, timestamps) and exposes transport operations (play, update, stop, pause, resume, seek, skip, speed, reverse, shutdown, status).
3. **Client tracking**: `MiniAudioAddon:set_client_active(mod_name, has_active_tracks)` keeps the daemon alive while any mod is playing.
4. **Watcher callbacks**: `MiniAudioAddon:on_generation_reset(cb)` and `:on_daemon_reset(cb)` let clients tear down their own state when the helper restarts.
5. **Testing harness**: `/miniaudio_test_play`, `/miniaudio_emit_start`, `/miniaudio_spatial_test`, and the bundled `/miniaudio_simple_*` commands ensure new builds can be validated in seconds.
6. **Diagnostics**: `Audio/bin/miniaudio_dt_log.txt` is always written, and the addon logs every payload when debug mode is on. Watchdog logic restarts the daemon when it disappears.
7. **Tunable defaults**: Mod options expose a debug-sphere toggle and a distance-scale slider so you can visualize emitters (or hide them) and expand/shrink how far the stock profiles carry without rewriting payloads.

Full QA walkthroughs (covering CLI, simple commands, spatial tests, and transport exercises) live in [`TESTING.md`](TESTING.md).

---

## Quick Start (Lua)

```lua
local MiniAudio = get_mod("MiniAudioAddon")
local api = MiniAudio.api -- registry helper

api.enable_logging(MiniAudio:get("miniaudioaddon_debug"))

-- Start a looping ambience that follows the player.
api.play({
    id = "mymod_ambience",
    path = "mods/MyMod/audio/ambience_fan.mp3",
    loop = true,
    volume = 0.6,
    process_id = Application.guid() or Managers.player:local_player_id(1),
    profile = { min_distance = 1, max_distance = 25, rolloff = "linear" },
    listener = api.build_listener and api.build_listener() or nil, -- optional manual listener override
})

-- Later updates (e.g. fades or spatial adjustments)
api.update({
    id = "mymod_ambience",
    volume = 0.35,
    source = {
        position = { 4, -2, 3 },
        forward = { 0, 1, 0 },
        velocity = { 0, 0, 0 },
    },
})

-- Transport controls
api.pause("mymod_ambience")
api.seek("mymod_ambience", 45) -- jump to 45s mark
api.speed("mymod_ambience", 0.8)
api.resume("mymod_ambience")

-- Cleanup
api.stop("mymod_ambience", { fade = 0.5 })
api.remove("mymod_ambience")
```

Each call returns `true, entry` (or `false, reason`). The entries stored inside the registry include `id`, `path`, `process_id`, `state`, `loop`, `volume`, `speed`, `reverse`, `created`, `updated`, plus any spatial/effects snapshot. Use `api.status()` to inspect them from other mods or debug consoles.

---

## API Reference

### `MiniAudioAddon.api` Registry

| Function | Description |
| --- | --- |
| `enable_logging(boolean)` | Adds `[MiniAudioAPI] …` entries for every command. |
| `play(table spec)` | Create or replace a track. Recognised fields: `id?`, `path`, `loop?`, `volume?`, `profile?`, `source?`, `listener?`, `effects?`, `process_id?`, `start_seconds?`, `seek_seconds?`, `skip_seconds?`, `speed?`, `reverse?`, `autoplay?`. |
| `update(table spec)` | Modify existing track properties (volume/profile/source/listener/effects/seek/skip/speed/reverse). |
| `stop(id, opts?)` | Stop a single track (optional `opts.fade`). |
| `stop_all(opts?)` | Stop every track in the registry. |
| `stop_process(process_id, opts?)` | Stop only tracks that belong to the given process/owner. |
| `pause(id)` / `resume(id)` | Toggle transport state without destroying the sound. |
| `seek(id, seconds)` | Absolute seek in seconds (clamped to the sound length). |
| `skip(id, seconds)` | Relative seek (positive/negative). |
| `speed(id, multiplier)` | Playback speed (0.125–4.0). |
| `reverse(id, bool)` | Toggle the reverse flag (stored in the registry and forwarded to the daemon once native support is available). |
| `shutdown_daemon()` | Emit `{ "cmd": "shutdown" }` to terminate the helper cleanly. |
| `remove(id)` | Drop a track from the registry (useful when the daemon reports the track finished). |
| `status(filter?)` | Return a single track (`filter.id`), tracks for a process (`filter.process_id`), or a list of all tracks. |
| `tracks_count()` / `has_track(id)` | Introspection helpers. |
| `set_track_state(id, state)` | Manually override the stored `state` string (e.g. `"playing"`, `"paused"`, `"finished"`). |
| `clear_finished(timeout_seconds?)` | Remove entries marked `"finished"`/`"stopped"` after an optional timeout. |

### Classic helpers (for low-level payload tinkering)

```lua
MiniAudio:daemon_start(path?, volume?, pan?)
MiniAudio:daemon_stop()
MiniAudio:daemon_update(volume, pan)
MiniAudio:daemon_send_play(payload)
MiniAudio:daemon_send_update(payload)
MiniAudio:daemon_send_stop(id, fade?)
MiniAudio:daemon_send_pause(id)
MiniAudio:daemon_send_resume(id)
MiniAudio:daemon_send_seek(id, seconds)
MiniAudio:daemon_send_skip(id, seconds)
MiniAudio:daemon_send_speed(id, multiplier)
MiniAudio:daemon_send_reverse(id, bool)
MiniAudio:daemon_manual_control(volume, pan)
MiniAudio:is_daemon_running()
MiniAudio:get_pipe_name()
MiniAudio:set_client_active(mod_name, has_active_tracks)
MiniAudio:on_generation_reset(function(generation, reason) ... end)
MiniAudio:on_daemon_reset(function(reason) ... end)
```

The `MiniAudioAddon.api` layer calls these primitives under the hood; prefer the registry unless you require bespoke payload manipulation.

---

## Debug & Test Commands (in-game)

> All JSON-powered commands require **Spatial Mode** to be enabled. Keep the **Debug spheres** option on if you want wireframe markers & labels, and tweak the **Distance scale** slider (defaults to 1.0×, raise it only if you want extended falloff) when you need the builtin tests to fire up closer/farther than stock.

- `/miniaudio_simple_play [mp3|wav]` – play bundled sample (`Audio/test/Free_Test_Data_*.mp3|wav`); `/miniaudio_simple_stop` halts simple playback + emitters.
- `/miniaudio_simple_emit [distance] [mp3|wav]` – spawn the debug cube at `distance` meters with the sample track.
- `/miniaudio_simple_spatial <orbit|direction|follow|loop|spin> [mp3|wav]` – run spatial harness modes using the samples.
- `/miniaudio_test_play <path>` / `/miniaudio_test_stop`
- `/miniaudio_emit_start <path> [distance]` / `/miniaudio_emit_stop`
- `/miniaudio_spatial_test <orbit|direction|follow|loop|spin|stop> …`
- `/miniaudio_volume <value>` / `/miniaudio_pan <value>` / `/miniaudio_manual_clear`
- `/miniaudio_cleanup_payloads` – purge any staged payload/control files beside the daemon.

CLI validation (outside the game):

```powershell
cd "...\mods\MiniAudioAddon\audio\bin"
.\miniaudio_dt.exe --daemon --log --stdin --control ".\miniaudio_dt.ctl" --pipe cli_test -volume 100
# in another shell:
.\miniaudio_dt.exe --pipe-client --pipe cli_test --payload-file "C:\path\to\play.json"
```

For complete regression scripts covering volume sweeps, transport controls, spatial loops, CLI payloads, and troubleshooting steps, open [`TESTING.md`](TESTING.md).

---

## Troubleshooting Checklist

- `taskkill /f /im miniaudio_dt.exe` before launching Darktide if you suspect a stale daemon.
- Enable debug logging and review `MiniAudioAddon/audio/bin/miniaudio_dt_log.txt` to see backend errors (device busy, channel layout unsupported, etc.).
- `/miniaudio_simple_play wav` is the quickest sanity check—it proves the daemon can launch and stream the bundled sample.
- Use `MiniAudio:on_daemon_reset(function(reason) … end)` to clear your own state when the watchdog restarts the helper.
- If you need to inspect raw payloads, read `Audio/bin/miniaudio_dt_last_play.json`.

Need exact command sequences for QA? See [`TESTING.md`](TESTING.md).
