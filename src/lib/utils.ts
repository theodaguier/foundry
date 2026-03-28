import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"
import type { PluginType, GenerationStep } from "@/lib/types"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

export function hexToRgba(hex: string, alpha: number): string {
  const r = parseInt(hex.slice(1, 3), 16)
  const g = parseInt(hex.slice(3, 5), 16)
  const b = parseInt(hex.slice(5, 7), 16)
  return `rgba(${r}, ${g}, ${b}, ${alpha})`
}

export function pluginTypeDisplayName(type: PluginType): string {
  switch (type) {
    case "instrument": return "Instrument"
    case "effect": return "Effect"
    case "utility": return "Utility"
  }
}

export function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${m}:${s.toString().padStart(2, "0")}`
}

export function generationStepLabel(step: GenerationStep | null, isRefine = false): string {
  switch (step) {
    case "preparingEnvironment": return "Preparing environment"
    case "preparingProject": return "Preparing project"
    case "generating": return isRefine ? "Applying changes" : "Generating code"
    case "compiling": return "Compiling"
    case "installing": return "Installing"
    default: return "Waiting..."
  }
}
