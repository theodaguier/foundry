import { useRef, useState, useEffect, useCallback, useMemo } from "react"
import { useAppStore } from "@/stores/app-store"
import { FoundryLogo } from "@/components/app/foundry-logo"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog"
import { Gift, Send, Check } from "lucide-react"
import { assignCardVariantBatch, updateCardVariant } from "@/lib/commands"
import type { CardVariant } from "@/lib/types"

function useSmoothTilt(cardRef: React.RefObject<HTMLDivElement | null>) {
  const target = useRef({ x: 0, y: 0, mx: 0.5, my: 0.5 })
  const current = useRef({ x: 0, y: 0, mx: 0.5, my: 0.5 })
  const hovering = useRef(false)
  const rafId = useRef(0)

  const reducedMotion =
    typeof window !== "undefined" &&
    window.matchMedia("(prefers-reduced-motion: reduce)").matches

  const loop = useCallback(() => {
    const lerp = 0.08
    const c = current.current
    const t = target.current
    c.x += (t.x - c.x) * lerp
    c.y += (t.y - c.y) * lerp
    c.mx += (t.mx - c.mx) * lerp
    c.my += (t.my - c.my) * lerp

    const el = cardRef.current
    if (el) {
      el.style.transform = `rotateX(${c.x}deg) rotateY(${c.y}deg)`
      const sx = -c.y * 1.5
      const sy = c.x * 1.5
      if (el.classList.contains("premium-card--gold")) {
        el.style.boxShadow = `${sx}px ${sy}px 40px -8px rgba(120,95,30,0.3), 0 20px 50px -12px rgba(80,60,15,0.2), 0 0 0 1px rgba(160,130,50,0.25)`
      } else if (el.classList.contains("premium-card--diamond")) {
        el.style.boxShadow = `${sx}px ${sy}px 40px -8px rgba(80,120,200,0.25), 0 0 60px -15px rgba(100,160,255,0.1), 0 0 0 1px rgba(140,180,255,0.15)`
      } else if (el.classList.contains("premium-card--ambassador")) {
        el.style.boxShadow = `${sx}px ${sy}px 40px -8px rgba(247,89,0,0.25), 0 20px 50px -12px rgba(200,60,0,0.15), 0 0 0 1px rgba(247,89,0,0.2)`
      } else {
        el.style.boxShadow = `${sx}px ${sy}px 40px -12px rgba(0,0,0,0.15), 0 0 0 1px rgba(0,0,0,0.04)`
      }
      el.style.setProperty("--glare-x", `${c.mx * 100}%`)
      el.style.setProperty("--glare-y", `${c.my * 100}%`)
      el.style.setProperty("--glare-opacity", hovering.current ? "1" : "0")
    }
    rafId.current = requestAnimationFrame(loop)
  }, [cardRef])

  useEffect(() => {
    if (reducedMotion) return
    rafId.current = requestAnimationFrame(loop)
    return () => cancelAnimationFrame(rafId.current)
  }, [loop, reducedMotion])

  const onMouseMove = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      if (reducedMotion || !cardRef.current) return
      const rect = cardRef.current.getBoundingClientRect()
      const x = (e.clientX - rect.left) / rect.width
      const y = (e.clientY - rect.top) / rect.height
      target.current = { x: (y - 0.5) * -12, y: (x - 0.5) * 12, mx: x, my: y }
    },
    [cardRef, reducedMotion],
  )
  const onMouseEnter = useCallback(() => { hovering.current = true }, [])
  const onMouseLeave = useCallback(() => {
    hovering.current = false
    target.current = { x: 0, y: 0, mx: 0.5, my: 0.5 }
  }, [])

  return { onMouseMove, onMouseEnter, onMouseLeave }
}

function getColorTokens(variant: CardVariant) {
  switch (variant) {
    case "gold":
      return {
        label: "gold-surface-text-dim",
        heading: "gold-surface-text",
        body: "gold-surface-text-dim",
        faint: "gold-surface-text-faint",
        guilloche: "text-[#3d2e0a]",
        border: "border-[#3d2e0a]/12",
        logo: "text-[#3d2e0a]",
        logoFaint: "text-[#3d2e0a]/20",
        checkFill: "border-[#3d2e0a]/50 bg-[#3d2e0a]/20",
        checkEmpty: "border-[#3d2e0a]/15",
        checkStroke: "#3d2e0a",
      }
    case "diamond":
      return {
        label: "diamond-text-dim",
        heading: "diamond-text",
        body: "diamond-text-dim",
        faint: "diamond-text-faint",
        guilloche: "text-[#1e2d50]",
        border: "border-[#1e2d50]/12",
        logo: "text-[#1e2d50]",
        logoFaint: "text-[#1e2d50]/20",
        checkFill: "border-[#1e2d50]/50 bg-[#1e2d50]/20",
        checkEmpty: "border-[#1e2d50]/15",
        checkStroke: "#1e2d50",
      }
    case "ambassador":
      return {
        label: "ambassador-text-dim",
        heading: "ambassador-text",
        body: "ambassador-text-dim",
        faint: "ambassador-text-faint",
        guilloche: "text-[#3a1500]",
        border: "border-[#3a1500]/12",
        logo: "text-[#3a1500]",
        logoFaint: "text-[#3a1500]/20",
        checkFill: "border-[#3a1500]/50 bg-[#3a1500]/20",
        checkEmpty: "border-[#3a1500]/15",
        checkStroke: "#3a1500",
      }
    default:
      return {
        label: "text-muted-foreground/55",
        heading: "text-foreground",
        body: "text-foreground/70",
        faint: "text-muted-foreground/35",
        guilloche: "text-foreground",
        border: "border-foreground/[0.06]",
        logo: "text-foreground",
        logoFaint: "text-muted-foreground/20",
        checkFill: "border-foreground bg-foreground",
        checkEmpty: "border-muted-foreground/25",
        checkStroke: "currentColor",
      }
  }
}

function PremiumCard({ variant }: { variant: CardVariant }) {
  const userProfile = useAppStore((s) => s.userProfile)
  const plugins = useAppStore((s) => s.plugins)
  const cardRef = useRef<HTMLDivElement>(null)
  const { onMouseMove, onMouseEnter, onMouseLeave } = useSmoothTilt(cardRef)

  const isGold = variant === "gold"
  const isDiamond = variant === "diamond"
  const isAmbassador = variant === "ambassador"

  const memberSince = userProfile?.createdAt
    ? new Date(userProfile.createdAt).toLocaleDateString("en-US", { month: "short", year: "numeric" })
    : new Date().toLocaleDateString("en-US", { month: "short", year: "numeric" })
  const plan = userProfile?.plan === "pro" ? "Pro" : "Free"
  const displayName = userProfile?.displayName || userProfile?.email?.split("@")[0] || "User"
  const email = userProfile?.email || ""
  const userId = userProfile?.id ? userProfile.id.slice(0, 8).toUpperCase() : "--------"

  const stats = useMemo(() => {
    const instruments = plugins.filter((p) => p.type === "instrument").length
    const effects = plugins.filter((p) => p.type === "effect").length
    const utilities = plugins.filter((p) => p.type === "utility").length
    return [
      { label: "plugins", value: plugins.length, checked: plugins.length > 0 },
      { label: "instruments", value: instruments, checked: instruments > 0 },
      { label: "effects", value: effects, checked: effects > 0 },
      { label: "utilities", value: utilities, checked: utilities > 0 },
    ]
  }, [plugins])

  const c = getColorTokens(variant)

  const cardClass = isGold ? "premium-card--gold" : isDiamond ? "premium-card--diamond" : isAmbassador ? "premium-card--ambassador" : ""
  const bgClass = isGold ? "premium-card--gold-bg" : isDiamond ? "premium-card--diamond-bg" : isAmbassador ? "premium-card--ambassador-bg" : "bg-card"
  const glareClass = isGold ? "premium-card-glare--gold" : isDiamond ? "premium-card-glare--diamond" : isAmbassador ? "premium-card-glare--ambassador" : "premium-card-glare"
  const guillocheOpacity = isGold ? "opacity-[0.05]" : isAmbassador ? "opacity-[0.05]" : isDiamond ? "opacity-[0.03]" : "opacity-[0.03]"

  return (
    <div style={{ perspective: "900px" }} className="select-none">
      <div
        ref={cardRef}
        onMouseMove={onMouseMove}
        onMouseEnter={onMouseEnter}
        onMouseLeave={onMouseLeave}
        className={`premium-card ${cardClass}`}
        style={{ transformStyle: "preserve-3d" }}
      >
        <div className={`absolute inset-0 rounded-2xl ${bgClass}`} />

        {/* Guilloche */}
        <svg
          className={`absolute inset-0 w-full h-full pointer-events-none ${guillocheOpacity}`}
          viewBox="0 0 380 507"
          preserveAspectRatio="none"
        >
          {isDiamond ? (
            <>
              {/* Diamond: geometric faceted pattern */}
              {Array.from({ length: 20 }, (_, i) => (
                <line
                  key={`d-${i}`}
                  x1={i * 20} y1="0" x2={380 - i * 20} y2="507"
                  stroke="currentColor" strokeWidth="0.3"
                  className={c.guilloche}
                />
              ))}
              {Array.from({ length: 20 }, (_, i) => (
                <line
                  key={`d2-${i}`}
                  x1={380 - i * 20} y1="0" x2={i * 20} y2="507"
                  stroke="currentColor" strokeWidth="0.2"
                  className={c.guilloche}
                />
              ))}
              {Array.from({ length: 12 }, (_, i) => (
                <line
                  key={`h-${i}`}
                  x1="0" y1={i * 45} x2="380" y2={i * 45}
                  stroke="currentColor" strokeWidth="0.15"
                  className={c.guilloche}
                />
              ))}
            </>
          ) : isAmbassador ? (
            <>
              {/* Ambassador: sunburst rays from bottom-left */}
              {Array.from({ length: 30 }, (_, i) => {
                const angle = (i * 6) * (Math.PI / 180)
                const x2 = 60 + Math.cos(angle) * 500
                const y2 = 420 - Math.sin(angle) * 500
                return (
                  <line
                    key={`a-${i}`}
                    x1="60" y1="420" x2={x2} y2={y2}
                    stroke="currentColor" strokeWidth={i % 3 === 0 ? "0.4" : "0.2"}
                    className={c.guilloche}
                  />
                )
              })}
              {Array.from({ length: 8 }, (_, i) => (
                <circle
                  key={`ac-${i}`}
                  cx="60" cy="420"
                  r={30 + i * 25}
                  fill="none" stroke="currentColor" strokeWidth="0.2"
                  className={c.guilloche}
                />
              ))}
            </>
          ) : (
            <>
              {Array.from({ length: 25 }, (_, i) => (
                <ellipse
                  key={i} cx="190" cy="360"
                  rx={50 + i * 12} ry={30 + i * 8}
                  fill="none" stroke="currentColor" strokeWidth="0.3"
                  className={c.guilloche}
                />
              ))}
              {Array.from({ length: 15 }, (_, i) => (
                <ellipse
                  key={`r-${i}`} cx="310" cy="440"
                  rx={25 + i * 10} ry={16 + i * 7}
                  fill="none" stroke="currentColor" strokeWidth="0.2"
                  className={c.guilloche}
                  transform={`rotate(${i * 5}, 310, 440)`}
                />
              ))}
            </>
          )}
        </svg>

        {/* Watermark */}
        <div className={`absolute bottom-12 right-5 text-[80px] font-display tracking-wider leading-none pointer-events-none ${c.faint}`}>
          FDY
        </div>

        <div className={glareClass} />

        {/* Content */}
        <div className="relative z-10 flex flex-col h-full p-7 pb-5">

          {/* Logo + Name block */}
          <div className="flex items-start gap-5 stagger-item" style={{ animationDelay: "0ms" }}>
            <div className="shrink-0 mt-1">
              <FoundryLogo height={44} className={c.logo} />
            </div>
            <div className="flex flex-col min-w-0">
              <span className={`text-[9px] tracking-[0.15em] uppercase font-mono ${c.label}`}>
                Foundry
              </span>
              <span className={`text-[22px] font-display leading-tight mt-0.5 ${c.heading}`}>
                {displayName}
              </span>
            </div>
          </div>

          {/* Fields */}
          <div className="mt-6 flex flex-col gap-3 font-mono stagger-item" style={{ animationDelay: "40ms" }}>
            <div className="flex items-baseline gap-3">
              <span className={`text-[9px] tracking-[0.15em] uppercase w-16 shrink-0 ${c.label}`}>Member</span>
              <span className={`text-[13px] ${c.body}`}>{memberSince}</span>
            </div>
            <div className="flex items-baseline gap-3">
              <span className={`text-[9px] tracking-[0.15em] uppercase w-16 shrink-0 ${c.label}`}>Plan</span>
              <span className={`text-[13px] font-medium ${c.heading}`}>
                {plan}
              </span>
            </div>
            {email && (
              <div className="flex items-baseline gap-3">
                <span className={`text-[9px] tracking-[0.15em] uppercase w-16 shrink-0 ${c.label}`}>Email</span>
                <span className={`text-[11px] ${c.body} truncate`}>{email}</span>
              </div>
            )}
            <div className="flex items-baseline gap-3">
              <span className={`text-[9px] tracking-[0.15em] uppercase w-16 shrink-0 ${c.label}`}>ID</span>
              <span className={`text-[11px] ${c.faint}`}>{userId}</span>
            </div>
          </div>

          <div className="flex-1" />

          {/* Stats */}
          <div className="stagger-item" style={{ animationDelay: "80ms" }}>
            <div className={`text-[9px] tracking-[0.15em] uppercase font-mono mb-2.5 ${c.label}`}>
              Builds
            </div>
            <div className="grid grid-cols-2 gap-x-4 gap-y-1.5">
              {stats.map((s, i) => (
                <div key={s.label} className="flex items-center gap-1.5 stagger-item" style={{ animationDelay: `${120 + i * 40}ms` }}>
                  <div
                    className={`size-[11px] rounded-[2px] flex items-center justify-center border ${
                      s.checked ? c.checkFill : c.checkEmpty
                    }`}
                  >
                    {s.checked && (
                      <svg width="7" height="7" viewBox="0 0 8 8">
                        <path d="M1.5 4L3.2 5.7L6.5 2.3" stroke={c.checkStroke} strokeWidth="1.2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
                      </svg>
                    )}
                  </div>
                  <span className={`text-[11px] font-mono ${c.body}`}>
                    {s.value} {s.label}
                  </span>
                </div>
              ))}
            </div>
          </div>

          {/* Footer */}
          <div
            className={`mt-4 pt-3 border-t stagger-item ${c.border}`}
            style={{ animationDelay: "280ms" }}
          >
            <div className="flex items-center justify-between">
              <span className={`text-[9px] tracking-[0.1em] font-mono ${c.faint}`}>
                Foundry — Audio Plugin Certificate
              </span>
              <div className={`size-5 rounded-full border flex items-center justify-center ${c.border}`}>
                <FoundryLogo height={10} className={c.logoFaint} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

const VARIANTS: CardVariant[] = ["default", "gold", "diamond", "ambassador"]

function VariantSelector({ variant, onChange }: { variant: CardVariant; onChange: (v: CardVariant) => void }) {
  return (
    <div className="flex items-center gap-1 p-1 rounded-lg bg-muted/50">
      {VARIANTS.map((v) => {
        const isActive = variant === v
        return (
          <button
            key={v}
            type="button"
            onClick={() => onChange(v)}
            className={`px-3 py-1.5 rounded-md text-[11px] font-mono tracking-wide uppercase transition-all duration-200 ${
              isActive
                ? v === "gold"
                  ? "bg-gradient-to-r from-[#b8963e] to-[#d4b85c] text-white shadow-sm"
                  : v === "diamond"
                    ? "bg-[#b8ccee] text-[#1e2d50] shadow-sm shadow-[rgba(100,160,255,0.2)]"
                    : v === "ambassador"
                      ? "bg-gradient-to-r from-[#cc4800] to-[#f75900] text-white shadow-sm"
                      : "bg-background text-foreground shadow-sm"
                : "text-muted-foreground/60 hover:text-muted-foreground"
            }`}
            style={{ transitionTimingFunction: "cubic-bezier(0.23, 1, 0.32, 1)" }}
          >
            {v === "default" ? "Standard" : v}
          </button>
        )
      })}
    </div>
  )
}

const MAX_INVITES = 5

function InviteButton() {
  const [open, setOpen] = useState(false)
  const [email, setEmail] = useState("")
  const [sending, setSending] = useState(false)
  const [sent, setSent] = useState(false)
  const [remaining, setRemaining] = useState(MAX_INVITES)
  const inputRef = useRef<HTMLInputElement>(null)

  const handleSend = async () => {
    if (!email.includes("@") || sending || remaining <= 0) return

    setSending(true)
    try {
      const count = await assignCardVariantBatch([email.trim()], "gold")
      if (count > 0) {
        setSent(true)
        setRemaining((r) => Math.max(0, r - 1))
        setTimeout(() => {
          setSent(false)
          setEmail("")
          setOpen(false)
        }, 1600)
      }
    } catch {
      // silently fail
    } finally {
      setSending(false)
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="relative group"
        style={{ transitionTimingFunction: "cubic-bezier(0.23, 1, 0.32, 1)" }}
      >
        <div className="relative flex items-center justify-center size-9 rounded-xl bg-muted/60 transition-all duration-200 group-hover:bg-muted group-active:scale-95">
          <Gift className="size-4 text-muted-foreground transition-colors duration-150 group-hover:text-foreground" />
          {remaining > 0 && (
            <span className="absolute -top-1.5 -right-1.5 flex items-center justify-center size-[18px] rounded-full bg-foreground text-background text-[10px] font-mono font-medium leading-none">
              {remaining}
            </span>
          )}
        </div>
      </button>

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-[340px]" showCloseButton={false}>
          <DialogHeader>
            <DialogTitle className="text-[14px]">Invite to Gold</DialogTitle>
            <DialogDescription className="text-[12px]">
              Give someone early beta access. {remaining} invite{remaining !== 1 ? "s" : ""} remaining.
            </DialogDescription>
          </DialogHeader>

          <form
            onSubmit={(e) => {
              e.preventDefault()
              handleSend()
            }}
            className="flex items-center gap-2"
          >
            <Input
              ref={inputRef}
              type="email"
              placeholder="email@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              disabled={sending || sent}
              className="flex-1 text-[13px] font-mono"
              autoFocus
            />
            <Button
              type="submit"
              size="sm"
              disabled={!email.includes("@") || sending || sent || remaining <= 0}
              className="relative overflow-hidden min-w-[72px]"
            >
              <span
                className="flex items-center gap-1.5 transition-all duration-300"
                style={{
                  transform: sent ? "translateY(-24px)" : "translateY(0)",
                  opacity: sent ? 0 : 1,
                  transitionTimingFunction: "cubic-bezier(0.23, 1, 0.32, 1)",
                }}
              >
                <Send className={`size-3.5 transition-transform duration-300 ${sending ? "translate-x-1 -translate-y-1 opacity-0" : ""}`}
                  style={{ transitionTimingFunction: "cubic-bezier(0.23, 1, 0.32, 1)" }}
                />
                <span className="text-[12px]">{sending ? "Sending" : "Send"}</span>
              </span>
              <span
                className="absolute inset-0 flex items-center justify-center transition-all duration-300"
                style={{
                  transform: sent ? "translateY(0)" : "translateY(24px)",
                  opacity: sent ? 1 : 0,
                  transitionTimingFunction: "cubic-bezier(0.23, 1, 0.32, 1)",
                }}
              >
                <Check className="size-4 text-green-400" />
              </span>
            </Button>
          </form>

          {remaining <= 0 && (
            <p className="text-[11px] text-muted-foreground/60 font-mono">
              No invites remaining.
            </p>
          )}
        </DialogContent>
      </Dialog>
    </>
  )
}

export default function Profile() {
  const userProfile = useAppStore((s) => s.userProfile)
  const setUserProfile = useAppStore((s) => s.setUserProfile)
  const variant: CardVariant = userProfile?.cardVariant || "default"

  const handleVariantChange = (v: CardVariant) => {
    if (userProfile) {
      setUserProfile({ ...userProfile, cardVariant: v })
    }
    // Fire-and-forget persist to Supabase
    if (userProfile?.id) {
      updateCardVariant(userProfile.id, v).catch(() => {})
    }
  }

  const variantBlurb: Record<CardVariant, string | null> = {
    default: null,
    gold: "Unlocked for early beta testers who helped shape Foundry from day one. ❤️",
    diamond: "Unlocked for builders who generated 10+ plugins. You're pushing the limits.",
    ambassador: "Awarded to Foundry ambassadors who spread the word and grow the community. ❤️",
  }

  const blurb = variantBlurb[variant]

  return (
    <div className="flex flex-col items-center justify-center h-full gap-6 p-8 overflow-y-auto">
      <PremiumCard variant={variant} />
      <div className="flex flex-col items-center gap-3 stagger-item" style={{ animationDelay: "320ms" }}>
        <VariantSelector variant={variant} onChange={handleVariantChange} />
        {blurb && (
          <p className="text-[11px] text-muted-foreground/60 text-center max-w-[280px] leading-relaxed font-mono">
            {blurb}
          </p>
        )}
      </div>
      <div className="stagger-item" style={{ animationDelay: "360ms" }}>
        <InviteButton />
      </div>
    </div>
  )
}
