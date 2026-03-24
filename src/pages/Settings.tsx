import { useState, useEffect } from "react"
import { useNavigate } from "react-router-dom"
import { open } from "@tauri-apps/plugin-dialog"
import { useAppStore } from "@/stores/app-store"
import { useSettingsStore } from "@/stores/settings-store"
import { checkDependencies, showInFinder } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"
import type { DependencyStatus } from "@/lib/types"
import { FolderOpen, RotateCcw } from "lucide-react"

export default function Settings() {
  const navigate = useNavigate()

  return (
    <div className="flex flex-col h-full max-w-[520px] mx-auto py-8 px-6">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-base font-medium">Settings</h2>
        <Button variant="ghost" size="sm" onClick={() => navigate("/")}>Done</Button>
      </div>

      <Tabs defaultValue="general">
        <TabsList variant="line">
          <TabsTrigger value="general">General</TabsTrigger>
          <TabsTrigger value="models">Models</TabsTrigger>
          <TabsTrigger value="dependencies">Dependencies</TabsTrigger>
          <TabsTrigger value="account">Account</TabsTrigger>
        </TabsList>

        <div className="mt-4 flex-1 overflow-y-auto">
          <TabsContent value="general"><GeneralTab /></TabsContent>
          <TabsContent value="models"><ModelsTab /></TabsContent>
          <TabsContent value="dependencies"><DependenciesTab /></TabsContent>
          <TabsContent value="account"><AccountTab /></TabsContent>
        </div>
      </Tabs>
    </div>
  )
}

function GeneralTab() {
  const { appearance, setAppearance, installPaths, loadInstallPaths, resetInstallPath } = useSettingsStore()

  useEffect(() => { loadInstallPaths() }, [loadInstallPaths])

  const chooseFolder = async (format: string) => {
    const selection = await open({ directory: true, multiple: false })
    if (typeof selection !== "string") return
    await useSettingsStore.getState().setInstallPath(format, selection)
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-3">
        <Label>Appearance</Label>
        <Select value={appearance} onValueChange={(v) => v && setAppearance(v as typeof appearance)}>
          <SelectTrigger className="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="system">System</SelectItem>
            <SelectItem value="light">Light</SelectItem>
            <SelectItem value="dark">Dark</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <Separator />

      <div className="flex flex-col gap-3">
        <Label>Plugin install paths</Label>
        <p className="text-xs text-muted-foreground -mt-1">
          Choose where Foundry installs compiled plugins. DAWs scan these directories to discover your plugins.
        </p>

        <div className="flex flex-col gap-2">
          <div className="flex flex-col gap-1.5">
            <span className="text-xs text-muted-foreground">AU Components</span>
            <div className="flex items-center gap-2">
              <div className="flex-1 min-w-0 rounded-lg border border-input bg-transparent px-2.5 py-1.5 text-sm text-foreground truncate">
                {installPaths?.auPath ?? "/Library/Audio/Plug-Ins/Components"}
              </div>
              <Button variant="outline" size="sm" onClick={() => chooseFolder("AU")}>
                <FolderOpen className="size-3.5" />
              </Button>
              {installPaths && !installPaths.auIsDefault && (
                <Button variant="ghost" size="sm" onClick={() => resetInstallPath("AU")}>
                  <RotateCcw className="size-3.5" />
                </Button>
              )}
            </div>
          </div>

          <div className="flex flex-col gap-1.5">
            <span className="text-xs text-muted-foreground">VST3 Plugins</span>
            <div className="flex items-center gap-2">
              <div className="flex-1 min-w-0 rounded-lg border border-input bg-transparent px-2.5 py-1.5 text-sm text-foreground truncate">
                {installPaths?.vst3Path ?? "/Library/Audio/Plug-Ins/VST3"}
              </div>
              <Button variant="outline" size="sm" onClick={() => chooseFolder("VST3")}>
                <FolderOpen className="size-3.5" />
              </Button>
              {installPaths && !installPaths.vst3IsDefault && (
                <Button variant="ghost" size="sm" onClick={() => resetInstallPath("VST3")}>
                  <RotateCcw className="size-3.5" />
                </Button>
              )}
            </div>
          </div>
        </div>
      </div>

      <Separator />

      <div className="flex flex-col gap-3">
        <Label>About</Label>
        <div className="flex flex-col gap-1 text-sm">
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground">Version</span>
            <span>1.0.0</span>
          </div>
          <div className="flex items-center justify-between">
            <span className="text-muted-foreground">Build</span>
            <span>1</span>
          </div>
        </div>
      </div>
    </div>
  )
}

function ModelsTab() {
  const { modelCatalog, loadCatalog, refreshModels, isRefreshing } = useSettingsStore()
  useEffect(() => { loadCatalog() }, [loadCatalog])

  return (
    <div className="flex flex-col gap-5">
      {modelCatalog.map((provider) => (
        <div key={provider.id} className="flex flex-col gap-2">
          <Label>{provider.name}</Label>
          <div className="flex flex-col rounded-lg border border-border overflow-hidden">
            {provider.models.map((model, i) => (
              <div key={model.id}>
                {i > 0 && <Separator />}
                <div className="flex items-center gap-3 px-3 py-2.5">
                  <div className="flex-1 min-w-0">
                    <div className="text-sm">{model.name}</div>
                    <div className="text-xs text-muted-foreground">{model.subtitle}</div>
                  </div>
                  {model.default && <Badge variant="secondary">Default</Badge>}
                  <span className="text-[10px] font-mono text-muted-foreground/60">{model.flag}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      ))}
      <Button variant="outline" size="sm" onClick={refreshModels} disabled={isRefreshing} className="self-start">
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
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <Label>JUCE Environment</Label>
          <Badge variant={buildEnvironment?.state === "ready" ? "default" : "destructive"}>
            {buildEnvironment?.state === "ready" ? "Ready" : "Blocked"}
          </Badge>
        </div>

        <div className="rounded-lg border border-border p-3 flex flex-col gap-3">
          <div className="flex flex-col gap-1 text-sm">
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Source</span>
              <span className="capitalize">{buildEnvironment?.juceSource ?? "none"}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Path</span>
              <span className="text-xs truncate max-w-[260px]">
                {isLoadingBuildEnvironment ? "Checking..." : buildEnvironment?.jucePath ?? "Not resolved"}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Version</span>
              <span>{buildEnvironment?.juceVersion ?? "8.0.12"}</span>
            </div>
          </div>

          {(buildEnvironment?.issues.length ?? 0) > 0 && (
            <>
              <Separator />
              <div className="flex flex-col gap-2">
                {buildEnvironment?.issues.map((issue) => (
                  <div key={issue.code} className="flex items-start gap-2">
                    <span className={`mt-1.5 size-2 rounded-full shrink-0 ${issue.recoverable ? "bg-amber-500" : "bg-destructive"}`} />
                    <div className="min-w-0">
                      <div className="text-sm">{issue.title}</div>
                      <div className="text-xs text-muted-foreground break-words">{issue.detail}</div>
                    </div>
                  </div>
                ))}
              </div>
            </>
          )}

          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={installManaged} disabled={isPreparingEnvironment}>
              {isPreparingEnvironment ? "Installing..." : "Install / Reinstall"}
            </Button>
            <Button variant="outline" size="sm" onClick={chooseJuceFolder} disabled={isPreparingEnvironment}>
              Choose Folder
            </Button>
            <Button variant="ghost" size="sm" onClick={useManaged} disabled={isPreparingEnvironment}>
              Use Managed
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => buildEnvironment?.jucePath && showInFinder(buildEnvironment.jucePath)}
              disabled={!buildEnvironment?.jucePath}
            >
              Reveal in Finder
            </Button>
          </div>
        </div>
      </div>

      <Separator />

      <div className="flex flex-col gap-3">
        <Label>Required</Label>
        <div className="flex flex-col rounded-lg border border-border overflow-hidden">
          {deps.map((dep, i) => (
            <div key={dep.name}>
              {i > 0 && <Separator />}
              <div className="flex items-center gap-3 px-3 py-2.5">
                <span className={`size-2 rounded-full shrink-0 ${dep.installed ? "bg-emerald-500" : "bg-destructive"}`} />
                <div className="flex-1 min-w-0">
                  <div className="text-sm">{dep.name}</div>
                  {dep.detail && <div className="text-xs text-muted-foreground truncate">{dep.detail}</div>}
                </div>
                <Badge variant={dep.installed ? "default" : "destructive"}>
                  {dep.installed ? "Installed" : "Missing"}
                </Badge>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function AccountTab() {
  const signOut = useAppStore((s) => s.signOut)
  const userProfile = useAppStore((s) => s.userProfile)

  return (
    <div className="flex flex-col gap-4">
      {userProfile && (
        <p className="text-sm text-muted-foreground">
          Signed in as {userProfile.email || userProfile.displayName || userProfile.id}
        </p>
      )}
      <Button variant="outline" size="sm" onClick={signOut} className="self-start text-destructive">
        Sign Out
      </Button>
    </div>
  )
}
