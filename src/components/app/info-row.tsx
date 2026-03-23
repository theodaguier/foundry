interface Props {
  label: string
  value: string
}

export function InfoRow({ label, value }: Props) {
  return (
    <div className="flex gap-6 px-6 py-3">
      <span className="w-[72px] shrink-0 text-[9px] font-mono tracking-[1.2px] text-muted-foreground/60 uppercase pt-0.5">
        {label}
      </span>
      <span className="text-[11px] font-mono text-muted-foreground select-text break-words leading-relaxed">
        {value}
      </span>
    </div>
  )
}
