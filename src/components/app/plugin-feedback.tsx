import { useState } from "react"
import { cn } from "@/lib/utils"
import { submitPluginFeedback } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Star, Check } from "lucide-react"

interface Props {
  pluginId: string
}

const criteria = [
  { key: "speed", label: "Speed" },
  { key: "quality", label: "Quality" },
  { key: "design", label: "Design" },
] as const

function StarRow({ value, onChange }: { value: number; onChange: (n: number) => void }) {
  const [hover, setHover] = useState(0)

  return (
    <div className="flex gap-0.5" onMouseLeave={() => setHover(0)}>
      {[1, 2, 3, 4, 5].map((n) => (
        <button
          key={n}
          onClick={() => onChange(n)}
          onMouseEnter={() => setHover(n)}
          className="cursor-default p-0.5"
        >
          <Star
            className={cn(
              "size-3.5 transition-colors duration-100",
              (hover || value) >= n
                ? "text-foreground fill-foreground"
                : "text-muted-foreground/20",
            )}
          />
        </button>
      ))}
    </div>
  )
}

export function PluginFeedback({ pluginId }: Props) {
  const [ratings, setRatings] = useState({ speed: 0, quality: 0, design: 0 })
  const [submitted, setSubmitted] = useState(false)

  const allRated = ratings.speed > 0 && ratings.quality > 0 && ratings.design > 0

  const handleSubmit = async () => {
    if (!allRated) return
    setSubmitted(true)
    try {
      await submitPluginFeedback(pluginId, ratings.speed, ratings.quality, ratings.design)
    } catch (e) {
      console.error("Failed to submit feedback:", e)
    }
  }

  if (submitted) {
    return (
      <div className="flex items-center gap-1.5 text-[10px] text-muted-foreground/50">
        <Check className="size-3 text-success" />
        Thanks for your feedback
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-2">
      <span className="text-[10px] text-muted-foreground/50">Rate this plugin</span>
      <div className="flex flex-col gap-1.5">
        {criteria.map((c) => (
          <div key={c.key} className="flex items-center gap-3">
            <span className="text-[10px] text-muted-foreground/60 w-12 shrink-0">{c.label}</span>
            <StarRow
              value={ratings[c.key]}
              onChange={(n) => setRatings((prev) => ({ ...prev, [c.key]: n }))}
            />
          </div>
        ))}
      </div>
      <Button
        size="xs"
        variant="secondary"
        onClick={handleSubmit}
        disabled={!allRated}
        className="self-start mt-0.5"
      >
        Submit
      </Button>
    </div>
  )
}
