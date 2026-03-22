import { useState, type ReactNode } from "react";

interface MenuProps {
  trigger: ReactNode;
  children: ReactNode;
  align?: "left" | "right";
  position?: "above" | "below";
}

/**
 * Dropdown menu — matches Swift Menu / contextMenu pattern.
 */
export function Menu({ trigger, children, align = "left", position = "above" }: MenuProps) {
  const [open, setOpen] = useState(false);

  const positionClass = position === "above" ? "bottom-full mb-1" : "top-full mt-1";
  const alignClass = align === "left" ? "left-0" : "right-0";

  return (
    <div className="relative">
      <div onClick={() => setOpen(!open)}>{trigger}</div>
      {open && (
        <>
          <div className="fixed inset-0 z-10" onClick={() => setOpen(false)} />
          <div className={`absolute ${positionClass} ${alignClass} bg-[var(--color-bg-elevated)] border border-[var(--color-border)] rounded-md shadow-xl z-20 min-w-[180px] py-1`}>
            {children}
          </div>
        </>
      )}
    </div>
  );
}

interface MenuItemProps {
  label: string;
  onClick: () => void;
  destructive?: boolean;
  disabled?: boolean;
}

/**
 * Single menu item — matches Swift Button inside Menu.
 */
export function MenuItem({ label, onClick, destructive, disabled }: MenuItemProps) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`w-full px-3 py-1.5 text-left text-[12px] hover:bg-[var(--color-bg-control)] transition-colors disabled:opacity-40 ${
        destructive ? "text-[var(--color-traffic-red)]" : "text-[var(--color-text-primary)]"
      }`}
    >
      {label}
    </button>
  );
}

/**
 * Menu divider.
 */
export function MenuSeparator() {
  return <div className="h-px bg-[var(--color-border)] my-1" />;
}
