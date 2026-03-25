import { useState, useEffect, useCallback } from "react"
import { getVersion } from "@tauri-apps/api/app"
import { open } from "@tauri-apps/plugin-dialog"
import { useAppStore } from "@/stores/app-store"
import { useSettingsStore } from "@/stores/settings-store"
import { checkDependencies, showInFinder } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Separator } from "@/components/ui/separator"
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"
import type { DependencyStatus } from "@/lib/types"
import { FolderOpen, RotateCcw } from "lucide-react"

export default function Settings() {
  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-[520px] mx-auto py-8 px-6">
        <div className="mb-6">
          <h2 className="text-base font-[ArchitypeStedelijk] uppercase tracking-[0.5px]">Settings</h2>
        </div>

        <Tabs defaultValue="general">
          <TabsList>
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
    </div>
  )
}

function GeneralTab() {
  const { appearance, setAppearance, installPaths, loadInstallPaths, resetInstallPath } = useSettingsStore()
  const [appVersion, setAppVersion] = useState<string>("")

  useEffect(() => { loadInstallPaths() }, [loadInstallPaths])
  useEffect(() => { getVersion().then(setAppVersion) }, [])

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
            <Label className="text-xs text-muted-foreground">AU Components</Label>
            <div className="flex items-center gap-2">
              <Input
                readOnly
                value={installPaths?.auPath ?? "/Library/Audio/Plug-Ins/Components"}
                className="flex-1 cursor-default"
              />
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
            <Label className="text-xs text-muted-foreground">VST3 Plugins</Label>
            <div className="flex items-center gap-2">
              <Input
                readOnly
                value={installPaths?.vst3Path ?? "/Library/Audio/Plug-Ins/VST3"}
                className="flex-1 cursor-default"
              />
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
        <Card size="sm">
          <CardContent className="flex flex-col gap-1 text-sm">
            <div className="flex items-center justify-between">
              <span className="text-muted-foreground">Version</span>
              <span>{appVersion || "—"}</span>
            </div>
          </CardContent>
        </Card>
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
          <Card size="sm">
            <CardContent className="flex flex-col">
              {provider.models.map((model, i) => (
                <div key={model.id}>
                  {i > 0 && <Separator />}
                  <div className="flex items-center gap-3 py-2.5">
                    <div className="flex-1 min-w-0">
                      <div className="text-sm">{model.name}</div>
                      <div className="text-xs text-muted-foreground">{model.subtitle}</div>
                    </div>
                    {model.default && <Badge variant="secondary">Default</Badge>}
                    <span className="text-[10px] font-mono text-muted-foreground/60">{model.flag}</span>
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>
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

  useEffect(() => {
    checkDependencies().then(setDeps).catch(() => setDeps([]))
  }, [])

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-3">
        <Label>Required</Label>
        <Card size="sm">
          <CardContent className="flex flex-col">
            {deps.map((dep, i) => (
              <div key={dep.name}>
                {i > 0 && <Separator />}
                <div className="flex items-center gap-3 py-2.5">
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
          </CardContent>
        </Card>
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
