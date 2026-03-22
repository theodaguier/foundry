import type { ReactNode } from "react";

type Variant = "accent" | "muted" | "success" | "warning" | "error";

interface Props {
  variant?: Variant;
  children: ReactNode;
  className?: string;
}

const variantStyles: Record<Variant, string> = {
  accent: "text-[var(--color-accent)] bg-[var(--color-accent)]/12",
  muted: "text-[var(--color-text-muted)] bg-[var(--color-bg-control)]",
  success: "text-[var(--color-traffic-green)] bg-[var(--color-traffic-green)]/12",
  warning: "text-[var(--color-traffic-yellow)] bg-[var(--color-traffic-yellow)]/12",
  error: "text-[var(--color-traffic-red)] bg-[var(--color-traffic-red)]/12",
};

/**
 * Capsule badge — matches Swift BadgeView / FormatBadge.
 */
export default function Badge({ variant = "accent", children, className = "" }: Props) {
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 text-[10px] font-bold font-[var(--font-mono)] rounded-full ${variantStyles[variant]} ${className}`}>
      {children}
    </span>
  );
}
