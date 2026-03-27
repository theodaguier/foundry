import { useState } from "react"
import { ThumbsUp, ThumbsDown } from "lucide-react"
import { useBuildStore } from "@/stores/build-store"
import { rateGeneration } from "@/lib/commands"
import { cn } from "@/lib/utils"

interface Props {
  /** When provided, rates a specific historical generation (not the current build) */
  telemetryId?: string
  /** Pre-existing rating — shown as selected state */
  initialRating?: 1 | -1 | null
}

export function GenerationFeedback({ telemetryId, initialRating }: Props) {
  const storeTelemetryId = useBuildStore((s) => s.lastCompletedTelemetryId)
  const storeRating = useBuildStore((s) => s.userRating)
  const setStoreRating = useBuildStore((s) => s.setUserRating)

  // Historical mode: standalone state, doesn't touch build-store
  const [localRating, setLocalRating] = useState<1 | -1 | null>(initialRating ?? null)

  const isHistorical = telemetryId !== undefined
  const effectiveId = isHistorical ? telemetryId : storeTelemetryId
  const currentRating = isHistorical ? localRating : storeRating

  if (!effectiveId) return null

  const handleRate = (rating: 1 | -1) => {
    if (currentRating !== null) return // already rated
    if (isHistorical) {
      setLocalRating(rating)
      rateGeneration(effectiveId, rating).catch(console.error)
    } else {
      setStoreRating(rating)
    }
  }

  if (currentRating !== null) {
    return (
      <div className="flex items-center gap-2 text-xs text-muted-foreground font-mono">
        {currentRating === 1 ? (
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
          onClick={() => handleRate(1)}
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
          onClick={() => handleRate(-1)}
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
