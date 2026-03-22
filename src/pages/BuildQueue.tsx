import { useNavigate } from "react-router-dom";
import { useBuildStore } from "../stores/build-store";
import { formatTime, generationStepLabel } from "../lib/utils";
import { Button } from "../components/ui";

export default function BuildQueue() {
  const navigate = useNavigate();
  const store = useBuildStore();

  return (
    <div className="flex flex-col h-full max-w-[600px] mx-auto py-8 px-8">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-lg font-medium">Builds</h2>
        <Button variant="ghost" onClick={() => navigate("/")}>Done</Button>
      </div>

      {!store.isRunning ? (
        <div className="flex-1 flex items-center justify-center">
          <span className="text-[13px] text-[var(--color-text-muted)]">No Active Builds</span>
        </div>
      ) : (
        <div className="bg-[var(--color-bg-elevated)] border border-[var(--color-border)] rounded-lg p-5">
          <div className="flex items-center gap-3 mb-3">
            <div className="w-4 h-4 border-2 border-[var(--color-accent)] border-t-transparent rounded-full animate-spin shrink-0" />
            <span className="text-[13px] font-medium flex-1 truncate">{store.generatedPluginName || store.config?.prompt.slice(0, 40) || "Building..."}</span>
            <span className="text-[11px] text-[var(--color-text-muted)] font-[var(--font-mono)]">{formatTime(store.elapsedSeconds)}</span>
          </div>
          <div className="flex items-center gap-2 mb-2">
            <span className="text-[11px] text-[var(--color-text-secondary)]">{generationStepLabel(store.currentStep)}</span>
            <span className="text-[11px] text-[var(--color-text-muted)]">{Math.round(store.progress * 100)}%</span>
          </div>
          <div className="h-1 bg-[var(--color-border)] rounded-full overflow-hidden mb-3">
            <div className="h-full bg-[var(--color-accent)] rounded-full transition-all duration-300" style={{ width: `${store.progress * 100}%` }} />
          </div>
          {store.buildAttempt > 1 && (
            <span className="text-[11px] text-[var(--color-text-muted)]">Build attempt {store.buildAttempt}</span>
          )}
          <div className="flex justify-end mt-2">
            <Button variant="ghost" size="sm" onClick={() => navigate("/generation")} className="text-[var(--color-accent)]">
              View Progress
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
