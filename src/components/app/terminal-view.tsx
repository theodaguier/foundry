import { useEffect, useRef } from "react"
import type { PipelineLogLine } from "@/lib/types"

interface Props {
  lines: PipelineLogLine[]
  title?: string
  visible?: boolean
}

export function TerminalView({ lines, title = "LOG", visible = true }: Props) {
  const scrollRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight
    }
  }, [lines.length])

  if (!visible) return null

  return (
    <div className="flex flex-col border border-border rounded-md overflow-hidden bg-muted">
      <div className="flex items-center px-3 py-2 border-b border-border bg-card">
        <span className="text-[9px] font-mono tracking-[1.2px] text-muted-foreground/60 uppercase">
          {title}
        </span>
        <div className="flex-1" />
        <span className="text-[9px] font-mono text-muted-foreground/60">
          {lines.length} lines
        </span>
      </div>
      <div ref={scrollRef} className="overflow-y-auto max-h-[240px] p-3">
        {lines.length === 0 ? (
          <span className="text-[11px] font-mono text-muted-foreground/60">
            Waiting for output...
          </span>
        ) : (
          lines.map((line, i) => (
            <TerminalLine key={i} line={line} />
          ))
        )}
      </div>
    </div>
  )
}

function TerminalLine({ line }: { line: PipelineLogLine }) {
  const styleClass = (() => {
    switch (line.style) {
      case "success": return "text-success"
      case "error": return "text-destructive"
      case "active": return "text-primary"
      default: return "text-muted-foreground"
    }
  })()

  return (
    <div className="flex gap-2 leading-relaxed">
      <span className="text-[10px] font-mono text-muted-foreground/60 shrink-0 select-none">
        {line.timestamp}
      </span>
      <span className={`text-[11px] font-mono break-all ${styleClass}`}>
        {line.message}
      </span>
    </div>
  )
}
