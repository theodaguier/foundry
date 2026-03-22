import type { ReactNode } from "react";
import Button from "./Button";

interface DialogProps {
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  width?: string;
}

/**
 * Modal dialog overlay — matches Swift .alert / .sheet pattern.
 */
export function Dialog({ open, onClose, children, width = "max-w-[320px]" }: DialogProps) {
  if (!open) return null;

  return (
    <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50" onClick={onClose}>
      <div
        className={`${width} w-full bg-[var(--color-bg-elevated)] rounded-lg p-5 shadow-xl`}
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </div>
    </div>
  );
}

interface ConfirmDialogProps {
  open: boolean;
  title: string;
  message: string;
  confirmLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

/**
 * Confirmation dialog — matches Swift .alert with Cancel + Confirm buttons.
 */
export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel = "Confirm",
  cancelLabel = "Cancel",
  destructive = false,
  onConfirm,
  onCancel,
}: ConfirmDialogProps) {
  return (
    <Dialog open={open} onClose={onCancel} width="max-w-[280px]">
      <h3 className="text-[13px] font-medium mb-1">{title}</h3>
      <p className="text-[11px] text-[var(--color-text-secondary)] mb-4 leading-relaxed">{message}</p>
      <div className="flex gap-2 justify-end">
        <Button variant="secondary" size="sm" onClick={onCancel}>{cancelLabel}</Button>
        <Button variant={destructive ? "destructive" : "primary"} size="sm" onClick={onConfirm}>{confirmLabel}</Button>
      </div>
    </Dialog>
  );
}

interface InputDialogProps {
  open: boolean;
  title: string;
  value: string;
  onChange: (value: string) => void;
  confirmLabel?: string;
  onConfirm: () => void;
  onCancel: () => void;
}

/**
 * Input dialog — matches Swift .alert with TextField.
 */
export function InputDialog({
  open,
  title,
  value,
  onChange,
  confirmLabel = "Done",
  onConfirm,
  onCancel,
}: InputDialogProps) {
  return (
    <Dialog open={open} onClose={onCancel}>
      <h3 className="text-[13px] font-medium mb-3">{title}</h3>
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && value.trim()) onConfirm(); }}
        autoFocus
        className="w-full px-3 py-2 bg-[var(--color-bg-text)] border border-[var(--color-border)] rounded-md text-[13px] text-[var(--color-text-primary)] outline-none focus:border-[var(--color-accent)] font-[var(--font-mono)]"
      />
      <div className="flex gap-2 justify-end mt-4">
        <Button variant="secondary" size="sm" onClick={onCancel}>Cancel</Button>
        <Button variant="primary" size="sm" onClick={onConfirm} disabled={!value.trim()}>{confirmLabel}</Button>
      </div>
    </Dialog>
  );
}
