import { useState, useEffect } from "react"
import { useNavigate } from "react-router-dom"
import { Button } from "@/components/ui/button"
import { FoundryLogo } from "@/components/app/foundry-logo"

export default function Welcome() {
  const navigate = useNavigate()
  const [logoAppeared, setLogoAppeared] = useState(false)
  const [textAppeared, setTextAppeared] = useState(false)
  const [btnAppeared, setBtnAppeared] = useState(false)

  useEffect(() => {
    const t1 = setTimeout(() => setLogoAppeared(true), 50)
    const t2 = setTimeout(() => setTextAppeared(true), 200)
    const t3 = setTimeout(() => setBtnAppeared(true), 350)
    return () => { clearTimeout(t1); clearTimeout(t2); clearTimeout(t3) }
  }, [])

  return (
    <div className="flex flex-col items-center justify-center h-full gap-5">
      <div
        className="transition-all duration-500"
        style={{ opacity: logoAppeared ? 1 : 0, transform: logoAppeared ? "scale(1)" : "scale(0.92)" }}
      >
        <FoundryLogo height={48} className="text-muted-foreground" />
      </div>

      <div
        className="flex flex-col items-center gap-1.5 transition-all duration-[350ms]"
        style={{ opacity: textAppeared ? 1 : 0, transform: textAppeared ? "translateY(0)" : "translateY(4px)" }}
      >
        <h2 className="text-xl font-medium">Welcome to Foundry</h2>
        <p className="text-sm text-muted-foreground text-center">
          AI-powered audio plugin generator.<br />Describe it, build it, play it.
        </p>
      </div>

      <div
        className="pt-2 transition-all duration-[350ms]"
        style={{ opacity: btnAppeared ? 1 : 0, transform: btnAppeared ? "translateY(0)" : "translateY(6px)" }}
      >
        <Button size="lg" onClick={() => navigate("/prompt")}>
          Build Your First Plugin
        </Button>
      </div>
    </div>
  )
}
