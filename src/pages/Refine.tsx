import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useAppStore } from "../stores/app-store";
import { useBuildStore } from "../stores/build-store";
import { Button } from "../components/ui";

export default function Refine() {
  const navigate = useNavigate();
  const { pluginId } = useParams();
  const plugins = useAppStore((s) => s.plugins);
  const startRefine = useBuildStore((s) => s.startRefine);
  const plugin = plugins.find((p) => p.id === pluginId);
  const [modification, setModification] = useState("");

  if (!plugin) return <div className="flex items-center justify-center h-full text-[var(--color-text-muted)]">Plugin not found</div>;

  const isEmpty = !modification.trim();

  const refine = async () => {
    if (isEmpty) return;
    await startRefine({ plugin, modification: modification.trim() });
    navigate("/refinement");
  };

  return (
    <div className="flex h-full">
      <div className="min-w-[80px] flex-shrink-0" />
      <div className="flex-1 max-w-[1024px] mx-auto flex flex-col justify-center py-8">
        <div className="flex flex-col items-center gap-2.5 mb-8">
          <svg className="w-12 h-12 text-[var(--color-text-secondary)]" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085" />
          </svg>
          <span className="text-sm text-[var(--color-text-secondary)]">Modify {plugin.name}</span>
        </div>

        <div className="mb-6">
          <textarea
            value={modification}
            onChange={(e) => setModification(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && e.metaKey) refine(); }}
            placeholder="Add a low-pass filter with resonance control..."
            autoFocus
            rows={5}
            className="w-full min-h-[100px] p-3 bg-[color-mix(in_srgb,var(--color-bg-text)_50%,transparent)] text-sm text-[var(--color-text-primary)] placeholder:text-[var(--color-text-dimmed)] rounded-lg border border-[var(--color-border)] outline-none resize-none font-[var(--font-mono)] focus:border-[var(--color-text-muted)]"
          />
          <div className="flex items-center justify-end gap-2.5 mt-2.5">
            <Button variant="ghost" onClick={() => navigate(-1 as any)}>Cancel</Button>
            <Button variant="primary" size="lg" onClick={refine} disabled={isEmpty}>Refine</Button>
          </div>
        </div>
      </div>
      <div className="min-w-[80px] flex-shrink-0" />
    </div>
  );
}
