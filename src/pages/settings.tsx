import { useState, useEffect, useCallback } from "react";
import { toast } from "sonner";
import { open } from "@tauri-apps/plugin-dialog";
import { useAppStore } from "@/stores/app-store";
import { useBuildStore } from "@/stores/build-store";
import { useSettingsStore } from "@/stores/settings-store";
import {
  invalidateAndCheckDependencies,
  installDependency,
  launchClaudeAuth,
  launchCodexAuth,
  resetDebugDependencies,
} from "@/lib/commands";
import { interpretDependencyInstallResult } from "@/lib/dependency-install";
import { cn } from "@/lib/utils";
import { AgentIcon } from "@/components/app/agent-icon";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Label } from "@/components/ui/label";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardFooter,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import {
  Select,
  SelectTrigger,
  SelectValue,
  SelectContent,
  SelectItem,
} from "@/components/ui/select";
import type { DependencyStatus } from "@/lib/types";
import {
  Download,
  FolderOpen,
  Loader2,
  RefreshCw,
  RotateCcw,
  Trash2,
} from "lucide-react";

function formatDateTime(value?: string | null) {
  if (!value) return "Never";

  try {
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: "medium",
      timeStyle: "short",
    }).format(new Date(value));
  } catch {
    return value;
  }
}

function formatBytes(value: number) {
  if (value < 1024) return `${value} B`;

  const units = ["KB", "MB", "GB"];
  let size = value / 1024;
  let unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }

  return `${size.toFixed(size >= 10 ? 0 : 1)} ${units[unitIndex]}`;
}

function getUpdateBadgeVariant(
  status: ReturnType<typeof useSettingsStore.getState>["updateStatus"],
) {
  switch (status) {
    case "available":
      return "default";
    case "checking":
    case "downloading":
    case "installing":
      return "secondary";
    case "error":
      return "destructive";
    case "not-available":
      return "outline";
    default:
      return "ghost";
  }
}

function getUpdateStatusLabel(
  status: ReturnType<typeof useSettingsStore.getState>["updateStatus"],
) {
  switch (status) {
    case "checking":
      return "Checking";
    case "available":
      return "Update available";
    case "not-available":
      return "Up to date";
    case "downloading":
      return "Downloading";
    case "installing":
      return "Installing";
    case "error":
      return "Update error";
    default:
      return "Idle";
  }
}

export default function Settings() {
  return (
    <div className="h-full overflow-y-auto">
      <div className="w-full py-8 px-6">
        <div className="mb-6">
          <h2 className="text-lg font-[ArchitypeStedelijk] uppercase tracking-[1px]">
            Settings
          </h2>
        </div>

        <Tabs defaultValue="general">
          <TabsList>
            <TabsTrigger value="general">General</TabsTrigger>
            <TabsTrigger value="models">Models</TabsTrigger>
            <TabsTrigger value="dependencies">Dependencies</TabsTrigger>
            <TabsTrigger value="account">Account</TabsTrigger>
          </TabsList>

          <div className="mt-4 flex-1 overflow-y-auto">
            <TabsContent value="general">
              <GeneralTab />
            </TabsContent>
            <TabsContent value="models">
              <ModelsTab />
            </TabsContent>
            <TabsContent value="dependencies">
              <DependenciesTab />
            </TabsContent>
            <TabsContent value="account">
              <AccountTab />
            </TabsContent>
          </div>
        </Tabs>
      </div>
    </div>
  );
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
  } = useSettingsStore();
  const isBuildRunning = useBuildStore((s) => s.isRunning);
  const supportsAu = installPaths?.supportedFormats.includes("AU") ?? false;
  const supportsVst3 = installPaths?.supportedFormats.includes("VST3") ?? false;
  const isCheckingForUpdates = updateStatus === "checking";
  const isInstallingUpdate =
    updateStatus === "downloading" || updateStatus === "installing";

  useEffect(() => {
    loadInstallPaths();
  }, [loadInstallPaths]);
  useEffect(() => {
    void loadAppVersion();
  }, [loadAppVersion]);

  const chooseFolder = async (format: string) => {
    const selection = await open({ directory: true, multiple: false });
    if (typeof selection !== "string") return;
    await useSettingsStore.getState().setInstallPath(format, selection);
  };

  const handleCheckForUpdates = async () => {
    clearUpdateError();
    await checkForAppUpdate(true);
  };

  const handleInstallUpdate = async () => {
    clearUpdateError();
    await installAppUpdate();
  };

  return (
    <div className="flex flex-col gap-5">
      <div className="flex flex-col gap-2">
        <Label className="text-[10px]">Appearance</Label>
        <Select
          value={appearance}
          onValueChange={(v) => v && setAppearance(v as typeof appearance)}
        >
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

      <div className="flex flex-col gap-2">
        <Label className="text-[10px]">Plugin install paths</Label>
        <p className="text-[10px] text-muted-foreground/60 -mt-0.5">
          Where Foundry installs compiled plugins. DAWs scan these directories.
        </p>

        <div className="flex flex-col gap-2">
          {supportsAu && (
            <div className="flex flex-col gap-1">
              <span className="text-[10px] text-muted-foreground/50">
                AU Components
              </span>
              <div className="flex items-center gap-1.5">
                <Input
                  readOnly
                  value={installPaths?.auPath ?? ""}
                  className="flex-1 cursor-default text-[10px]"
                />
                <Button
                  variant="outline"
                  size="xs"
                  onClick={() => chooseFolder("AU")}
                >
                  <FolderOpen className="size-3" />
                </Button>
                {installPaths && !installPaths.auIsDefault && (
                  <Button
                    variant="ghost"
                    size="xs"
                    onClick={() => resetInstallPath("AU")}
                  >
                    <RotateCcw className="size-3" />
                  </Button>
                )}
              </div>
            </div>
          )}

          {supportsVst3 && (
            <div className="flex flex-col gap-1">
              <span className="text-[10px] text-muted-foreground/50">
                VST3 Plugins
              </span>
              <div className="flex items-center gap-1.5">
                <Input
                  readOnly
                  value={installPaths?.vst3Path ?? ""}
                  className="flex-1 cursor-default text-[10px]"
                />
                <Button
                  variant="outline"
                  size="xs"
                  onClick={() => chooseFolder("VST3")}
                >
                  <FolderOpen className="size-3" />
                </Button>
                {installPaths && !installPaths.vst3IsDefault && (
                  <Button
                    variant="ghost"
                    size="xs"
                    onClick={() => resetInstallPath("VST3")}
                  >
                    <RotateCcw className="size-3" />
                  </Button>
                )}
              </div>
            </div>
          )}
        </div>
      </div>

      <Separator />

      <div className="flex flex-col gap-2">
        <Label className="text-[10px]">About</Label>
        <Card size="sm">
          <CardContent>
            <div className="flex items-center justify-between py-1">
              <span className="text-xs text-muted-foreground">Version</span>
              <span className="text-xs">{appVersion || "—"}</span>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="flex flex-col gap-2">
        <Label className="text-[10px]">App updates</Label>
        <Card size="sm">
          <CardContent className="flex flex-col gap-2">
            <div className="flex items-center justify-between gap-3">
              <div className="min-w-0">
                <div className="text-xs">Desktop updater</div>
                <div className="text-[10px] text-muted-foreground/60">
                  Last checked {formatDateTime(lastUpdateCheck)}
                </div>
              </div>
              <span className="text-[9px] text-muted-foreground/50">
                {getUpdateStatusLabel(updateStatus)}
              </span>
            </div>

            {availableUpdate ? (
              <div className="min-w-0">
                <div className="flex items-center justify-between gap-3">
                  <div className="text-xs">
                    Version {availableUpdate.version}
                  </div>
                  <div className="text-[10px] text-muted-foreground/60 shrink-0">
                    {formatDateTime(availableUpdate.date)}
                  </div>
                </div>
                {availableUpdate.notes && (
                  <p className="mt-1 text-[10px] text-muted-foreground/50 whitespace-pre-wrap break-all overflow-hidden max-h-20 line-clamp-5">
                    {availableUpdate.notes}
                  </p>
                )}
              </div>
            ) : (
              <div className="text-[10px] text-muted-foreground/60">
                {updateStatus === "not-available"
                  ? "Up to date."
                  : "Checks GitHub Releases for signed updates."}
              </div>
            )}

            {downloadProgress && (
              <div className="text-[10px] text-muted-foreground/60">
                Downloaded {formatBytes(downloadProgress.downloaded)}
                {downloadProgress.total
                  ? ` of ${formatBytes(downloadProgress.total)}`
                  : ""}
              </div>
            )}

            {isBuildRunning && availableUpdate && (
              <div className="text-[10px] text-muted-foreground/60">
                Finish the current build before installing.
              </div>
            )}

            {updateError && (
              <div className="text-[10px] text-destructive break-words">
                {updateError}
              </div>
            )}
          </CardContent>
          <CardFooter className="flex flex-wrap justify-end gap-1.5">
            <Button
              variant="outline"
              size="xs"
              onClick={() => void handleCheckForUpdates()}
              disabled={isCheckingForUpdates || isInstallingUpdate}
            >
              <RefreshCw className="size-3" />
              {isCheckingForUpdates ? "Checking..." : "Check for updates"}
            </Button>

            {availableUpdate && (
              <Button
                size="xs"
                onClick={() => void handleInstallUpdate()}
                disabled={isBuildRunning || isInstallingUpdate}
              >
                <Download className="size-3" />
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
  );
}

function ModelsTab() {
  const { modelCatalog, loadCatalog, refreshModels, isRefreshing } =
    useSettingsStore();
  const [installingCli, setInstallingCli] = useState<string | null>(null);
  useEffect(() => {
    loadCatalog();
  }, [loadCatalog]);

  const hasClaudeCode = modelCatalog.some((p) =>
    p.name.toLowerCase().includes("claude"),
  );
  const hasCodex = modelCatalog.some((p) =>
    p.name.toLowerCase().includes("codex"),
  );

  const handleInstallCli = useCallback(
    async (key: string) => {
      const label = key === "claude_code" ? "Claude Code" : "Codex";
      setInstallingCli(key);
      try {
        const result = await installDependency(key);
        const outcome = interpretDependencyInstallResult(result);

        if (outcome.shouldRefreshProviderState) {
          await invalidateAndCheckDependencies();
          await refreshModels();
        }

        if (outcome.state === "verified") {
          toast.success(label + " installed successfully");
        } else if (outcome.state === "auth_required") {
          toast.info(outcome.message, { description: "Opening browser…" });
          if (key === "codex") await launchCodexAuth();
          else await launchClaudeAuth();
        } else if (outcome.state === "failed") {
          // Fix (ghost installations): When the install returns "could not verify",
          // perform a delayed recheck to see if the binary appeared after the
          // verification timeout expired. If it did, update the UI accordingly
          // instead of leaving the user with a misleading failure.
          const isVerificationFailure = outcome.message.includes("could not verify");
          if (isVerificationFailure) {
            toast.error(`Verifying ${label}…`, {
              description: "Installation completed but verification is still in progress. Will recheck shortly.",
            });
            // Recheck after a short delay (the install likely succeeded but the
            // 30s verification window wasn't enough)
            setTimeout(async () => {
              try {
                const recheck = await invalidateAndCheckDependencies();
                await refreshModels();
                const installed = recheck?.find(
                  (d: DependencyStatus) => d.name === (key === "claude_code" ? "Claude Code CLI" : "Codex CLI")
                );
                if (installed?.installed) {
                  toast.success(label + " is now available");
                } else {
                  toast.error(`${label} verification failed`, {
                    description: "Please click Install again or install manually.",
                  });
                }
              } catch {
                toast.error(`${label} recheck failed`);
              }
            }, 5000);
          } else {
            toast.error(`Failed to install ${label}`, {
              description: outcome.message,
            });
          }
        } else {
          toast.success(outcome.message);
        }
      } catch (e) {
        toast.error(`Failed to install ${label}`, { description: String(e) });
      }
      setInstallingCli(null);
    },
    [refreshModels],
  );

  return (
    <div className="flex flex-col gap-4">
      {modelCatalog.length === 0 && !isRefreshing && (
        <p className="text-[10px] text-muted-foreground/50">
          No AI providers detected. Install Claude Code or Codex CLI from the
          Dependencies tab.
        </p>
      )}

      {modelCatalog.map((provider) => (
        <div key={provider.id} className="flex flex-col gap-2">
          <div className="flex items-center gap-1.5">
            <AgentIcon
              agent={provider.name}
              className="size-3 text-muted-foreground/60"
            />
            <Label className="text-[10px]">{provider.name}</Label>
          </div>
          <Card size="sm">
            <CardContent className="flex flex-col">
              {provider.models.map((model, i) => (
                <div key={model.id}>
                  {i > 0 && <Separator />}
                  <div className="flex items-center gap-3 py-2">
                    <div className="flex-1 min-w-0">
                      <div className="text-xs">{model.name}</div>
                      <div className="text-[10px] text-muted-foreground/60">
                        {model.subtitle}
                      </div>
                    </div>
                    {model.default && (
                      <Badge variant="secondary">Default</Badge>
                    )}
                    <span className="text-[10px] text-muted-foreground/40">
                      {model.flag}
                    </span>
                  </div>
                </div>
              ))}
            </CardContent>
          </Card>
        </div>
      ))}

      {!hasClaudeCode && (
        <div className="flex items-center gap-2 px-1 py-2">
          <AgentIcon
            agent="Claude Code"
            className="size-3 text-muted-foreground/40"
          />
          <span className="text-[10px] text-muted-foreground/50 flex-1">
            Claude Code CLI not installed
          </span>
          <Button
            variant="outline"
            size="xs"
            disabled={installingCli !== null}
            onClick={() => handleInstallCli("claude_code")}
          >
            {installingCli === "claude_code" ? (
              <>
                <div className="size-3 border-[1.5px] border-current border-t-transparent rounded-full animate-spin mr-1.5" />
                Installing…
              </>
            ) : (
              "Install"
            )}
          </Button>
        </div>
      )}

      {!hasCodex && (
        <div className="flex items-center gap-2 px-1 py-2">
          <AgentIcon
            agent="Codex"
            className="size-3 text-muted-foreground/40"
          />
          <span className="text-[10px] text-muted-foreground/50 flex-1">
            Codex CLI not installed
          </span>
          <Button
            variant="outline"
            size="xs"
            disabled={installingCli !== null}
            onClick={() => handleInstallCli("codex")}
          >
            {installingCli === "codex" ? (
              <>
                <div className="size-3 border-[1.5px] border-current border-t-transparent rounded-full animate-spin mr-1.5" />
                Installing…
              </>
            ) : (
              "Install"
            )}
          </Button>
        </div>
      )}
      <Button
        variant="outline"
        size="xs"
        onClick={refreshModels}
        disabled={isRefreshing}
        className="self-start"
      >
        {isRefreshing ? "Refreshing..." : "Refresh Models"}
      </Button>
    </div>
  );
}

const DEP_INSTALL_KEY: Record<string, string> = {
  "Xcode Command Line Tools": "xcode_clt",
  CMake: "cmake",
  "Claude Code CLI": "claude_code",
  "Codex CLI": "codex",
};

const AI_PROVIDER_NAMES = new Set(["Claude Code CLI", "Codex CLI"]);

function DependenciesTab() {
  const [deps, setDeps] = useState<DependencyStatus[]>([]);
  const [installing, setInstalling] = useState<string | null>(null);
  const [isResetDialogOpen, setIsResetDialogOpen] = useState(false);
  const [isResetting, setIsResetting] = useState(false);
  const buildEnvironment = useSettingsStore((s) => s.buildEnvironment);
  const loadBuildEnvironment = useSettingsStore((s) => s.loadBuildEnvironment);
  const installManagedJuce = useSettingsStore((s) => s.installManagedJuce);
  const setJuceOverride = useSettingsStore((s) => s.setJuceOverride);
  const clearJuceOverride = useSettingsStore((s) => s.clearJuceOverride);
  const refreshModels = useSettingsStore((s) => s.refreshModels);
  const isPreparingEnvironment = useSettingsStore(
    (s) => s.isPreparingEnvironment,
  );
  const isLoadingBuildEnvironment = useSettingsStore(
    (s) => s.isLoadingBuildEnvironment,
  );

  const refreshDeps = useCallback(async () => {
    try {
      const next = await invalidateAndCheckDependencies();
      setDeps(next);
    } catch {
      setDeps([]);
    }
  }, []);

  useEffect(() => {
    void refreshDeps();
    void loadBuildEnvironment();
  }, [refreshDeps, loadBuildEnvironment]);

  const handleInstall = useCallback(
    async (dep: DependencyStatus) => {
      const key = DEP_INSTALL_KEY[dep.name];
      if (!key) return;
      setInstalling(key);
      try {
        const result = await installDependency(key);
        const outcome = interpretDependencyInstallResult(result);

        if (outcome.state === "verified") {
          toast.success(`${dep.name} installed successfully`);
        } else if (outcome.state === "auth_required") {
          toast.info(outcome.message, { description: "Opening browser…" });
          if (dep.name === "Codex CLI") await launchCodexAuth();
          else if (dep.name === "Claude Code CLI") await launchClaudeAuth();
        } else if (outcome.state === "pending") {
          toast.success(outcome.message);
        } else {
          toast.error(`Failed to install ${dep.name}`, {
            description: outcome.message,
          });
        }
      } catch (e) {
        toast.error(`Failed to install ${dep.name}`, {
          description: String(e),
        });
      }
      await refreshDeps();
      setInstalling(null);
    },
    [refreshDeps],
  );

  const handleAuth = useCallback(async (depName: string) => {
    try {
      if (depName === "Codex CLI") await launchCodexAuth();
      else await launchClaudeAuth();
    } catch {}
  }, []);

  const chooseJuceFolder = useCallback(async () => {
    const selection = await open({ directory: true, multiple: false });
    if (typeof selection !== "string") return;
    await setJuceOverride(selection);
    await refreshDeps();
  }, [refreshDeps, setJuceOverride]);

  const installManagedCopy = useCallback(async () => {
    await installManagedJuce();
    await refreshDeps();
  }, [installManagedJuce, refreshDeps]);

  const restoreManagedCopy = useCallback(async () => {
    await clearJuceOverride();
    await refreshDeps();
  }, [clearJuceOverride, refreshDeps]);

  const recheckEnvironment = useCallback(async () => {
    await Promise.all([refreshDeps(), loadBuildEnvironment()]);
  }, [loadBuildEnvironment, refreshDeps]);

  const handleResetDependencies = useCallback(async () => {
    setIsResetting(true);
    try {
      const result = await resetDebugDependencies();
      await Promise.all([
        refreshDeps(),
        loadBuildEnvironment(),
        refreshModels(),
      ]);

      const failures = result.items.filter((item) => item.status === "failed");
      const skipped = result.items.filter((item) => item.status === "skipped");

      if (failures.length > 0) {
        toast.error(result.summary, {
          description: failures
            .map((item) => `${item.name}: ${item.detail}`)
            .join(" "),
        });
      } else if (skipped.length > 0) {
        toast.success(result.summary, {
          description: skipped
            .map((item) => `${item.name}: ${item.detail}`)
            .join(" "),
        });
      } else {
        toast.success(result.summary);
      }

      setIsResetDialogOpen(false);
    } catch (e) {
      toast.error("Failed to reset dependencies", { description: String(e) });
    } finally {
      setIsResetting(false);
    }
  }, [loadBuildEnvironment, refreshDeps, refreshModels]);

  // Filter out JUCE (handled by Build Environment card) and split into groups
  const filteredDeps = deps.filter((d) => d.name !== "JUCE SDK");
  const buildToolDeps = filteredDeps.filter(
    (d) => !AI_PROVIDER_NAMES.has(d.name),
  );
  const providerDeps = filteredDeps.filter((d) =>
    AI_PROVIDER_NAMES.has(d.name),
  );

  const renderDepRow = (dep: DependencyStatus, i: number) => {
    const key = DEP_INSTALL_KEY[dep.name];
    const isProvider = AI_PROVIDER_NAMES.has(dep.name);
    return (
      <div key={dep.name}>
        {i > 0 && <Separator />}
        <div className="flex items-center gap-2.5 py-2">
          {installing === key ? (
            <Loader2 className="size-3 shrink-0 text-muted-foreground/60 animate-spin" />
          ) : (
            <span
              className={cn(
                "size-1.5 rounded-full shrink-0",
                dep.installed && !dep.authRequired
                  ? "bg-green-400"
                  : dep.authRequired
                    ? "bg-amber-400"
                    : "bg-destructive",
              )}
            />
          )}
          <div className="flex-1 min-w-0">
            <div className="text-xs">{dep.name}</div>
            {dep.detail && (
              <div className="text-[10px] text-muted-foreground/60 truncate">
                {dep.detail}
              </div>
            )}
          </div>
          {dep.installed && !dep.authRequired && (
            <span className="text-[9px] shrink-0 text-success">Installed</span>
          )}
          {dep.installed && dep.authRequired && (
            <Button
              variant="outline"
              size="xs"
              onClick={() => handleAuth(dep.name)}
              disabled={installing !== null}
            >
              Sign in
            </Button>
          )}
          {!dep.installed && key && (
            <Button
              variant="outline"
              size="xs"
              disabled={installing !== null}
              onClick={() => handleInstall(dep)}
            >
              {installing === key && (
                <Loader2 className="size-3 animate-spin" />
              )}
              {installing === key ? "Installing…" : "Install"}
            </Button>
          )}
          {!dep.installed && !key && (
            <span
              className={cn(
                "text-[9px] shrink-0",
                isProvider ? "text-muted-foreground/40" : "text-destructive",
              )}
            >
              {isProvider ? "Optional" : "Missing"}
            </span>
          )}
        </div>
      </div>
    );
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <Label className="text-[10px]">Build Environment</Label>
        <Card size="sm">
          <CardContent className="flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <div>
                <div className="text-xs">JUCE SDK</div>
                <div className="text-[10px] text-muted-foreground/60">
                  {buildEnvironment?.jucePath
                    ? `${buildEnvironment.juceVersion} · ${buildEnvironment.juceSource === "override" ? "custom path" : "managed copy"}`
                    : "Not configured"}
                </div>
              </div>
              <span
                className={cn(
                  "text-[10px]",
                  buildEnvironment?.state === "ready"
                    ? "text-success"
                    : "text-destructive",
                )}
              >
                {isLoadingBuildEnvironment
                  ? "Checking..."
                  : buildEnvironment?.state === "ready"
                    ? "Ready"
                    : "Blocked"}
              </span>
            </div>

            {buildEnvironment?.issues.length ? (
              <div className="flex flex-col gap-1.5">
                {buildEnvironment.issues.map((issue) => (
                  <div
                    key={issue.code}
                    className="bg-muted/40 rounded-md px-2.5 py-2"
                  >
                    <div className="text-xs">{issue.title}</div>
                    <div className="text-[10px] text-muted-foreground/60 mt-0.5">
                      {issue.detail}
                    </div>
                  </div>
                ))}
                <div className="flex flex-wrap gap-1.5">
                  <Button
                    variant="outline"
                    size="xs"
                    onClick={recheckEnvironment}
                    disabled={isPreparingEnvironment}
                  >
                    Re-check
                  </Button>
                  <Button
                    size="xs"
                    onClick={installManagedCopy}
                    disabled={isPreparingEnvironment}
                  >
                    {isPreparingEnvironment
                      ? "Preparing..."
                      : "Install Managed JUCE"}
                  </Button>
                  <Button
                    variant="secondary"
                    size="xs"
                    onClick={chooseJuceFolder}
                    disabled={isPreparingEnvironment}
                  >
                    Choose JUCE Folder
                  </Button>
                </div>
              </div>
            ) : (
              <div className="text-[10px] text-muted-foreground/60">
                {buildEnvironment?.jucePath && (
                  <span className="text-muted-foreground/40 break-all">
                    {buildEnvironment.jucePath}
                  </span>
                )}
              </div>
            )}
            {buildEnvironment?.juceSource === "override" && (
              <Button
                variant="ghost"
                size="xs"
                onClick={restoreManagedCopy}
                disabled={isPreparingEnvironment}
                className="self-start"
              >
                Use Managed Copy
              </Button>
            )}
          </CardContent>
        </Card>
      </div>

      {buildToolDeps.length > 0 && (
        <div className="flex flex-col gap-2">
          <Label className="text-[10px]">Build Tools</Label>
          <Card size="sm">
            <CardContent className="flex flex-col">
              {buildToolDeps.map(renderDepRow)}
            </CardContent>
          </Card>
        </div>
      )}

      {providerDeps.length > 0 && (
        <div className="flex flex-col gap-2">
          <Label className="text-[10px]">AI Providers</Label>
          <Card size="sm">
            <CardContent className="flex flex-col">
              {providerDeps.map(renderDepRow)}
            </CardContent>
          </Card>
        </div>
      )}

      <Button
        variant="outline"
        size="xs"
        onClick={refreshDeps}
        disabled={installing !== null}
        className="self-start"
      >
        <RefreshCw className="size-3" />
        Re-check dependencies
      </Button>

      <div className="flex items-center justify-between gap-3 rounded-lg border border-dashed border-border/60 bg-muted/20 px-3 py-2">
        <div className="min-w-0">
          <div className="text-[9px] uppercase tracking-[0.18em] text-muted-foreground/35">
            Debug
          </div>
          <p className="text-[10px] text-muted-foreground/55">
            Reset removable dependency installs to replay onboarding and setup
            flows.
          </p>
        </div>
        <Button
          variant="ghost"
          size="xs"
          disabled={
            installing !== null || isPreparingEnvironment || isResetting
          }
          onClick={() => setIsResetDialogOpen(true)}
          className="shrink-0 text-muted-foreground/55 hover:text-destructive"
        >
          <Trash2 className="size-3" />
          Reset installs
        </Button>
      </div>

      <Dialog open={isResetDialogOpen} onOpenChange={setIsResetDialogOpen}>
        <DialogContent showCloseButton={false}>
          <DialogHeader>
            <DialogTitle>Reset dependency installs?</DialogTitle>
            <DialogDescription>
              This removes Foundry-managed installs it can safely reset: Claude
              Code CLI, Codex CLI, managed JUCE, and Homebrew CMake when
              applicable. System toolchains like Xcode Command Line Tools stay
              in place.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              size="xs"
              disabled={isResetting}
              onClick={() => setIsResetDialogOpen(false)}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              size="xs"
              disabled={isResetting}
              onClick={() => void handleResetDependencies()}
            >
              {isResetting ? (
                <>
                  <Loader2 className="size-3 animate-spin" />
                  Resetting…
                </>
              ) : (
                <>
                  <Trash2 className="size-3" />
                  Reset installs
                </>
              )}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function AccountTab() {
  const signOut = useAppStore((s) => s.signOut);
  const userProfile = useAppStore((s) => s.userProfile);

  return (
    <div className="flex flex-col gap-3">
      {userProfile && (
        <p className="text-xs text-muted-foreground">
          Signed in as{" "}
          {userProfile.email || userProfile.displayName || userProfile.id}
        </p>
      )}
      <Button
        variant="outline"
        size="xs"
        onClick={signOut}
        className="self-start text-destructive"
      >
        Sign Out
      </Button>
    </div>
  );
}
