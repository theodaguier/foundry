import { useState, useEffect } from "react"
import { useNavigate } from "react-router-dom"
import { open } from "@tauri-apps/plugin-dialog"
import { useAppStore } from "@/stores/app-store"
import { useSettingsStore } from "@/stores/settings-store"
import { checkDependencies, showInFinder } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { SectionLabel } from "@/components/app/section-label"
import type { DependencyStatus } from "@/lib/types"

type Tab = "general" | "models" | "dependencies" | "account"
const tabItems: Tab[] = ["general", "models", "dependencies", "account"]
const tabLabels: Record<Tab, string> = { general: "General", models: "Models", dependencies: "Dependencies", account: "Account" }

export default function Settings() {
  const navigate = useNavigate()
  const [tab, setTab] = useState<Tab>("general")

  return (
    <div className="flex flex-col h-full max-w-[480px] mx-auto py-8 px-6">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-lg font-medium">Settings</h2>
        <Button variant="ghost" onClick={() => navigate("/")}>Done</Button>
      </div>

      <div className="flex mb-6 border-b border-border">
        {tabItems.map((t, i) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className="relative flex flex-col items-center"
            style={{ marginLeft: i === 0 ? 0 : 24 }}
          >
            <span className={`pb-2 text-[11px] tracking-[0.5px] font-mono transition-colors ${
              tab === t ? "text-foreground" : "text-muted-foreground hover:text-foreground"
            }`}>
              {tabLabels[t]}
            </span>
            <div className={`absolute bottom-0 left-0 right-0 h-[2px] ${tab === t ? "bg-primary" : "bg-transparent"}`} />
          </button>
        ))}
      </div>

      <div className="flex-1 overflow-y-auto">
        {tab === "general" && <GeneralTab />}
        {tab === "models" && <ModelsTab />}
        {tab === "dependencies" && <DependenciesTab />}
        {tab === "account" && <AccountTab />}
      </div>
    </div>
  )
}

function GeneralTab() {
  const { appearance, setAppearance } = useSettingsStore()
  const pluginPaths = [
    { label: "AU Components", path: "~/Library/Audio/Plug-Ins/Components/" },
    { label: "VST3 Plugins", path: "~/Library/Audio/Plug-Ins/VST3/" },
    { label: "Plugin Data", path: "~/Library/Application Support/Foundry/" },
  ]

  return (
    <div className="flex flex-col gap-6">
      <section>
        <SectionLabel>Appearance</SectionLabel>
        <div className="flex rounded-md overflow-hidden border border-border">
          {(["system", "light", "dark"] as const).map((a) => (
            <button
              key={a}
              onClick={() => setAppearance(a)}
              className={`flex-1 py-2 text-[12px] capitalize transition-colors ${
                appearance === a
                  ? "bg-primary text-primary-foreground"
                  : "bg-muted text-muted-foreground hover:text-foreground"
              }`}
            >
              {a === "system" ? "System" : a === "light" ? "Light" : "Dark"}
            </button>
          ))}
        </div>
      </section>

      <section>
        <SectionLabel>Plugin Paths</SectionLabel>
        <div className="flex flex-col divide-y divide-border border border-border rounded-md overflow-hidden">
          {pluginPaths.map((item) => (
            <div key={item.label} className="flex items-center justify-between px-3 py-2.5 bg-muted">
              <span className="text-[12px] text-foreground">{item.label}</span>
              <span className="text-[11px] font-mono text-muted-foreground select-text">{item.path}</span>
            </div>
          ))}
        </div>
      </section>

      <section>
        <SectionLabel>About</SectionLabel>
        <div className="flex flex-col divide-y divide-border border border-border rounded-md overflow-hidden">
          <div className="flex items-center justify-between px-3 py-2.5 bg-muted">
            <span className="text-[12px] text-foreground">Version</span>
            <span className="text-[12px] text-muted-foreground">1.0.0</span>
          </div>
          <div className="flex items-center justify-between px-3 py-2.5 bg-muted">
            <span className="text-[12px] text-foreground">Build</span>
            <span className="text-[12px] text-muted-foreground">1</span>
          </div>
        </div>
      </section>
    </div>
  )
}

function ModelsTab() {
  const { modelCatalog, loadCatalog, refreshModels, isRefreshing } = useSettingsStore()
  useEffect(() => { loadCatalog() }, [loadCatalog])

  return (
    <div className="flex flex-col gap-4">
      {modelCatalog.map((provider) => (
        <section key={provider.id}>
          <SectionLabel>{provider.name}</SectionLabel>
          <div className="flex flex-col divide-y divide-border border border-border rounded-md overflow-hidden">
            {provider.models.map((model) => (
              <div key={model.id} className="flex items-center gap-3 px-3 py-2.5 bg-muted">
                <div className="flex-1">
                  <div className="text-[12px] text-foreground">{model.name}</div>
                  <div className="text-[11px] text-muted-foreground">{model.subtitle}</div>
                </div>
                {model.default && <Badge variant="secondary">Default</Badge>}
                <span className="text-[10px] font-mono text-muted-foreground/60">{model.flag}</span>
              </div>
            ))}
          </div>
        </section>
      ))}
      <Button variant="ghost" onClick={refreshModels} disabled={isRefreshing} className="self-start text-primary">
        {isRefreshing ? "Refreshing..." : "Refresh Models"}
      </Button>
    </div>
  )
}

function DependenciesTab() {
  const [deps, setDeps] = useState<DependencyStatus[]>([])
  const buildEnvironment = useSettingsStore((s) => s.buildEnvironment)
  const isLoadingBuildEnvironment = useSettingsStore((s) => s.isLoadingBuildEnvironment)
  const isPreparingEnvironment = useSettingsStore((s) => s.isPreparingEnvironment)
  const loadBuildEnvironment = useSettingsStore((s) => s.loadBuildEnvironment)
  const installManagedJuce = useSettingsStore((s) => s.installManagedJuce)
  const setJuceOverride = useSettingsStore((s) => s.setJuceOverride)
  const clearJuceOverride = useSettingsStore((s) => s.clearJuceOverride)

  const refresh = async () => {
    await Promise.all([
      loadBuildEnvironment(),
      checkDependencies().then(setDeps).catch(() => setDeps([])),
    ])
  }

  useEffect(() => { void refresh() }, [])

  const chooseJuceFolder = async () => {
    const selection = await open({ directory: true, multiple: false })
    if (typeof selection !== "string") return
    await setJuceOverride(selection)
    await refresh()
  }

  const installManaged = async () => {
    await installManagedJuce()
    await refresh()
  }

  const useManaged = async () => {
    await clearJuceOverride()
    await refresh()
  }

  return (
    <div className="flex flex-col gap-4">
      <section>
        <SectionLabel>JUCE Environment</SectionLabel>
        <div className="flex flex-col gap-3 border border-border rounded-md bg-muted p-3">
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <div className="text-[12px] text-foreground">Managed JUCE {buildEnvironment?.juceVersion ?? "8.0.12"}</div>
              <div className="text-[11px] text-muted-foreground">
                {isLoadingBuildEnvironment ? "Checking environment..." : buildEnvironment?.jucePath ?? "No validated JUCE path yet"}
              </div>
            </div>
            <Badge
              variant={buildEnvironment?.state === "ready" ? "default" : "destructive"}
            >
              {buildEnvironment?.state === "ready" ? "Ready" : "Blocked"}
            </Badge>
          </div>

          <div className="grid grid-cols-[96px_1fr] gap-x-3 gap-y-1 text-[11px]">
            <span className="text-muted-foreground">Source</span>
            <span className="text-foreground capitalize">{buildEnvironment?.juceSource ?? "none"}</span>
            <span className="text-muted-foreground">Path</span>
            <span className="text-foreground break-all">{buildEnvironment?.jucePath ?? "Not resolved"}</span>
            <span className="text-muted-foreground">Version</span>
            <span className="text-foreground">{buildEnvironment?.juceVersion ?? "8.0.12"}</span>
          </div>

          {(buildEnvironment?.issues.length ?? 0) > 0 && (
            <div className="flex flex-col gap-2 border border-border rounded-md bg-card/40 p-2.5">
              {buildEnvironment?.issues.map((issue) => (
                <div key={issue.code} className="flex items-start gap-2.5">
                  <span className={`mt-1 h-2 w-2 rounded-full ${issue.recoverable ? "bg-amber-500" : "bg-destructive"}`} />
                  <div className="min-w-0">
                    <div className="text-[12px] text-foreground">{issue.title}</div>
                    <div className="text-[11px] text-muted-foreground break-words">{issue.detail}</div>
                  </div>
                </div>
              ))}
            </div>
          )}

          <div className="flex flex-wrap gap-2">
            <Button onClick={installManaged} disabled={isPreparingEnvironment}>
              {isPreparingEnvironment ? "Installing..." : "Install / Reinstall JUCE"}
            </Button>
            <Button variant="secondary" onClick={chooseJuceFolder} disabled={isPreparingEnvironment}>
              Choose JUCE Folder
            </Button>
            <Button variant="ghost" onClick={useManaged} disabled={isPreparingEnvironment}>
              Use Managed Copy
            </Button>
            <Button
              variant="ghost"
              onClick={() => buildEnvironment?.jucePath && showInFinder(buildEnvironment.jucePath)}
              disabled={!buildEnvironment?.jucePath}
            >
              Reveal in Finder
            </Button>
          </div>
        </div>
      </section>

      <section>
        <SectionLabel>Required</SectionLabel>
        <div className="flex flex-col divide-y divide-border border border-border rounded-md overflow-hidden">
          {deps.map((dep) => (
            <div key={dep.name} className="flex items-center gap-3 px-3 py-2.5 bg-muted">
              <span className={`w-2 h-2 rounded-full shrink-0 ${dep.installed ? "bg-success" : "bg-destructive"}`} />
              <div className="flex-1 min-w-0">
                <div className="text-[12px] text-foreground">{dep.name}</div>
                {dep.detail && <div className="text-[11px] text-muted-foreground truncate">{dep.detail}</div>}
              </div>
              <Badge variant={dep.installed ? "default" : "destructive"}>
                {dep.installed ? "Installed" : "Missing"}
              </Badge>
            </div>
          ))}
        </div>
      </section>
    </div>
  )
}

function AccountTab() {
  const signOut = useAppStore((s) => s.signOut)
  const userProfile = useAppStore((s) => s.userProfile)

  return (
    <div className="flex flex-col gap-4">
      {userProfile && (
        <div className="text-[12px] text-muted-foreground">
          Signed in as {userProfile.email || userProfile.displayName || userProfile.id}
        </div>
      )}
      <Button variant="ghost" onClick={signOut} className="self-start text-destructive">Sign Out</Button>
    </div>
  )
}
