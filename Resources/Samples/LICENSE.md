# Instrument samples

The recorded instrument sounds in this folder (guitars, bass, violin, viola, cello, double bass,
banjo, piano) were rendered note by note from **MuseScore_General.sf2** (version 0.2), shared
under the MIT license. The acknowledgements and copyright notices of the original work:

- FluidR3 (original version) by Frank Wen, Copyright (c) 2000-02
- Mono conversion (FluidR3Mono) by Michael Cowgill, Copyright (c) 2014-17
- Adaptation for MuseScore_General.sf2 by S. Christian Collins, Copyright (c) 2018-19

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Regenerate with `tools/render_samples.swift` and `tools/tune_samples.swift`.

The metronome hits in `metronome/` (except the synthesized beep) come from the same SoundFont's GM percussion kit; regenerate with `tools/render_metronome.swift`.

The progression player's drum kit in `drums/` (including the crash cymbal and the three toms used for fills) is one-shots from the same SoundFont's GM percussion kit ("Standard"); regenerate with `tools/render_drums.swift`.

## Bağlama (`baglama/`)

Single notes of a short-neck bağlama recorded by **fcerim** on Freesound, pack "Baglama Notes"
(https://freesound.org/people/fcerim/packs/40093/), dedicated to the public domain under
**Creative Commons CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/). Each file was trimmed to its
attack, level-matched, faded and re-encoded with `tools/import_samples.swift`; its pitch is in `tuning.json`.

- `43.m4a`: "Baglama_Gl", https://freesound.org/people/fcerim/sounds/717204/
- `44.m4a`: "Baglama_Abl", https://freesound.org/people/fcerim/sounds/717179/
- `45.m4a`: "Baglama_A", https://freesound.org/people/fcerim/sounds/717175/
- `46.m4a`: "Baglama_Bb", https://freesound.org/people/fcerim/sounds/717182/
- `52.m4a`: "Baglama_E", https://freesound.org/people/fcerim/sounds/717195/
- `53.m4a`: "Baglama_F", https://freesound.org/people/fcerim/sounds/717200/
- `54.m4a`: "Baglama_Fsharp", https://freesound.org/people/fcerim/sounds/717201/
- `55.m4a`: "Baglama_G", https://freesound.org/people/fcerim/sounds/717203/
- `56.m4a`: "Baglama_Ab", https://freesound.org/people/fcerim/sounds/717176/
- `57.m4a`: "Baglama_Ah", https://freesound.org/people/fcerim/sounds/717180/
- `59.m4a`: "Baglama_B", https://freesound.org/people/fcerim/sounds/717181/
- `60.m4a`: "Baglama_Ch", https://freesound.org/people/fcerim/sounds/717188/
- `61.m4a`: "Baglama_Cs", https://freesound.org/people/fcerim/sounds/717189/
- `62.m4a`: "Baglama_D1N", https://freesound.org/people/fcerim/sounds/719281/
- `63.m4a`: "Baglama_Eb", https://freesound.org/people/fcerim/sounds/717196/
- `64.m4a`: "Baglama_Eh", https://freesound.org/people/fcerim/sounds/717199/

## Ukulele (`ukulele/`)

The pitched notes (C4–C6) of the **FreePats Ukulele**, version 2026-08-11, recorded by Mateusz Dąbrowski from a
Flight Fireball tenor ukulele (https://freepats.zenvoid.org/GuitarFamily/ukulele.html,
https://github.com/freepats/ukulele1), dedicated to the public domain under **Creative Commons CC0 1.0**
(https://creativecommons.org/publicdomain/zero/1.0/). Re-encoded with `tools/import_samples.swift`.
