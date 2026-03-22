import { useEffect, useRef } from "react";
import type { PipelineLogLine } from "../../lib/types";

interface Props {
  lines: PipelineLogLine[];
  title?: string;
  visible?: boolean;
}

/**
 * Terminal/log display panel — matches Swift TerminalView.
 * Auto-scrolls to bottom, monospace text with styled lines.
 */
export default function TerminalView({ lines, title = "LOG", visible = true }: Props) {
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [lines.length]);

  if (!visible) return null;

  return (
    <div className="flex flex-col border border-[var(--color-border)] rounded-md overflow-hidden bg-[var(--color-bg-text)]">
      {/* Header */}
      <div className="flex items-center px-3 py-2 border-b border-[var(--color-border)] bg-[var(--color-bg-elevated)]">
        <span className="text-[9px] font-[var(--font-mono)] tracking-[1.2px] text-[var(--color-text-muted)] uppercase">
          {title}
        </span>
        <div className="flex-1" />
        <span className="text-[9px] font-[var(--font-mono)] text-[var(--color-text-muted)]">
          {lines.length} lines
        </span>
      </div>

      {/* Log content */}
      <div ref={scrollRef} className="overflow-y-auto max-h-[240px] p-3">
        {lines.length === 0 ? (
          <span className="text-[11px] font-[var(--font-mono)] text-[var(--color-text-muted)]">
            Waiting for output...
          </span>
        ) : (
          lines.map((line, i) => (
            <TerminalLine key={i} line={line} />
          ))
        )}
      </div>
    </div>
  );
}

function TerminalLine({ line }: { line: PipelineLogLine }) {
  const styleClass = (() => {
    switch (line.style) {
      case "success": return "text-[var(--color-traffic-green)]";
      case "error": return "text-[var(--color-traffic-red)]";
      case "active": return "text-[var(--color-accent)]";
      default: return "text-[var(--color-text-secondary)]";
    }
  })();

  return (
    <div className="flex gap-2 leading-relaxed">
      <span className="text-[10px] font-[var(--font-mono)] text-[var(--color-text-muted)] shrink-0 select-none">
        {line.timestamp}
      </span>
      <span className={`text-[11px] font-[var(--font-mono)] break-all ${styleClass}`}>
        {line.message}
      </span>
    </div>
  );
}
