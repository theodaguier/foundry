interface Props {
  className?: string;
}

/**
 * 1px horizontal divider — matches Swift Separator / Rectangle().fill(border).frame(height:1).
 */
export default function Separator({ className = "" }: Props) {
  return <div className={`h-px bg-[var(--color-border)] ${className}`} />;
}
