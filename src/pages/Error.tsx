import { useState, useEffect } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useBuildStore } from "../stores/build-store";

export default function ErrorPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const config = useBuildStore((s) => s.config);
  const startGeneration = useBuildStore((s) => s.startGeneration);
  const message = (location.state as any)?.message || "An unknown error occurred";

  const [iconAppeared, setIconAppeared] = useState(false);
  const [textAppeared, setTextAppeared] = useState(false);
  const [actionsAppeared, setActionsAppeared] = useState(false);

  useEffect(() => {
    const t1 = setTimeout(() => setIconAppeared(true), 50);
    const t2 = setTimeout(() => setTextAppeared(true), 200);
    const t3 = setTimeout(() => setActionsAppeared(true), 350);
    return () => { clearTimeout(t1); clearTimeout(t2); clearTimeout(t3); };
  }, []);

  const failureTitle = message.toLowerCase().includes("incomplete") ? "Implementation Incomplete"
    : message.toLowerCase().includes("timed out") ? "Generation Timed Out"
    : message.toLowerCase().includes("compile") || message.toLowerCase().includes("error:") ? "Build Failed"
    : "Generation Failed";

  const failureSubtitle: Record<string, string> = {
    "Implementation Incomplete": "The generated plugin was missing key implementations.\nTry again with a more detailed prompt.",
    "Generation Timed Out": "The code generator did not finish\nwithin the allowed time.",
    "Build Failed": "Foundry could not compile the plugin\nafter multiple attempts.",
    "Generation Failed": "Foundry could not finish a usable plugin\nfrom this brief.",
  };

  const retry = async () => {
    if (config) {
      await startGeneration(config);
      navigate("/generation");
    }
  };

  return (
    <div className="flex flex-col items-center justify-center h-full gap-5">
      <svg
        className="w-10 h-10 text-[var(--color-text-secondary)] transition-all duration-500"
        style={{ opacity: iconAppeared ? 1 : 0, transform: iconAppeared ? "scale(1)" : "scale(0.92)" }}
        fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1}
      >
        <path strokeLinecap="round" strokeLinejoin="round" d="M10 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2m7-2a9 9 0 11-18 0 9 9 0 0118 0z" />
      </svg>

      <div
        className="flex flex-col items-center gap-1.5 transition-all duration-350"
        style={{ opacity: textAppeared ? 1 : 0, transform: textAppeared ? "translateY(0)" : "translateY(4px)" }}
      >
        <h2 className="text-xl font-medium">{failureTitle}</h2>
        <p className="text-sm text-[var(--color-text-secondary)] text-center whitespace-pre-line">{failureSubtitle[failureTitle]}</p>
      </div>

      <div
        className="flex gap-2.5 mt-2 transition-all duration-350"
        style={{ opacity: actionsAppeared ? 1 : 0, transform: actionsAppeared ? "translateY(0)" : "translateY(6px)" }}
      >
        <button onClick={() => navigate("/")} className="px-4 py-2 text-sm rounded-lg bg-[var(--color-bg-control)] text-[var(--color-text-secondary)]">Back to Library</button>
        {config && (
          <button onClick={retry} className="px-5 py-2 bg-[var(--color-accent)] text-white text-sm rounded-lg font-medium">Retry</button>
        )}
      </div>
    </div>
  );
}
