import { useState } from "react"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { useSettingsStore } from "@/stores/settings-store"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { Label } from "@/components/ui/label"
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuGroup,
  DropdownMenuLabel,
} from "@/components/ui/dropdown-menu"
import { AgentIcon } from "@/components/app/agent-icon"
import { ArrowUpRight } from "lucide-react"
import type { FormatOption } from "@/lib/types"

const suggestions = [
  {
    title: "Instruments",
    items: [
      { display: "Subtractive Synth", prompt: "Warm analog polysynth with detuned oscillators, a resonant low-pass filter, and ADSR envelope" },
      { display: "FM Pad", prompt: "FM pad synth with slow attack, chorus, stereo spread, and 4-operator modulation" },
      { display: "Wavetable Synth", prompt: "Wavetable synthesizer with morphable waveforms, unison voices, and built-in delay" },
      { display: "Pluck Synth", prompt: "Karplus-Strong plucked string synth with damping, body resonance, and stereo chorus" },
      { display: "Organ", prompt: "Tonewheel organ with drawbar controls, rotary speaker simulation, and overdrive" },
      { display: "Drum Machine", prompt: "808-style drum machine with kick, snare, hi-hat, and clap with individual tuning and decay" },
      { display: "Acid Bass", prompt: "303-style acid bassline synth with squelchy resonant filter, accent, slide, and distortion" },
      { display: "Noise Synth", prompt: "Noise-based texture synth with filtered white/pink noise, sample and hold modulation, and stereo panning" },
      { display: "Supersaw Lead", prompt: "Massive supersaw lead synth with 7 detuned saw oscillators, unison spread, and portamento" },
      { display: "Granular Drone", prompt: "Granular drone synth with grain size, density, pitch scatter, and freeze control for ambient textures" },
      { display: "Kalimba", prompt: "Physical modeling kalimba with tine stiffness, damping, body resonance, and sympathetic resonance" },
      { display: "Lo-fi Piano", prompt: "Detuned felt piano synth with wow and flutter, tape hiss, and a soft low-pass filter" },
    ],
  },
  {
    title: "Effects",
    items: [
      { display: "Algorithmic Reverb", prompt: "Algorithmic reverb with room size, damping, pre-delay, and stereo width" },
      { display: "Tape Delay", prompt: "Lo-fi tape delay with wow, flutter, saturation, and tempo sync" },
      { display: "Bitcrusher", prompt: "Bitcrusher with sample rate reduction, bit depth control, and dithering" },
      { display: "Chorus", prompt: "Stereo chorus with rate, depth, feedback, and mix controls" },
      { display: "Phaser", prompt: "12-stage phaser with rate, depth, feedback, and stereo spread" },
      { display: "Compressor", prompt: "Optical compressor with threshold, ratio, attack, release, and sidechain filter" },
      { display: "Distortion", prompt: "Multi-mode distortion with tube, tape, and fuzz algorithms plus tone shaping" },
      { display: "Flanger", prompt: "Through-zero flanger with rate, depth, feedback, and manual controls" },
      { display: "Parametric EQ", prompt: "4-band parametric EQ with low shelf, two parametric mids, and high shelf with Q control" },
      { display: "Tremolo", prompt: "Stereo tremolo with sine, triangle, and square LFO shapes and tempo sync" },
      { display: "Ring Modulator", prompt: "Ring modulator with carrier frequency, LFO modulation, and wet/dry mix" },
      { display: "Shimmer Reverb", prompt: "Shimmer reverb with pitch-shifted octave feedback, long decay tail, and modulated diffusion" },
      { display: "Vinyl Crackle", prompt: "Vinyl emulation with crackle density, surface noise, wow and flutter, and dustiness control" },
      { display: "Stutter Gate", prompt: "Rhythmic gate effect with step sequencer, variable gate length, and tempo-synced patterns" },
      { display: "Pitch Shifter", prompt: "Polyphonic pitch shifter with semitone and cent control, formant preservation, and stereo detune" },
      { display: "Spring Reverb", prompt: "Vintage spring reverb emulation with tension, drip intensity, and tone control" },
      { display: "Auto-Wah", prompt: "Envelope follower wah with sensitivity, frequency range, resonance, and up/down sweep modes" },
      { display: "Glitch Machine", prompt: "Glitch effect with random buffer repeat, reverse, stutter, tape stop, and probability controls" },
    ],
  },
  {
    title: "Utilities",
    items: [
      { display: "Gain Utility", prompt: "Precision gain staging utility with level, pan, phase invert, and mono summing" },
      { display: "Spectrum Analyzer", prompt: "Real-time spectrum analyzer with FFT display, peak hold, and adjustable resolution" },
      { display: "Stereo Widener", prompt: "Mid-side stereo width plugin with width control, bass mono, and correlation meter" },
      { display: "Tuner", prompt: "Chromatic tuner with cent deviation display, reference pitch adjustment, and note detection" },
      { display: "Test Tone", prompt: "Test tone generator with sine, white noise, pink noise, and sweep modes with frequency and level controls" },
      { display: "Loudness Meter", prompt: "LUFS loudness meter with integrated, short-term, momentary readings, and true peak display" },
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
      <div className="max-w-[520px] mx-auto flex flex-col py-8 px-6">
        {/* Hero */}
        <div className="flex flex-col items-center gap-2.5 mb-8">
          <span className="text-[14px] text-muted-foreground">Describe your plugin, Foundry builds it.</span>
          {installPaths?.supportedFormats.length === 1 && (
            <span className="text-[11px] uppercase tracking-[1px] text-muted-foreground/60">
              {installPaths.supportedFormats[0]} only on this platform
            </span>
          )}
        </div>

        {/* Prompt input */}
        <div className="mb-6">
          <Textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && e.metaKey) generate() }}
            placeholder="A warm analog synth with detuned oscillators..."
            autoFocus
            rows={5}
            className="min-h-[100px] resize-none font-mono text-[14px]"
          />

          {/* Controls row */}
          <div className="flex items-center gap-1.5 mt-2.5">
            {/* Model picker */}
            <DropdownMenu>
              <DropdownMenuTrigger
                render={
                  <Button variant="secondary" size="sm" className="gap-1.5 text-[12px]">
                    <AgentIcon agent={selectedAgent} className="size-3.5" />
                    <span>{selectedModel}</span>
                  </Button>
                }
              />
              <DropdownMenuContent align="start" className="min-w-[200px] w-auto">
                {modelCatalog.length === 0 ? (
                  <div className="px-3 py-3 text-xs text-muted-foreground">
                    No agent CLI installed. Open Setup to install Claude Code or Codex.
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
                        className={selectedModel === (model.flag || model.id) ? "text-primary" : ""}
                      >
                        <span>{model.name}</span>
                        <span className="text-muted-foreground/60 text-[10px]">— {model.subtitle}</span>
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuGroup>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>

            <div className="flex-1" />

            <Button size="sm" onClick={generate} disabled={isEmpty}>
              Generate
            </Button>
          </div>
        </div>

        {/* Suggestions */}
        <div className="flex flex-col gap-5">
          {suggestions.map((cat, catIdx) => (
            <div key={cat.title} className="flex flex-col gap-2">
              <Label>{cat.title}</Label>
              <div className="flex flex-wrap gap-1.5">
                {cat.items.map((item) => (
                  <Button
                    key={item.display}
                    variant="outline"
                    size="sm"
                    onClick={() => setPrompt(item.prompt)}
                    className="gap-1.5"
                  >
                    <span className="text-xs">{item.display}</span>
                    <ArrowUpRight className="size-3 text-muted-foreground/60 shrink-0" />
                  </Button>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
