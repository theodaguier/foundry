import { useState, useEffect, useCallback } from "react"
import { open } from "@tauri-apps/plugin-dialog"
import { useAppStore } from "@/stores/app-store"
import { useBuildStore } from "@/stores/build-store"
import { useSettingsStore } from "@/stores/settings-store"
import { checkDependencies } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Label } from "@/components/ui/label"
import { Input } from "@/components/ui/input"
import { Separator } from "@/components/ui/separator"
import { Card, CardContent, CardHeader, CardTitle, CardFooter } from "@/components/ui/card"
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs"
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from "@/components/ui/select"
import type { DependencyStatus } from "@/lib/types"
import { Download, FolderOpen, RefreshCw, RotateCcw } from "lucide-react"

function formatDateTime(value?: string | null) {
  if (!value) return "Never"

  try {
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(value))
  } catch {
    return value
  }
}

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`

  const units = ["KB", "MB", "GB"]
  let size = value / 1024
  let unitIndex = 0

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024
    unitIndex += 1
  }

  return `${size.toFixed(size >= 10 ? 0 : 1)} ${units[unitIndex]}`
}

function getUpdateBadgeVariant(status: ReturnType<typeof useSettingsStore.getState>["updateStatus"]) {
  switch (status) {
    case "available":
      return "default"
    case "checking":
    case "downloading":
    case "installing":
      return "secondary"
    case "error":
      return "destructive"
    case "not-available":
      return "outline"
    default:
      return "ghost"
  }
}

function getUpdateStatusLabel(status: ReturnType<typeof useSettingsStore.getState>["updateStatus"]) {
  switch (status) {
    case "checking":
      return "Checking"
    case "available":
      return "Update available"
    case "not-available":
      return "Up to date"
    case "downloading":
      return "Downloading"
    case "installing":
      return "Installing"
    case "error":
      return "Update error"
    default:
      return "Idle"
  }
}

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
  const {
    appearance,
    setAppearance,
    installPaths,
    loadInstallPaths,
    resetInstallPath,
    appVersion,
    loadAppVersion,
    updateStatus,
    availableUpdate,
    lastUpdateCheck,
    updateError,
    downloadProgress,
    checkForAppUpdate,
    installAppUpdate,
    clearUpdateError,
  } = useSettingsStore()
  const isBuildRunning = useBuildStore((s) => s.isRunning)
  const supportsAu = installPaths?.supportedFormats.includes("AU") ?? false
  const supportsVst3 = installPaths?.supportedFormats.includes("VST3") ?? false
  const isCheckingForUpdates = updateStatus === "checking"
  const isInstallingUpdate = updateStatus === "downloading" || updateStatus === "installing"

  useEffect(() => { loadInstallPaths() }, [loadInstallPaths])
  useEffect(() => { void loadAppVersion() }, [loadAppVersion])

  const chooseFolder = async (format: string) => {
    const selection = await open({ directory: true, multiple: false })
    if (typeof selection !== "string") return
    await useSettingsStore.getState().setInstallPath(format, selection)
  }

  const handleCheckForUpdates = async () => {
    clearUpdateError()
    await checkForAppUpdate(true)
  }

  const handleInstallUpdate = async () => {
    clearUpdateError()
    await installAppUpdate()
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
          {supportsAu && (
            <div className="flex flex-col gap-1.5">
              <Label className="text-xs text-muted-foreground">AU Components</Label>
              <div className="flex items-center gap-2">
                <Input
                  readOnly
                  value={installPaths?.auPath ?? ""}
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
          )}

          {supportsVst3 && (
            <div className="flex flex-col gap-1.5">
              <Label className="text-xs text-muted-foreground">VST3 Plugins</Label>
              <div className="flex items-center gap-2">
                <Input
                  readOnly
                  value={installPaths?.vst3Path ?? ""}
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
          )}
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

      <div className="flex flex-col gap-3">
        <Label>App updates</Label>
        <Card size="sm">
          <CardContent className="flex flex-col gap-3 text-sm">
            <div className="flex items-center justify-between gap-3">
              <div className="min-w-0">
                <div>Desktop updater</div>
                <div className="text-xs text-muted-foreground">
                  Last checked {formatDateTime(lastUpdateCheck)}
                </div>
              </div>
              <Badge variant={getUpdateBadgeVariant(updateStatus)}>
                {getUpdateStatusLabel(updateStatus)}
              </Badge>
            </div>

            {availableUpdate ? (
              <div className="rounded-lg border border-border/60 bg-muted/30 p-3">
                <div className="flex items-center justify-between gap-3">
                  <div className="text-sm">Version {availableUpdate.version}</div>
                  <div className="text-[11px] text-muted-foreground">
                    {formatDateTime(availableUpdate.date)}
                  </div>
                </div>
                {availableUpdate.notes && (
                  <p className="mt-2 text-xs text-muted-foreground whitespace-pre-wrap">
                    {availableUpdate.notes}
                  </p>
                )}
              </div>
            ) : (
              <div className="text-xs text-muted-foreground">
                {updateStatus === "not-available"
                  ? "Foundry is already on the latest published version."
                  : "Checks GitHub Releases for signed desktop updates."}
              </div>
            )}

            {downloadProgress && (
              <div className="rounded-lg border border-border/60 bg-muted/30 p-3 text-xs text-muted-foreground">
                Downloaded {formatBytes(downloadProgress.downloaded)}
                {downloadProgress.total
                  ? ` of ${formatBytes(downloadProgress.total)}`
                  : ""}
              </div>
            )}

            {isBuildRunning && availableUpdate && (
              <div className="rounded-lg border border-border/60 bg-muted/30 p-3 text-xs text-muted-foreground">
                Finish the current build before installing the app update.
              </div>
            )}

            {updateError && (
              <div className="rounded-lg border border-destructive/20 bg-destructive/5 p-3 text-xs text-destructive">
                {updateError}
              </div>
            )}
          </CardContent>
          <CardFooter className="flex flex-wrap justify-end gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => void handleCheckForUpdates()}
              disabled={isCheckingForUpdates || isInstallingUpdate}
            >
              <RefreshCw className="size-3.5" />
              {isCheckingForUpdates ? "Checking..." : "Check for updates"}
            </Button>

            {availableUpdate && (
              <Button
                size="sm"
                onClick={() => void handleInstallUpdate()}
                disabled={isBuildRunning || isInstallingUpdate}
              >
                <Download className="size-3.5" />
                {updateStatus === "downloading"
                  ? "Downloading..."
                  : updateStatus === "installing"
                    ? "Installing..."
                    : "Install update"}
              </Button>
            )}
          </CardFooter>
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
  const buildEnvironment = useSettingsStore((s) => s.buildEnvironment)
  const loadBuildEnvironment = useSettingsStore((s) => s.loadBuildEnvironment)
  const installManagedJuce = useSettingsStore((s) => s.installManagedJuce)
  const setJuceOverride = useSettingsStore((s) => s.setJuceOverride)
  const clearJuceOverride = useSettingsStore((s) => s.clearJuceOverride)
  const isPreparingEnvironment = useSettingsStore((s) => s.isPreparingEnvironment)
  const isLoadingBuildEnvironment = useSettingsStore((s) => s.isLoadingBuildEnvironment)

  const optionalDeps = new Set(["Codex CLI"])

  const refreshDeps = useCallback(async () => {
    try {
      const next = await checkDependencies()
      setDeps(next)
    } catch {
      setDeps([])
    }
  }, [])

  useEffect(() => {
    void refreshDeps()
    void loadBuildEnvironment()
  }, [refreshDeps, loadBuildEnvironment])

  const chooseJuceFolder = useCallback(async () => {
    const selection = await open({ directory: true, multiple: false })
    if (typeof selection !== "string") return
    await setJuceOverride(selection)
    await refreshDeps()
  }, [refreshDeps, setJuceOverride])

  const installManagedCopy = useCallback(async () => {
    await installManagedJuce()
    await refreshDeps()
  }, [installManagedJuce, refreshDeps])

  const restoreManagedCopy = useCallback(async () => {
    await clearJuceOverride()
    await refreshDeps()
  }, [clearJuceOverride, refreshDeps])

  const recheckEnvironment = useCallback(async () => {
    await Promise.all([refreshDeps(), loadBuildEnvironment()])
  }, [loadBuildEnvironment, refreshDeps])

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-3">
        <Label>Build Environment</Label>
        <Card size="sm">
          <CardContent className="flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <div>
                <div className="text-sm">JUCE SDK</div>
                <div className="text-xs text-muted-foreground">
                  {buildEnvironment?.jucePath
                    ? `${buildEnvironment.juceVersion} · ${buildEnvironment.juceSource === "override" ? "custom path" : "managed copy"}`
                    : "Not configured"}
                </div>
              </div>
              <Badge variant={buildEnvironment?.state === "ready" ? "default" : "destructive"}>
                {isLoadingBuildEnvironment ? "Checking..." : buildEnvironment?.state === "ready" ? "Ready" : "Blocked"}
              </Badge>
            </div>

            {buildEnvironment?.jucePath && (
              <div className="text-xs font-mono text-muted-foreground break-all">
                {buildEnvironment.jucePath}
              </div>
            )}

            {buildEnvironment?.issues.length ? (
              <div className="flex flex-col gap-2">
                {buildEnvironment.issues.map((issue) => (
                  <div key={issue.code} className="rounded-lg border border-border/60 bg-muted/40 p-3">
                    <div className="text-sm">{issue.title}</div>
                    <div className="text-xs text-muted-foreground mt-1">{issue.detail}</div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-xs text-muted-foreground">
                The build toolchain and managed JUCE copy are ready.
              </div>
            )}

            <div className="flex flex-wrap gap-2">
              <Button variant="outline" size="sm" onClick={recheckEnvironment} disabled={isPreparingEnvironment}>
                Re-check
              </Button>
              <Button size="sm" onClick={installManagedCopy} disabled={isPreparingEnvironment}>
                {isPreparingEnvironment ? "Preparing..." : "Install Managed JUCE"}
              </Button>
              <Button variant="secondary" size="sm" onClick={chooseJuceFolder} disabled={isPreparingEnvironment}>
                Choose JUCE Folder
              </Button>
              {buildEnvironment?.juceSource === "override" && (
                <Button variant="ghost" size="sm" onClick={restoreManagedCopy} disabled={isPreparingEnvironment}>
                  Use Managed Copy
                </Button>
              )}
            </div>
          </CardContent>
        </Card>
      </div>

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
                  {optionalDeps.has(dep.name) && !dep.installed ? (
                    <Badge variant="secondary">Optional</Badge>
                  ) : (
                    <Badge variant={dep.installed ? "default" : "destructive"}>
                      {dep.installed ? "Installed" : "Missing"}
                    </Badge>
                  )}
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
