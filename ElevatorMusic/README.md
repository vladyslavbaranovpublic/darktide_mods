# ElevatorMusic

Play custom elevator/airlock tunes on every Darktide moveable platform (hub lifts, mission airlocks, transition shuttles, and more). The mod now talks directly to **MiniAudioAddon’s API** – no more per-mod daemon wrappers or payload files – so it happily coexists with any other MiniAudioAddon client.

## Requirements
- [Darktide Local Server](https://www.nexusmods.com/warhammer40kdarktide/mods/211)
- [MiniAudioAddon](https://www.nexusmods.com/warhammer40kdarktide/mods/???) (load it before ElevatorMusic)

## Setup
1. Drop one or more audio files into `mods/ElevatorMusic/audio/` (mp3/wav/ogg/opus/flac).
2. Enable the mod in-game and tweak the options if desired.
3. Hop on any elevator or stand near an idle platform – the track should flow from idle → activation → linger → idle without awkward restarts.

## Behaviour overview
- **Idle speaker.** When you approach a stationary platform the mod starts a low-volume mix whose gain is based on your distance. Walk away and it fades automatically.
- **Activation hand-off.** If the platform begins moving while idle music is playing, the same track is promoted to activation mode (full volume, refreshed spatial source) instead of stopping and re-starting later.
- **Linger & fade.** Once the ride completes you can keep the music alive for a configurable number of seconds before fading out. If you’re still nearby, the idle speaker can spin back up automatically.
- **Playlist control.** Drop as many files as you want, pick random or sequential order, and set a master gain. Everything is routed through `MiniAudioAddon.api.play/update/stop`, so other mods can still play their own sounds.

## Commands
- `/elevatormusic_refresh` – rescan `mods/ElevatorMusic/audio/` without restarting the game.

Enjoy smoother, gap-free elevator jams without juggling payload files or separate daemons.
