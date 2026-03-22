import { useState, useEffect, useCallback, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { useBuildStore } from "../stores/build-store";
import { useAppStore } from "../stores/app-store";
import { useTauriEvent } from "../hooks/use-tauri-event";
import { formatTime, generationStepLabel } from "../lib/utils";
import { Button, TerminalView } from "../components/ui";
import { ConfirmDialog } from "../components/ui/Dialog";
import type { GenerationStep, PipelineLogLine } from "../lib/types";

const GLYPHS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const ALL_STEPS: GenerationStep[] = ["preparingProject", "generatingDSP", "generatingUI", "compiling", "installing"];
const REFINE_STEPS: GenerationStep[] = ["generatingDSP", "compiling", "installing"];

function NameScramble({ targetName }: { targetName: string | null }) {
  const [slots, setSlots] = useState<{ char: string; locked: boolean }[]>(
    Array.from({ length: 7 }, () => ({ char: GLYPHS[Math.floor(Math.random() * 26)], locked: false }))
  );
  const resolved = useRef(false);

  useEffect(() => {
    if (resolved.current) return;
    const interval = setInterval(() => {
      setSlots((prev) => prev.map((s) => s.locked ? s : { ...s, char: GLYPHS[Math.floor(Math.random() * 26)] }));
    }, 80);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (!targetName || resolved.current) return;
    const target = targetName.toUpperCase().split("");
    setSlots((prev) => {
      const newSlots = [...prev];
      while (newSlots.length < target.length) newSlots.push({ char: GLYPHS[Math.floor(Math.random() * 26)], locked: false });
      return newSlots.slice(0, target.length);
    });

    target.forEach((ch, i) => {
      setTimeout(() => {
        setSlots((prev) => prev.map((s, j) => j === i ? { char: ch, locked: true } : s));
        if (i === target.length - 1) resolved.current = true;
      }, i * 120 + 150);
    });
  }, [targetName]);

  return (
    <div className="flex gap-0.5 h-[52px] items-center justify-center">
      {slots.map((slot, i) => (
        <span
          key={i}
          className="text-[42px] font-[ArchitypeStedelijk] transition-all duration-200"
          style={{
            color: slot.locked ? "var(--color-text-primary)" : "rgba(255,255,255,0.25)",
            filter: slot.locked ? "none" : "blur(0.8px)",
          }}
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
  const store = useBuildStore();
  const [showCancel, setShowCancel] = useState(false);
  const isRefine = mode === "refinement";
  const steps = isRefine ? REFINE_STEPS : ALL_STEPS;

  // Timer
  useEffect(() => {
    if (!store.isRunning) return;
    const interval = setInterval(() => store.tick(), 1000);
    return () => clearInterval(interval);
  }, [store.isRunning, store]);

  // Event listeners
  const handleStep = useCallback((payload: { step: GenerationStep }) => store.handleStep(payload.step), [store]);
  const handleLog = useCallback((payload: PipelineLogLine) => store.handleLog(payload), [store]);
  const handleName = useCallback((payload: { name: string }) => store.handleName(payload.name), [store]);
  const handleError = useCallback((payload: { message: string }) => {
    store.handleError(payload.message);
    navigate("/error", { state: { message: payload.message } });
  }, [store, navigate]);
  const handleComplete = useCallback((payload: { plugin: any }) => {
    store.handleComplete(payload.plugin);
    useAppStore.getState().loadPlugins();
    navigate(`/result/${payload.plugin.id}`);
  }, [store, navigate]);
  const handleBuildAttempt = useCallback((payload: { attempt: number }) => store.handleBuildAttempt(payload.attempt), [store]);

  useTauriEvent("pipeline:step", handleStep);
  useTauriEvent("pipeline:log", handleLog);
  useTauriEvent("pipeline:name", handleName);
  useTauriEvent("pipeline:error", handleError);
  useTauriEvent("pipeline:complete", handleComplete);
  useTauriEvent("pipeline:build_attempt", handleBuildAttempt);

  const stepIndex = (step: GenerationStep) => ALL_STEPS.indexOf(step);

  return (
    <div className="flex h-full">
      {/* Left panel */}
      <div className="flex-1 flex flex-col items-center justify-center p-8">
        <div className="flex flex-col gap-8 max-w-[360px] w-full">
          {!isRefine && <NameScramble targetName={store.generatedPluginName} />}

          {/* Step list */}
          <div className="flex flex-col">
            {steps.map((step) => {
              const isDone = store.completedSteps.has(stepIndex(step));
              const isActive = store.currentStep === step || (isRefine && step === "generatingDSP" && store.currentStep === "generatingUI");
              const isPending = !isDone && !isActive;
              return (
                <div key={step} className="flex items-center gap-2.5 py-1.5">
                  <div className="w-5 flex items-center justify-center">
                    {isDone ? (
                      <svg className="w-3.5 h-3.5 text-[var(--color-traffic-green)]" fill="currentColor" viewBox="0 0 20 20"><path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" /></svg>
                    ) : isActive ? (
                      <div className="w-3.5 h-3.5 border-2 border-[var(--color-text-secondary)] border-t-transparent rounded-full animate-spin" />
                    ) : (
                      <svg className="w-3.5 h-3.5 text-[var(--color-text-faint)]" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}><circle cx="12" cy="12" r="10" /></svg>
                    )}
                  </div>
                  <span className={`text-sm font-mono ${isPending ? "text-[var(--color-text-muted)]" : "text-[var(--color-text-primary)]"}`}>
                    {generationStepLabel(step, isRefine)}
                  </span>
                  <span className="flex-1" />
                  {isDone && <span className="text-xs text-[var(--color-text-secondary)]">Done</span>}
                </div>
              );
            })}
          </div>

          {/* Progress bar */}
          <div className="w-full h-1 bg-[var(--color-border)] rounded-full overflow-hidden">
            <div className="h-full bg-[var(--color-accent)] transition-all duration-300 rounded-full" style={{ width: `${store.progress * 100}%` }} />
          </div>

          {/* Actions */}
          <div className="flex items-center gap-4 justify-center">
            <Button variant="ghost" size="sm" onClick={() => store.setShowConsole(!store.showConsole)}>
              {store.showConsole ? "Hide Log" : "Show Log"}
            </Button>
            <Button variant="ghost" onClick={() => setShowCancel(true)}>Cancel</Button>
          </div>
        </div>
      </div>

      {/* Terminal panel */}
      {store.showConsole && (
        <>
          <div className="w-px bg-[var(--color-border)]" />
          <div className="flex-1 flex flex-col bg-[var(--color-bg-text)]">
            <div className="flex items-center justify-between px-4 py-2 border-b border-[var(--color-border)]">
              <span className="text-[10px] tracking-[1px] text-[var(--color-text-muted)]">BUILD LOG</span>
              <span className="text-[10px] text-[var(--color-text-muted)] font-mono">{formatTime(store.elapsedSeconds)}</span>
            </div>
            <div className="flex-1 overflow-y-auto p-3 font-mono text-xs">
              {store.logLines.map((line, i) => (
                <div key={i} className="text-[var(--color-text-secondary)] leading-5">
                  <span className="text-[var(--color-text-muted)] mr-2">{line.timestamp}</span>
                  {line.message}
                </div>
              ))}
            </div>
          </div>
        </>
      )}

      {/* Cancel confirmation */}
      <ConfirmDialog
        open={showCancel}
        title={isRefine ? "Cancel Refinement?" : "Cancel Build?"}
        message={`This will stop the current ${isRefine ? "refinement" : "build"}. You will lose all progress.`}
        confirmLabel="Cancel Build"
        cancelLabel="Continue"
        destructive
        onConfirm={() => { store.cancel(); store.reset(); navigate("/"); }}
        onCancel={() => setShowCancel(false)}
      />
    </div>
  );
}
