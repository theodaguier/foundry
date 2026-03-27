import { ThumbsUp, ThumbsDown } from "lucide-react"
import { useBuildStore } from "@/stores/build-store"
import { cn } from "@/lib/utils"

export function GenerationFeedback() {
  const userRating = useBuildStore((s) => s.userRating)
  const setUserRating = useBuildStore((s) => s.setUserRating)
  const telemetryId = useBuildStore((s) => s.lastCompletedTelemetryId)

  if (!telemetryId) return null

  if (userRating !== null) {
    return (
      <div className="flex items-center gap-2 text-xs text-muted-foreground font-mono">
        {userRating === 1 ? (
          <ThumbsUp className="size-3.5 text-success" />
        ) : (
          <ThumbsDown className="size-3.5 text-destructive" />
        )}
        <span>Feedback recorded</span>
      </div>
    )
  }

  return (
    <div className="flex items-center gap-3">
      <span className="text-xs text-muted-foreground font-mono">How did this turn out?</span>
      <div className="flex items-center gap-1.5">
        <button
          onClick={() => setUserRating(1)}
          className={cn(
            "flex items-center justify-center size-7 rounded-sm border border-border",
            "text-muted-foreground hover:text-success hover:border-success",
            "transition-colors duration-150"
          )}
          title="Good"
        >
          <ThumbsUp className="size-3.5" />
        </button>
        <button
          onClick={() => setUserRating(-1)}
          className={cn(
            "flex items-center justify-center size-7 rounded-sm border border-border",
            "text-muted-foreground hover:text-destructive hover:border-destructive",
            "transition-colors duration-150"
          )}
          title="Bad"
        >
          <ThumbsDown className="size-3.5" />
        </button>
      </div>
    </div>
  )
}
