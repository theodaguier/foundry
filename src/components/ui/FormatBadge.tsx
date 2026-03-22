import type { PluginFormat } from "../../lib/types";

interface Props {
  formats: PluginFormat[];
  style?: "accent" | "muted";
}

/**
 * Capsule badge showing plugin formats — matches Swift FormatBadge.
 * "AU · VST3" or "AU" or "VST3"
 */
export default function FormatBadge({ formats, style = "accent" }: Props) {
  const label = formats.join(" · ");

  if (style === "muted") {
    return (
      <span className="text-[10px] font-bold font-[var(--font-mono)] text-[var(--color-text-muted)] px-2.5 py-1 bg-[var(--color-bg-control)] rounded-full">
        {label}
      </span>
    );
  }

  return (
    <span className="text-[10px] font-bold font-[var(--font-mono)] text-[var(--color-accent)] px-2.5 py-1 bg-[var(--color-accent)]/12 rounded-full">
      {label}
    </span>
  );
}
