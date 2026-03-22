interface Props {
  label: string;
  value: string;
}

/**
 * Label + value row — matches Swift InfoRow (HStack, label 72px, mono fonts).
 * Used in PluginDetailView, Result, and anywhere key-value info is displayed.
 */
export default function InfoRow({ label, value }: Props) {
  return (
    <div className="flex gap-6 px-6 py-3">
      <span className="w-[72px] shrink-0 text-[9px] font-[var(--font-mono)] tracking-[1.2px] text-[var(--color-text-muted)] uppercase pt-0.5">
        {label}
      </span>
      <span className="text-[11px] font-[var(--font-mono)] text-[var(--color-text-secondary)] select-text break-words leading-relaxed">
        {value}
      </span>
    </div>
  );
}
