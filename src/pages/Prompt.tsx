import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useBuildStore } from "@/stores/build-store"
import { useSettingsStore } from "@/stores/settings-store"
import { Button } from "@/components/ui/button"
import { Textarea } from "@/components/ui/textarea"
import { FoundryLogo } from "@/components/app/foundry-logo"

const suggestions = [
  {
    title: "INSTRUMENTS",
    icon: "♪",
    items: [
      { display: "SUBTRACTIVE SYNTH", prompt: "Warm analog polysynth with detuned oscillators and a low-pass filter" },
      { display: "FM ENGINE", prompt: "FM pad synth with slow attack, chorus, and stereo spread" },
      { display: "WAVETABLE OSC", prompt: "Wavetable synthesizer with morphable waveforms and built-in effects" },
    ],
  },
  {
    title: "EFFECTS",
    icon: "~",
    items: [
      { display: "ALGORITHMIC REVERB", prompt: "Algorithmic reverb with room size, damping, and pre-delay" },
      { display: "TAPE DELAY", prompt: "Lo-fi tape delay with wow, flutter, and saturation" },
      { display: "BITCRUSHER", prompt: "Bitcrusher with sample rate reduction and dithering" },
    ],
  },
  {
    title: "UTILITIES",
    icon: "◎",
    items: [
      { display: "MODULATION MATRIX", prompt: "Flexible modulation matrix with multiple sources and destinations" },
      { display: "STEP SEQUENCER", prompt: "8-step sequencer with rate, swing, and gate controls" },
      { display: "ADSR ENVELOPE", prompt: "ADSR envelope follower with output level and retrigger" },
    ],
  },
];

export default function Prompt() {
  const navigate = useNavigate();
  const startGeneration = useBuildStore((s) => s.startGeneration);
  const modelCatalog = useSettingsStore((s) => s.modelCatalog);
  const [prompt, setPrompt] = useState("");
  const [selectedAgent, setSelectedAgent] = useState("Claude Code");
  const [selectedModel, setSelectedModel] = useState("sonnet");
  const [showModelMenu, setShowModelMenu] = useState(false);

  const isEmpty = !prompt.trim();

  const generate = async () => {
    if (isEmpty) return;
    navigate("/generation");
    void startGeneration({
      prompt: prompt.trim(),
      format: "Both",
      channelLayout: "Stereo",
      presetCount: 5,
      agent: selectedAgent,
      model: selectedModel,
    });
  };

  return (
    <div className="flex h-full">
      {/* Side spacer — Swift: Spacer(minLength: 80) */}
      <div className="min-w-[80px] flex-shrink-0" />

      <div className="flex-1 max-w-[1024px] mx-auto flex flex-col justify-center py-8 overflow-y-auto">
        {/* Hero — Swift: logo 48px, VStack spacing 10 */}
        <div className="flex flex-col items-center gap-2.5 mb-8">
          <FoundryLogo height={48} className="text-foreground opacity-70" />
          <span className="text-[14px] text-muted-foreground">Describe your plugin, Foundry builds it.</span>
        </div>

        {/* Prompt input — Swift: minHeight 100, cornerRadius 8, bg textBackgroundColor 0.5 */}
        <div className="mb-6">
          <Textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && e.metaKey) generate(); }}
            placeholder="A warm analog synth with detuned oscillators…"
            autoFocus
            rows={5}
            className="min-h-[100px] resize-none font-mono text-[14px]"
          />

          {/* Controls row — Swift: HStack spacing 6, pt 10 */}
          <div className="flex items-center gap-1.5 mt-2.5">
            {/* Model picker — Swift: px 10, py 5, cornerRadius 6, controlBg */}
            <div className="relative">
              <button
                onClick={() => setShowModelMenu(!showModelMenu)}
                className="flex items-center gap-1.5 px-2.5 py-[5px] bg-secondary rounded-md text-[12px] font-medium"
              >
                <span className="text-[14px]">⬡</span>
                <span>{selectedModel}</span>
                <svg className="w-2 h-2 text-muted-foreground" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2.5}>
                  <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
                </svg>
              </button>
              {showModelMenu && (
                <>
                  <div className="fixed inset-0 z-10" onClick={() => setShowModelMenu(false)} />
                  <div className="absolute top-full left-0 mt-1 bg-card border border-border rounded-md shadow-xl z-20 min-w-[200px]">
                    {modelCatalog.length === 0 ? (
                      <div className="px-3 py-3 text-[11px] text-muted-foreground">
                        No agent CLI installed. Open Setup to install Claude Code or Codex.
                      </div>
                    ) : modelCatalog.map((provider) => (
                      <div key={provider.id}>
                        <div className="px-3 py-1.5 text-[9px] tracking-[1px] text-muted-foreground/60 uppercase">{provider.name}</div>
                        {provider.models.map((model) => (
                          <button
                            key={model.id}
                            onClick={() => { setSelectedAgent(provider.name); setSelectedModel(model.flag || model.id); setShowModelMenu(false); }}
                            className={`w-full px-3 py-2 text-left text-[12px] hover:bg-secondary flex items-center gap-2 ${
                              selectedModel === (model.flag || model.id) ? "text-primary" : ""
                            }`}
                          >
                            <span>{model.name}</span>
                            <span className="text-muted-foreground/60 text-[10px]">— {model.subtitle}</span>
                          </button>
                        ))}
                      </div>
                    ))}
                  </div>
                </>
              )}
            </div>

            <div className="flex-1" />

            {/* Generate button — Swift: borderedProminent, controlSize large */}
            <Button onClick={generate} disabled={isEmpty}>
              Generate
            </Button>
          </div>
        </div>

        {/* Category grid — Swift: 3 columns, 1px gap, separatorColor border */}
        <div className="grid grid-cols-3 gap-px bg-border border border-border">
          {suggestions.map((cat) => (
            <div key={cat.title} className="bg-muted p-5">
              {/* Header — Swift: HStack spacing sm (12), mb lg (24) */}
              <div className="flex items-center gap-3 mb-6">
                <span className="text-[11px]">{cat.icon}</span>
                <span className="text-[12px] font-mono tracking-[2.4px] text-foreground">{cat.title}</span>
              </div>
              {/* Items — Swift: spacing md (16) */}
              <div className="flex flex-col gap-4">
                {cat.items.map((item) => (
                  <button
                    key={item.display}
                    onClick={() => setPrompt(item.prompt)}
                    className="flex items-center gap-2 group text-left"
                  >
                    <span className="text-[11px] font-mono tracking-[-0.275px] text-muted-foreground group-hover:text-foreground transition-colors">
                      {item.display}
                    </span>
                    <span className="flex-1" />
                    <svg className="w-[7px] h-[7px] text-muted-foreground/60 shrink-0 group-hover:text-muted-foreground transition-colors" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={2}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M7 17L17 7M17 7H7M17 7v10" />
                    </svg>
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Side spacer */}
      <div className="min-w-[80px] flex-shrink-0" />
    </div>
  );
}
