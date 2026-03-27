"use client"

import { useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

export default function LoginPage() {
  const [pw, setPw] = useState("")
  const [error, setError] = useState(false)
  const [loading, setLoading] = useState(false)
  const router = useRouter()
  const params = useSearchParams()

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    const res = await fetch("/api/auth", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password: pw }),
    })
    setLoading(false)
    if (res.ok) router.push(params.get("from") ?? "/")
    else { setError(true); setPw("") }
  }

  return (
    <div className="min-h-screen flex items-center justify-center">
      <Card className="w-72">
        <CardHeader>
          <CardTitle className="text-sm tracking-widest font-normal">FOUNDRY DASHBOARD</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-3">
            <Input
              type="password"
              value={pw}
              onChange={(e) => { setPw(e.target.value); setError(false) }}
              placeholder="Password"
              autoFocus
              className={error ? "border-destructive" : ""}
            />
            {error && <p className="text-xs text-destructive">Wrong password</p>}
            <Button type="submit" variant="outline" size="sm" className="w-full" disabled={loading}>
              {loading ? "…" : "Enter"}
            </Button>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}
