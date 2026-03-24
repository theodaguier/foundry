import { useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useBuildStore } from "@/stores/build-store"
import { Button } from "@/components/ui/button"
import type { FormatOption, ChannelLayout, PresetCount } from "@/lib/types"

export default function QuickOptions() {
  const navigate = useNavigate();
  const location = useLocation();
  const startGeneration = useBuildStore((s) => s.startGeneration);
  const prompt = (location.state as any)?.prompt || "";
  const agent = (location.state as any)?.agent || "Claude Code";
  const model = (location.state as any)?.model || "sonnet";

  const [format, setFormat] = useState<FormatOption>("Both");
  const [channels, setChannels] = useState<ChannelLayout>("Stereo");
  const [presets, setPresets] = useState<PresetCount>(5);

  const generate = async () => {
    await startGeneration({
      prompt,
      format,
      channelLayout: channels,
      presetCount: presets,
      agent,
      model,
    });
    navigate("/generation");
  };

  return (
    <div className="flex flex-col items-center justify-center h-full">
      <div className="w-[400px] flex flex-col gap-8">
        <h2 className="text-lg font-medium text-center">Quick Options</h2>

        <div className="flex flex-col gap-6">
          <SegmentedPicker label="FORMAT" options={["AU", "VST3", "Both"] as FormatOption[]} value={format} onChange={setFormat} />
          <SegmentedPicker label="CHANNELS" options={["Mono", "Stereo"] as ChannelLayout[]} value={channels} onChange={setChannels} />
          <SegmentedPicker label="PRESETS" options={[0, 3, 5, 10] as PresetCount[]} value={presets} onChange={setPresets} displayFn={(v) => v === 0 ? "None" : String(v)} />
        </div>

        <div className="flex gap-3 justify-center">
          <Button variant="ghost" onClick={() => navigate("/prompt")}>Back</Button>
          <Button onClick={generate}>Generate</Button>
        </div>
      </div>
    </div>
  );
}

function SegmentedPicker<T extends string | number>({ label, options, value, onChange, displayFn }: {
  label: string;
  options: T[];
  value: T;
  onChange: (v: T) => void;
  displayFn?: (v: T) => string;
}) {
  return (
    <div>
      <span className="text-[9px] tracking-[2px] text-muted-foreground/60 font-mono mb-2 block">{label}</span>
      <div className="flex bg-muted rounded-md overflow-hidden border border-border">
        {options.map((opt) => (
          <button
            key={String(opt)}
            onClick={() => onChange(opt)}
            className={`flex-1 py-2 text-xs font-mono transition-colors ${
              value === opt
                ? "bg-primary text-primary-foreground"
                : "text-muted-foreground hover:text-foreground"
            }`}
          >
            {displayFn ? displayFn(opt) : String(opt)}
          </button>
        ))}
      </div>
    </div>
  );
}
