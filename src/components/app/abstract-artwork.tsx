import type { PluginType } from "@/lib/types"

interface Props {
  pluginType: PluginType
  className?: string
}

/**
 * Type-based abstract artwork matching Swift AbstractArtwork.
 * - instrument -> WaveformBars (8 animated bars)
 * - effect -> ConcentricRings (3 circles)
 * - utility -> SpectrumBars (5 bars with baseline)
 */
export function AbstractArtwork({ pluginType, className = "" }: Props) {
  return (
    <div className={`flex items-center justify-center w-full h-full ${className}`}>
      {pluginType === "instrument" && <WaveformBars />}
      {pluginType === "effect" && <ConcentricRings />}
      {pluginType === "utility" && <SpectrumBars />}
    </div>
  )
}

function WaveformBars() {
  const heights = [0.3, 0.5, 0.8, 0.6, 0.9, 0.4, 0.7, 0.5]
  return (
    <svg viewBox="0 0 80 40" className="w-[80px] h-[40px] opacity-20">
      {heights.map((h, i) => (
        <rect
          key={i}
          x={i * 10}
          y={40 - h * 40}
          width={6}
          height={h * 40}
          rx={1}
          fill="currentColor"
          className="text-foreground"
        />
      ))}
    </svg>
  )
}

function ConcentricRings() {
  return (
    <svg viewBox="0 0 60 60" className="w-[60px] h-[60px] opacity-20">
      {[28, 20, 12].map((r) => (
        <circle
          key={r}
          cx={30}
          cy={30}
          r={r}
          fill="none"
          stroke="currentColor"
          strokeWidth={1}
          className="text-foreground"
        />
      ))}
    </svg>
  )
}

function SpectrumBars() {
  const heights = [0.4, 0.7, 1.0, 0.6, 0.3]
  return (
    <svg viewBox="0 0 50 40" className="w-[50px] h-[40px] opacity-20">
      <line x1={0} y1={39} x2={50} y2={39} stroke="currentColor" strokeWidth={1} className="text-foreground" />
      {heights.map((h, i) => (
        <rect
          key={i}
          x={i * 10 + 1}
          y={39 - h * 35}
          width={7}
          height={h * 35}
          rx={1}
          fill="currentColor"
          className="text-foreground"
        />
      ))}
    </svg>
  )
}
