interface Props {
  children: string;
  className?: string;
}

/**
 * Section header label — matches Swift Form Section header style.
 * 9px mono, tracking 1.2, muted, uppercase.
 */
export default function SectionLabel({ children, className = "" }: Props) {
  return (
    <span className={`text-[9px] tracking-[1.2px] text-[var(--color-text-muted)] font-[var(--font-mono)] uppercase block mb-2 ${className}`}>
      {children}
    </span>
  );
}
