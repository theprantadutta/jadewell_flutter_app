# Audio credits and licences

Everything here is public domain (CC0 1.0) or original. Nothing requires
attribution, but credit is given below anyway. Licences were checked on the
download page on 2026-11-16. Downloads were processed (trimmed, loudness
normalised, faded, re-encoded) for the game; the originals are unchanged at
the source URLs.

## Music (`music/`, Ogg Vorbis ~90 kbps stereo, normalised to -18 LUFS)

| File | Title | Author | Source | Licence | Notes |
|---|---|---|---|---|---|
| `hot_spring_town.ogg` | Hot Springs Town | Kistol (OGA user `kistol`) | https://opengameart.org/content/hot-springs-town | CC0 ("No credits necessary") | Made for Town Music Jam #3. 2:40. Used the FLAC master. |
| `notebook_lofi.ogg` | Japanese Lofi Hiphop Track ("God's Notebook – Main Theme") | Uploaded by OGA user `pickentcode` | https://opengameart.org/content/japanese-lofi-hiphop-track | CC0 | Uploader says it was commissioned on Fiverr for an unfinished project and released as CC0. 2:29. Leading/trailing silence trimmed. |
| `chill_lofi.ogg` | Chill lofi inspired (seamless loop edit) | omfgdude (original), qubodup (loop edit) | https://opengameart.org/content/chill-lofi-inspired-loop-edit (original: https://opengameart.org/content/chill-lofi-inspired) | CC0 | 1:37, already loop-edited. |

All three are processed with `loudnorm=I=-18:TP=-2`, a 1 s fade-in and a 3 s
fade-out; the app crossfades between them (4 s) and loops each one if the
crossfade timer is late.

## Sound effects (`sfx/`, 16-bit mono WAV 44.1 kHz)

Sampled sounds come from Kenney's CC0 packs (https://kenney.nl, "This content
is free to use in personal, educational and commercial projects", CC0 1.0,
https://creativecommons.org/publicdomain/zero/1.0/). They were low-passed,
trimmed and level-matched.

| File | Source | Processing |
|---|---|---|
| `tap.wav` | Kenney *Interface Sounds* (https://kenney.nl/assets/interface-sounds) `select_002.ogg` | low-pass 3.5 kHz |
| `select.wav` | Kenney *Casino Audio* (https://kenney.nl/assets/casino-audio) `chip-lay-3.ogg` (clay chip) | low-pass 4.5 kHz |
| `deselect.wav` | Kenney *Casino Audio* `chip-lay-1.ogg` | pitched down 18 %, low-pass 3.5 kHz |
| `mismatch.wav` | Kenney *Impact Sounds* (https://kenney.nl/assets/impact-sounds) `impactWood_medium_002.ogg` | low-pass 3 kHz |
| `blocked.wav` | Kenney *Impact Sounds* `impactWood_light_001.ogg` | low-pass 2.5 kHz, doubled 60 ms apart (matches the double haptic tick) |
| `shuffle.wav` | Kenney *Casino Audio* `chips-handle-5.ogg` | band-pass 200 Hz–5 kHz |
| `toggle.wav` | Kenney *Interface Sounds* `toggle_002.ogg` | low-pass 4 kHz |

Synthesised for Jadewell (original, public domain): Karplus–Strong plucked
strings (guzheng-like) and additive bells in A major pentatonic, with a short
synthetic reverb.

| File | Sound |
|---|---|
| `match.wav` | two rising plucks (E5 → A5) with a soft bell shimmer |
| `star.wav` | bright bell ping (C♯6) |
| `hint.wav` | quiet descending bell sparkle |
| `unlock.wav` | three rising plucks + bell |
| `clear.wav` | pentatonic run up the strings resolving on a bell chord (~1.8 s) |
| `undo.wav` | reversed pluck ("reverse pop") into a tiny marimba tick |

To replace any sound, keep the file name: `AudioServiceImpl` loads
`assets/audio/sfx/<Sfx.name>.wav` and the music list in
`AudioServiceImpl.defaultMusicTracks`.
