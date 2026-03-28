import { useState, useMemo } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { useSettingsStore } from "@/stores/settings-store"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuGroup,
  DropdownMenuLabel,
} from "@/components/ui/dropdown-menu"
import { AgentIcon } from "@/components/app/agent-icon"
import { ArrowUp, Plus } from "lucide-react"
import type { FormatOption } from "@/lib/types"

const INITIAL_VISIBLE = 8

const suggestions = [
  {
    title: "Instruments",
    items: [
      { display: "Analog Polysynth", prompt: "Warm analog polysynth with detuned oscillators, a resonant low-pass filter, and ADSR envelope" },
      { display: "808 Drum Machine", prompt: "808-style drum machine with kick, snare, hi-hat, and clap with individual tuning and decay" },
      { display: "Acid Bass", prompt: "303-style acid bassline synth with squelchy resonant filter, accent, slide, and distortion" },
      { display: "Lo-fi Keys", prompt: "Detuned felt piano with wow and flutter, tape hiss, gentle low-pass filter, and subtle chorus" },
      { display: "Supersaw", prompt: "Massive supersaw lead with 7 detuned saw oscillators, unison spread, and portamento" },
      { display: "FM Bell", prompt: "FM synthesis bell with 4 operators, metallic harmonics, slow decay, and brightness control" },
      { display: "Tape Organ", prompt: "Mellotron-style tape organ with speed wobble, tone selector, attack fade, and saturation" },
      { display: "Granular Pad", prompt: "Granular pad synth with grain size, density, pitch scatter, freeze, and long reverb tail" },
      { display: "Pluck", prompt: "Karplus-Strong plucked string with damping, body resonance, brightness, and stereo chorus" },
      { display: "Broken Radio", prompt: "AM radio emulator with tuning dial, static noise, bandwidth filter, and signal dropout" },
      { display: "Choir", prompt: "Formant vocal choir with vowel morphing between A-E-I-O-U, vibrato, and 4-voice unison" },
      { display: "Theremin", prompt: "Monophonic theremin with smooth pitch glide, vibrato depth, waveform morph, and tremolo" },
      { display: "Wind", prompt: "Procedural wind generator with gust intensity, howl frequency, turbulence, and stereo movement" },
      { display: "Music Box", prompt: "Tiny music box synth with metallic tines, mechanical noise, slow deceleration, and room reverb" },
      { display: "Sitar Drone", prompt: "Sympathetic string sitar with drone strings, buzz bridge, portamento, and tanpura resonance" },
      { display: "Circuit Bent", prompt: "Glitchy circuit-bent toy with clock speed knob, bit reduction, random pitch jumps, and crackle" },
      { display: "Bowed Metal", prompt: "Bowed metal plate synth with bow pressure, friction, resonant body modes, and slow attack" },
      { display: "Underwater", prompt: "Subaquatic synth with bubbly LFO, muffled low-pass, water resonance, and depth control" },
      { display: "Swarm", prompt: "Insect swarm generator with density, individual pitch drift, spatial spread, and aggression control" },
      { display: "Tongue Drum", prompt: "Steel tongue drum with strike velocity, tunable tongues, body resonance, and sustain pedal" },
    ],
  },
  {
    title: "Effects",
    items: [
      { display: "Tape Delay", prompt: "Lo-fi tape delay with wow, flutter, saturation, feedback, and tempo sync" },
      { display: "Shimmer Reverb", prompt: "Shimmer reverb with pitch-shifted octave feedback, long decay tail, and modulated diffusion" },
      { display: "Vinyl", prompt: "Vinyl emulation with crackle density, surface noise, wow and flutter, and dustiness control" },
      { display: "Glitch", prompt: "Glitch effect with random buffer repeat, reverse, stutter, tape stop, and probability controls" },
      { display: "Distortion", prompt: "Multi-mode distortion with tube, tape, and fuzz algorithms plus tone shaping" },
      { display: "Spring Reverb", prompt: "Vintage spring reverb with tension, drip intensity, tone control, and crash on hit" },
      { display: "Bitcrusher", prompt: "Bitcrusher with sample rate reduction, bit depth, jitter, and aliasing character" },
      { display: "Phaser", prompt: "12-stage phaser with rate, depth, feedback, stereo spread, and barber-pole mode" },
      { display: "Spectral Freeze", prompt: "FFT spectral freeze that captures a moment of audio and sustains it as a drone, with blur and pitch shift" },
      { display: "Doppler", prompt: "Doppler pitch and volume simulation with speed, distance, rotation mode, and pan" },
      { display: "Granular Delay", prompt: "Delay that shatters repeats into grains with pitch scatter, density, and freeze" },
      { display: "Tape Stop", prompt: "Tape stop and startup effect with speed curve, trigger mode, and vinyl brake" },
      { display: "Resonator", prompt: "Tuned resonator bank with 4 resonant frequencies, decay time, and MIDI tracking" },
      { display: "Reverse Reverb", prompt: "Pre-delay reverse reverb with swell time, decay, tone filter, and crossfade" },
      { display: "Stutter", prompt: "Rhythmic gate with step sequencer, variable gate length, and tempo-synced patterns" },
      { display: "Transient Shaper", prompt: "Transient designer with attack and sustain gain, detection speed, and listen mode" },
      { display: "Lo-fi Degrader", prompt: "Signal degrader with sample rate crush, noise injection, broken speaker, and AM radio mode" },
      { display: "Frequency Shifter", prompt: "Analog frequency shifter with Hz offset, feedback, stereo shift, and LFO" },
      { display: "Ducking Delay", prompt: "Sidechain delay that ducks repeats when input is present, with threshold and release" },
      { display: "Space Echo", prompt: "Roland RE-201 style space echo with 3 playback heads, spring reverb, wow/flutter, and intensity" },
      { display: "Wormhole", prompt: "Extreme reverb with infinite decay, pitch modulation, spectral smearing, and freeze" },
      { display: "Half-speed", prompt: "Real-time half-speed effect like slowing a vinyl record, with octave drop and formant shift" },
      { display: "Parallel Crush", prompt: "Parallel processing with clean/crushed blend, drive, filter, and NY compression style" },
      { display: "Rainfall", prompt: "Procedural rain overlay with droplet density, thunder probability, distance, and puddle splashes" },
    ],
  },
  {
    title: "Utilities",
    items: [
      { display: "Gain Staging", prompt: "Precision gain staging utility with level, pan, phase invert, mono sum, and VU meter" },
      { display: "Spectrum", prompt: "Real-time spectrum analyzer with FFT display, peak hold, and resolution control" },
      { display: "Tuner", prompt: "Chromatic tuner with cent deviation, reference pitch adjustment, and note name display" },
      { display: "Loudness Meter", prompt: "LUFS loudness meter with integrated, short-term, and momentary readings plus true peak" },
      { display: "Oscilloscope", prompt: "Waveform oscilloscope with time zoom, trigger level, freeze, and XY Lissajous mode" },
      { display: "Stereo Scope", prompt: "Mid-side stereo analyzer with goniometer, correlation meter, and mono compatibility check" },
      { display: "Test Tone", prompt: "Test tone generator with sine, white noise, pink noise, and frequency sweep modes" },
      { display: "BPM Tap", prompt: "BPM detector with tap tempo button, beat flash, and tempo range filter" },
      { display: "Channel Tool", prompt: "Channel utility with L/R swap, mid-side encode/decode, polarity flip, and solo" },
      { display: "Reference A/B", prompt: "A/B reference tool to switch between your mix and a reference track with level matching" },
    ],
  },
]

export default function Prompt() {
  const setMainView = useAppStore((s) => s.setMainView)
  const startGeneration = useBuildStore((s) => s.startGeneration)
  const modelCatalog = useSettingsStore((s) => s.modelCatalog)
  const installPaths = useSettingsStore((s) => s.installPaths)
  const [prompt, setPrompt] = useState("")
  const [selectedAgent, setSelectedAgent] = useState("Claude Code")
  const [selectedModel, setSelectedModel] = useState("sonnet")
  const [expanded, setExpanded] = useState<Record<string, boolean>>({})
  const isEmpty = !prompt.trim()

  const generate = async () => {
    if (isEmpty) return
    const format: FormatOption =
      installPaths?.supportedFormats.length === 1
        ? installPaths.supportedFormats[0]
        : "Both"
    setMainView({ kind: "generation" })
    void startGeneration({
      prompt: prompt.trim(),
      format,
      channelLayout: "Stereo",
      presetCount: 5,
      agent: selectedAgent,
      model: selectedModel,
    })
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="w-full flex flex-col py-8 px-6">
        {/* Hero */}
        <div className="flex flex-col items-center gap-2 mb-8">
          <h1 className="text-xl font-[ArchitypeStedelijk] tracking-[1px] uppercase text-foreground">
            What will you build?
          </h1>
          <p className="text-[12px] text-muted-foreground text-center leading-relaxed max-w-xs">
            Describe your audio plugin. Foundry writes the C++, compiles it, and installs it in your DAW.
          </p>
          {installPaths?.supportedFormats.length === 1 && (
            <span className="text-[10px] uppercase tracking-[1.5px] text-muted-foreground/50">
              {installPaths.supportedFormats[0]} only
            </span>
          )}
        </div>

        {/* Prompt input */}
        <div className="mb-8">
          <div className="relative">
            <Textarea
              value={prompt}
              onChange={(e) => setPrompt(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter" && e.metaKey) generate() }}
              placeholder="A warm analog synth with detuned oscillators..."
              autoFocus
              rows={4}
              className="min-h-[100px] resize-none pr-12 rounded-xl"
            />
            <Button
              size="icon-sm"
              onClick={generate}
              disabled={isEmpty}
              className="absolute right-2.5 bottom-2.5 rounded-lg"
            >
              <ArrowUp className="size-4" />
            </Button>
          </div>

          <div className="flex items-center gap-1.5 mt-2">
            <DropdownMenu>
              <DropdownMenuTrigger
                render={
                  <Button variant="ghost" size="sm" className="gap-1.5 text-[11px] text-muted-foreground hover:text-foreground">
                    <AgentIcon agent={selectedAgent} className="size-3.5" />
                    <span>{selectedModel}</span>
                  </Button>
                }
              />
              <DropdownMenuContent align="start" className="min-w-[200px] w-auto">
                {modelCatalog.length === 0 ? (
                  <div className="px-3 py-3 text-[11px] text-muted-foreground">
                    No agent CLI installed. Open Settings to install Claude Code or Codex.
                  </div>
                ) : modelCatalog.map((provider) => (
                  <DropdownMenuGroup key={provider.id}>
                    <DropdownMenuLabel className="flex items-center gap-1.5 text-[9px] tracking-[1px] text-muted-foreground/60 uppercase">
                      <AgentIcon agent={provider.name} className="size-3" />
                      {provider.name}
                    </DropdownMenuLabel>
                    {provider.models.map((model) => (
                      <DropdownMenuItem
                        key={model.id}
                        onClick={() => { setSelectedAgent(provider.name); setSelectedModel(model.flag || model.id) }}
                        className={model.flag === selectedModel || model.id === selectedModel ? "text-foreground" : ""}
                      >
                        <span className="text-[12px]">{model.name}</span>
                        <span className="text-muted-foreground/50 text-[10px] ml-1">{model.subtitle}</span>
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuGroup>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
            <span className="text-[10px] text-muted-foreground/30">
              {"\u2318"}Enter to generate
            </span>
          </div>
        </div>

        {/* Suggestions */}
        <div className="flex flex-col gap-5">
          {suggestions.map((cat) => {
            const isExpanded = expanded[cat.title] ?? false
            const visible = isExpanded ? cat.items : cat.items.slice(0, INITIAL_VISIBLE)
            const hasMore = cat.items.length > INITIAL_VISIBLE

            return (
              <div key={cat.title} className="flex flex-col gap-2">
                <span className="text-[10px] tracking-[1.5px] uppercase text-muted-foreground/40">
                  {cat.title}
                </span>
                <div className="flex flex-wrap gap-1.5">
                  {visible.map((item) => (
                    <button
                      key={item.display}
                      onClick={() => setPrompt(item.prompt)}
                      className="inline-flex items-center px-2 py-1 rounded-md text-[10px] text-muted-foreground bg-muted/60 hover:bg-muted hover:text-foreground transition-colors duration-150 cursor-default"
                    >
                      {item.display}
                    </button>
                  ))}
                  {hasMore && !isExpanded && (
                    <button
                      onClick={() => setExpanded((prev) => ({ ...prev, [cat.title]: true }))}
                      className="inline-flex items-center gap-0.5 px-2 py-1 rounded-md text-[10px] text-muted-foreground/40 bg-muted/30 hover:bg-muted/50 hover:text-muted-foreground transition-colors duration-150 cursor-default"
                    >
                      <Plus className="size-2.5" />
                      {cat.items.length - INITIAL_VISIBLE} more
                    </button>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </div>
  )
}
