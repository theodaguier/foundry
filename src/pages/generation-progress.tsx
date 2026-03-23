import { useState, useEffect, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { useBuildStore } from "@/stores/build-store";
import { formatTime, generationStepLabel } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/app/confirm-dialog";
import type { AgentModel, GenerationStep } from "@/lib/types";

const STEP_ORDER: Record<GenerationStep, number> = {
  preparingEnvironment: 0,
  preparingProject: 1,
  generatingDSP: 2,
  generatingUI: 3,
  compiling: 4,
  installing: 5,
};

const GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const ALL_STEPS: GenerationStep[] = [
  "preparingEnvironment",
  "preparingProject",
  "generatingDSP",
  "generatingUI",
  "compiling",
  "installing",
];
const REFINE_STEPS: GenerationStep[] = [
  "preparingEnvironment",
  "generatingDSP",
  "compiling",
  "installing",
];

function NameScramble({ targetName }: { targetName: string | null }) {
  const [slots, setSlots] = useState<{ char: string; locked: boolean }[]>(
    Array.from({ length: 7 }, () => ({
      char: GLYPHS[Math.floor(Math.random() * 26)],
      locked: false,
    })),
  );
  const resolved = useRef(false);

  useEffect(() => {
    if (resolved.current) return;
    const interval = setInterval(() => {
      setSlots((prev) =>
        prev.map((s) =>
          s.locked ? s : { ...s, char: GLYPHS[Math.floor(Math.random() * 26)] },
        ),
      );
    }, 80);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (!targetName || resolved.current) return;
    const target = targetName.toUpperCase().split("");
    setSlots((prev) => {
      const newSlots = [...prev];
      while (newSlots.length < target.length)
        newSlots.push({
          char: GLYPHS[Math.floor(Math.random() * 26)],
          locked: false,
        });
      return newSlots.slice(0, target.length);
    });

    target.forEach((ch, i) => {
      setTimeout(
        () => {
          setSlots((prev) =>
            prev.map((s, j) => (j === i ? { char: ch, locked: true } : s)),
          );
          if (i === target.length - 1) resolved.current = true;
        },
        i * 120 + 150,
      );
    });
  }, [targetName]);

  return (
    <div className="flex gap-0.5 h-[52px] items-center justify-center">
      {slots.map((slot, i) => (
        <span
          key={i}
          className={`text-[42px] font-[ArchitypeStedelijk] transition-all duration-200 ${slot.locked ? "text-foreground" : "text-muted-foreground/40 blur-[0.8px]"}`}
        >
          {slot.char}
        </span>
      ))}
    </div>
  );
}

interface Props {
  mode: "generation" | "refinement";
}

export default function GenerationProgress({ mode }: Props) {
  const navigate = useNavigate();
  const currentStep = useBuildStore((s) => s.currentStep);
  const completedSteps = useBuildStore((s) => s.completedSteps);
  const showConsole = useBuildStore((s) => s.showConsole);
  const generatedPluginName = useBuildStore((s) => s.generatedPluginName);
  const progress = useBuildStore((s) => s.progress);
  const elapsedSeconds = useBuildStore((s) => s.elapsedSeconds);
  const logLines = useBuildStore((s) => s.logLines);
  const streamingText = useBuildStore((s) => s.streamingText);
  const buildAttempt = useBuildStore((s) => s.buildAttempt);
  const config = useBuildStore((s) => s.config);
  const refineConfig = useBuildStore((s) => s.refineConfig);
  const setShowConsole = useBuildStore((s) => s.setShowConsole);
  const reset = useBuildStore((s) => s.reset);
  const cancel = useBuildStore((s) => s.cancel);

  const [showCancel, setShowCancel] = useState(false);
  const isRefine = mode === "refinement";
  const steps = isRefine ? REFINE_STEPS : ALL_STEPS;

  const modelMeta = (() => {
    const selectedModel: AgentModel | null = refineConfig?.plugin.model ?? null;

    const agentLabel =
      config?.agent ?? refineConfig?.plugin.agent ?? "claude-code";

    const modelLabel =
      config?.model ??
      selectedModel?.name ??
      selectedModel?.flag ??
      "unknown-model";

    return {
      agentLabel,
      modelLabel,
      stepLabel: generationStepLabel(currentStep, isRefine),
    };
  })();

  const logStyleClass = (style?: string) => {
    switch (style) {
      case "success":
        return "text-success";
      case "error":
        return "text-destructive";
      case "active":
        return "text-primary";
      default:
        return "text-muted-foreground";
    }
  };

  return (
    <div className="flex h-full">
      <div className="flex-1 flex flex-col items-center justify-center p-8">
        <div className="flex flex-col gap-8 max-w-[360px] w-full">
          {!isRefine && <NameScramble targetName={generatedPluginName} />}

          <div className="flex flex-col">
            {steps.map((step) => {
              const isDone = completedSteps.has(STEP_ORDER[step]);
              const isActive = currentStep === step;
              const isPending = !isDone && !isActive;
              return (
                <div key={step} className="flex items-center gap-2.5 py-1.5">
                  <div className="w-5 flex items-center justify-center">
                    {isDone ? (
                      <svg
                        className="w-3.5 h-3.5 text-success"
                        fill="currentColor"
                        viewBox="0 0 20 20"
                      >
                        <path
                          fillRule="evenodd"
                          d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
                          clipRule="evenodd"
                        />
                      </svg>
                    ) : isActive ? (
                      <div className="w-3.5 h-3.5 border-2 border-muted-foreground border-t-transparent rounded-full animate-spin" />
                    ) : (
                      <svg
                        className="w-3.5 h-3.5 text-muted-foreground/25"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                        strokeWidth={1.5}
                      >
                        <circle cx="12" cy="12" r="10" />
                      </svg>
                    )}
                  </div>
                  <span
                    className={`text-sm font-mono ${isPending ? "text-muted-foreground/60" : "text-foreground"}`}
                  >
                    {generationStepLabel(step, isRefine)}
                  </span>
                  <span className="flex-1" />
                  {isDone && (
                    <span className="text-xs text-muted-foreground">Done</span>
                  )}
                </div>
              );
            })}
          </div>

          <div className="w-full h-1 bg-border rounded-full overflow-hidden">
            <div
              className="h-full bg-primary transition-all duration-300 rounded-full"
              style={{ width: `${progress * 100}%` }}
            />
          </div>

          <div className="flex items-center gap-4 justify-center">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowConsole(!showConsole)}
            >
              {showConsole ? "Hide Log" : "Show Log"}
            </Button>
            <Button variant="ghost" size="sm" onClick={() => navigate("/")}>
              Minimize
            </Button>
            <Button variant="ghost" onClick={() => setShowCancel(true)}>
              Cancel
            </Button>
          </div>
        </div>
      </div>

      {showConsole && (
        <>
          <div className="w-px bg-border" />
          <div className="flex-1 flex flex-col bg-muted">
            <div className="flex items-center justify-between px-4 py-2 border-b border-border">
              <div className="flex flex-col gap-1">
                <span className="text-[10px] tracking-[1px] text-muted-foreground/60">
                  BUILD LOG
                </span>
                <span className="text-[10px] text-muted-foreground/60 font-mono uppercase">
                  {modelMeta.agentLabel} · {modelMeta.modelLabel} ·{" "}
                  {modelMeta.stepLabel}
                  {buildAttempt > 0 ? ` · attempt ${buildAttempt}` : ""}
                </span>
              </div>
              <span className="text-[10px] text-muted-foreground/60 font-mono">
                {formatTime(elapsedSeconds)}
              </span>
            </div>
            <div className="flex-1 overflow-y-auto p-3 font-mono text-xs space-y-3">
              {streamingText && (
                <div className="border border-border rounded-md bg-card/60 overflow-hidden">
                  <div className="px-3 py-2 border-b border-border text-[10px] tracking-[1px] text-muted-foreground/60">
                    LIVE AGENT MESSAGE
                  </div>
                  <div className="px-3 py-2 text-primary whitespace-pre-wrap break-words leading-5">
                    {streamingText}
                  </div>
                </div>
              )}

              <div className="space-y-1">
                {logLines.map((line, i) => (
                  <div key={i} className="flex gap-2 leading-5">
                    <span className="text-muted-foreground/60 mr-2 shrink-0">
                      {line.timestamp}
                    </span>
                    <span
                      className={`break-words whitespace-pre-wrap ${logStyleClass(line.style)}`}
                    >
                      {line.message}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </>
      )}

      <ConfirmDialog
        open={showCancel}
        title={isRefine ? "Cancel Refinement?" : "Cancel Build?"}
        message={`This will stop the current ${isRefine ? "refinement" : "build"}. You will lose all progress.`}
        confirmLabel="Cancel Build"
        cancelLabel="Continue"
        destructive
        onConfirm={() => {
          cancel();
          reset();
          navigate("/");
        }}
        onCancel={() => setShowCancel(false)}
      />
    </div>
  );
}
