# MiniAudioAddon – Test Plan

This document is the definitive checklist for validating the daemon, API, and console commands. Run through these steps whenever you upgrade `miniaudio_dt.exe`, refactor the addon, or publish a mod that depends on it.

> **Notation** – replace `G:\SteamLibrary\…` with your actual install paths. Every command assumes **MiniAudioAddon spatial mode is enabled**.

---

## 0. Prerequisites

1. Ensure `Audio/bin/miniaudio_dt.exe` and `.ctl` exist under `mods/MiniAudioAddon/`.
2. Open the MiniAudioAddon mod options and verify:
   - **Spatial Mode** is enabled.
   - **Debug spheres** is ON if you want to see the helper cube/text (toggle OFF for clean captures).
   - **Distance scale** sits at your desired baseline (1.0 = legacy falloff; raise it above 1 only when you want to test extended attenuation).
3. Kill any leftover helper:
   ```powershell
   taskkill /f /im miniaudio_dt.exe 2>$null
   ```
4. Clear logs:
   ```powershell
   Remove-Item "mods\MiniAudioAddon\audio\bin\miniaudio_dt_log.txt" -ErrorAction Ignore
   ```

---

## 1. Command-line daemon smoke test (outside the game)

```powershell
cd "G:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\MiniAudioAddon\audio\bin"
\miniaudio_dt.exe --daemon --log --stdin --control ".\miniaudio_dt.ctl" --no-autoplay --pipe cli_test -volume 100
# let the daemon idle in this window
```

In another PowerShell window:

```powershell
$payload = @'
{"cmd":"play","id":"cli_demo","path":"..\test\Free_Test_Data_2MB_MP3.mp3","loop":false,"volume":1.0}
{"cmd":"stop","id":"cli_demo","fade":0.2}
'@
$payload | Out-File cli_payload.json -Encoding ascii
.\miniaudio_dt.exe --pipe-client --pipe cli_test --payload-file cli_payload.json
```

- **Expected**: audio plays immediately, `miniaudio_dt_log.txt` appears beside the EXE, and the second command stops with a short fade. Exit the daemon with `Ctrl+C`.

---

## 2. In-game **Simple Track** tests

Enter a mission (spatial mode on) and execute:

1. `/miniaudio_simple_play mp3`
2. `/miniaudio_simple_stop`
3. `/miniaudio_simple_play wav`
4. `/miniaudio_volume 75`
5. `/miniaudio_pan -0.35`
6. `/miniaudio_manual_clear`

**Expected**
- Daemon launches once (watch the log).
- Audio plays both sample formats.
- Stop command halts playback without freezing (after the recent watchdog fix).
- Volume/pan commands update the control file and audible output.

---

## 3. **Emitter** tests

1. `/miniaudio_emit_start "G:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\Audio\audio\joji-pixelated-kisses-visualizer.mp3" 5`
2. Walk around the cube – confirm attenuation and doppler feel sane (no hard cutoffs).
3. `/miniaudio_emit_stop`
4. `/miniaudio_emit_start G:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\ElevatorMusic\audio\Luude - Down Under (Feat. Colin Hay).mp3 8`
5. Kill the unit via debug menu (or let it despawn) – addon should clean up and log the stop.

**Expected**
- `miniaudio_dt_last_play.json` updates for each start.
- `miniaudio_dt_log.txt` shows periodic `cmd=update` for the emitter’s track id.
- No leftover payload files in `Audio/bin/` after each stop.
- Toggling the **Debug spheres** option while the emitter runs should immediately hide/show the cube + wireframe marker; changing the **Distance scale** slider between runs should make the sound fade closer/farther without editing commands.

---

## 4. **Spatial harness** tests

Run each command, letting it play for ~15 seconds before `stop`.

1. `/miniaudio_spatial_test orbit 4 8 0 "...\joji-pixelated-kisses-visualizer.mp3"`
2. `/miniaudio_spatial_test direction 0 0 8 "...\Luude - Down Under (Feat. Colin Hay).mp3"`
3. `/miniaudio_spatial_test follow "...\Luude - Down Under (Feat. Colin Hay).mp3" 0 0 0`
4. `/miniaudio_spatial_test loop 6 8 0 "...\joji-pixelated-kisses-visualizer.mp3"`
5. `/miniaudio_spatial_test spin 4 6 0 "...\joji-pixelated-kisses-visualizer.mp3"`
6. `/miniaudio_spatial_test stop`

**Expected**
- Each mode renders its orbit/spin sphere and logs alternating `cmd=play`/`cmd=update`.
- `/stop` sends a final `cmd=stop` and prints “Spatial test stopped (user).”
- Performance stays stable (no frame spikes).
- Debug sphere toggle should hide/show the markers instantly; repeating the tests after changing the distance scale demonstrates how the audible range expands or contracts without editing the commands.

---

## 5. API-level tests (Lua console)

Open the in-game lua scratchpad tester and run:

```lua
local api = get_mod("MiniAudioAddon").api
api.enable_logging(true)
api.play({
    id = "api_demo",
    path = "mods/MiniAudioAddon/Audio/test/Free_Test_Data_2MB_MP3.mp3",
    loop = true,
    volume = 0.8,
})
```

Then:

```lua
api.pause("api_demo")
api.resume("api_demo")
api.seek("api_demo", 10)
api.skip("api_demo", -2)
api.speed("api_demo", 1.5)
api.reverse("api_demo", true)
api.update({ id = "api_demo", volume = 0.4 })
api.status({ id = "api_demo" }) -- inspect entry
api.stop("api_demo", { fade = 0.25 })
api.remove("api_demo")
```

**Expected**
- Console prints `[MiniAudioAPI] play/update/stop...` lines (logging on).
- `api.status` returns a Lua table with current `state`, `volume`, `speed`, `reverse`.
- After `api.remove`, `api.has_track("api_demo")` should return `false`.

---

## 6. Process ownership tests

```lua
local api = get_mod("MiniAudioAddon").api
api.play({ id = "p1_track", path = "mods/.../test/Free_Test_Data_2MB_MP3.mp3", loop = true, process_id = 101 })
api.play({ id = "p2_track", path = "mods/.../test/Free_Test_Data_2MB_WAV.wav", loop = true, process_id = 202 })
api.stop_process(101)
api.status() -- confirm only p2_track remains
api.stop_all()
```

**Expected**
- `stop_process(101)` only stops `p1_track`.
- `stop_all` clears the registry and stops every track.

---

## 7. Watchdog + restart resilience

1. Start `/miniaudio_simple_play mp3`.
2. Kill the daemon externally: `taskkill /f /im miniaudio_dt.exe`.
3. Within ~1 second the addon watchdog should relaunch and continue playback.
4. Run `/miniaudio_simple_stop` to verify the freeze regression is fixed.

**Expected**
- Debug log shows `Daemon status reset (force_quit)` followed by `daemon_start cmd: ...`.
- No visible hitch when stopping.

---

## 8. CLI pipe-client regression

While the game is running (daemon alive), push manual payloads through the pipe reported by `MiniAudio:get_pipe_name()`:

```powershell
$pipe = (dmf:dofile("return get_mod('MiniAudioAddon'):get_pipe_name()")) # run via DMF console
Set-Content play.json '{"cmd":"play","id":"manual_cli","path":"G:\\...\Free_Test_Data_2MB_MP3.mp3","loop":false,"volume":1.0}'
Set-Content stop.json '{"cmd":"stop","id":"manual_cli","fade":0.2}'
.\miniaudio_dt.exe --pipe-client --pipe $pipe --payload-file play.json
Start-Sleep -Seconds 2
.\miniaudio_dt.exe --pipe-client --pipe $pipe --payload-file stop.json
```

**Expected** – playback succeeds and the log records the commands without crashing the daemon or the mod.

---

## 9. Shutdown / unload checks

- Disable the mod or exit the game → `miniaudio_dt.exe` should terminate, payload files removed, and no orphaned `.ctl` modifications remain.
- Restart the game; confirm `/miniaudio_simple_play` still works (proves the previous shutdown was clean).

---

## Failure escalation

If any step fails:

1. Capture `MiniAudioAddon/audio/bin/miniaudio_dt_log.txt`.
2. Copy the in-game console output (`/dmf_mod_log MiniAudioAddon`).
3. File an issue/Zendesk with the log snippets, test step number, and hardware audio device info (channel layout, exclusive mode, etc.).
