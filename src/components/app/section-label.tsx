interface Props {
  children: string
  className?: string
}

export function SectionLabel({ children, className = "" }: Props) {
  return (
    <span className={`text-[9px] tracking-[1.2px] text-muted-foreground/60 font-mono uppercase block mb-2 ${className}`}>
      {children}
    </span>
  )
}
