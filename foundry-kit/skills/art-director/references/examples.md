# Layout Examples

These 15 examples show the range of layouts, sizes, and structures this skill produces. Same design language, radically different forms.

---

## 01 — Gate (480×260)
Minimal. Input meter left, large threshold knob center, envelope display + 3 knobs right, options column, output meter.
No header. Plugin name in bottom-right corner, 9px dimTextColour.
Zone widths: [60px meter][140px threshold][220px env+knobs][100px options][60px meter]

## 02 — True Peak Limiter (620×260)
Transfer curve display takes 200px. Ceiling knob hero at left. Params grid 4×2. Status column. Stereo meters.
Thin top bar: name + LED only, no preset.
Zone widths: [140px ceiling][200px curve][flex params][120px status][100px meters]

## 03 — Chorus / Ensemble (760×280)
Modulation waveform display occupies full height left half. Depth knob right of display. Params grid. LFO section. Mix fader.
No title bar anywhere.
Zone widths: [320px display][130px depth][220px params][140px lfo][90px mix]

## 04 — Distortion / Drive (740×260)
Transfer curve 200px. Drive knob large left. Tone/bias/mix/output grid. Algorithm list. Output meters.
Small name label inside drive zone, top-left, 9px.
Zone widths: [130px drive][200px curve][flex params][120px modes][90px meters]

## 05 — Stereo Width MS (740×240)
Vectorscope display 200px. Width knob. MS controls grid split Mid/Side. Correlation meter. Output meters.
Very compact — 240px height, no wasted space.
Zone widths: [200px scope][130px width][flex ms][120px corr][100px meters]

## 06 — Compressor (820×300)
GR meter column far left. Threshold knob large. Attack/Release/Knee/Makeup/Mix grid. Character toggles + ratio pills. Output meter.
Header: 36px top bar with name + preset + LED.
Zone widths: [60px gr][150px threshold][flex params][140px char][80px output]

## 07 — Tape Saturation (880×320)
Input VU meter. Drive knob hero (80px). Type/speed/bias character section. Tone knobs. Output stereo meters.
Warm dark base (#1c1510), amber accent (#c87030).
Zone widths: [60px vu][180px drive][180px char][140px tone][120px output]

## 08 — Loudness Analyzer (900×280)
Spectrum display 540px wide. LUFS readouts column. Stereo peak meters. Target mode list.
Display-dominant. No knobs visible — pure meters and readouts.
Zone widths: [540px spectrum][180px lufs][100px stereo][130px targets]

## 09 — Granular Processor (900×340)
Waveform + selection display 260px. Grain params 3×3 grid. Scatter XY plot 140px. Mod matrix rows. Mix fader.
Most complex layout — 5 distinct zones, each different in nature.
Zone widths: [260px source][200px grain][140px scatter][flex mod][90px mix]

## 10 — 4-Band Compressor (900×340)
GR overview bar spans full width at top (70px, 4 colored bands). Below: 4 equal band columns side by side. Master strip bottom (48px).
Top-to-bottom AND left-to-right — exception justified by the 4-band structure.
No knob hero — the 4 GR bars ARE the dominant visual.

## 11 — Parametric EQ (900×300)
EQ curve display 60% height. Band controls row below — 6 columns, each band a different color.
Display fully dominates. Controls are secondary, compact.
No standalone hero knob.

## 12 — Subtractive Synth (900×360)
Tabs row (Synth/FX/Arp). OSC section, Filter section (with curve display), Amp Env (with ADSR shape), LFO, Mod Matrix.
Each section has internal hierarchy but no single plugin-wide hero.
Zone widths proportional to parameter count.

## 13 — Algorithmic Reverb (900×300)
Room visualizer with scatter plot left. Type list. Params 2×4 grid. Mix single large fader.
Visualizer is the hero — not a knob.
Zone widths: [280px room][160px type][flex params][90px mix]

## 14 — Stereo Delay (900×320)
Delay line visualization top half (full width). Below: tap+sync strip. L channel controls. R channel controls. Filter section. Dry/Wet faders.
Top-to-bottom split: visualization area / controls area.

## 15 — Harmonizer (900×300)
Pitch detection scope left. Voice rows (Dry + 3 voices): each a horizontal strip with LED + label + mini pitch display + semitone value + pan + level bar. Scale list. Formant knob.
Unusual: voices are rows not columns. Justified by the nature of harmonizer workflow.
