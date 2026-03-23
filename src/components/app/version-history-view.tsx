import { useState } from "react"
import type { Plugin, PluginVersion } from "@/lib/types"
import { installVersion, clearBuildCache } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu"

interface Props {
  plugin: Plugin
  onBack: () => void
  onVersionRestored?: (plugin: Plugin) => void
}

export function VersionHistoryContent({ plugin, onBack, onVersionRestored }: Props) {
  const [restoring, setRestoring] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [clearCacheConfirm, setClearCacheConfirm] = useState<PluginVersion | null>(null)

  const sortedVersions = [...plugin.versions].sort(
    (a, b) => b.versionNumber - a.versionNumber
  )

  const handleRestore = async (version: PluginVersion) => {
    setRestoring(true)
    setError(null)
    try {
      const updated = await installVersion(plugin.id, version.versionNumber)
      onVersionRestored?.(updated)
      onBack()
    } catch (e) {
      setError(String(e))
    } finally {
      setRestoring(false)
    }
  }

  const handleClearCache = async (version: PluginVersion) => {
    try {
      const updated = await clearBuildCache(plugin.id, version.versionNumber)
      onVersionRestored?.(updated)
      setClearCacheConfirm(null)
    } catch (e) {
      setError(String(e))
      setClearCacheConfirm(null)
    }
  }

  const formatDate = (dateStr: string) => {
    return new Date(dateStr).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    })
  }

  const versionType = (version: PluginVersion): "CREATED" | "REFINED" => {
    return version.versionNumber === 1 ? "CREATED" : "REFINED"
  }

  if (clearCacheConfirm) {
    return (
      <div className="flex flex-col">
        <div className="px-6 pt-5 pb-4">
          <span className="text-[9px] font-mono tracking-[1.2px] text-muted-foreground/60 uppercase block mb-1">
            Clear Build Cache
          </span>
          <p className="text-[13px] text-muted-foreground leading-relaxed">
            This will delete the build directory for v{clearCacheConfirm.versionNumber}.
            You will not be able to restore this version without rebuilding.
          </p>
        </div>
        <Separator />
        <div className="flex items-center justify-end gap-2 px-6 py-4">
          <Button variant="outline" onClick={() => setClearCacheConfirm(null)}>
            Cancel
          </Button>
          <Button
            variant="destructive"
            onClick={() => handleClearCache(clearCacheConfirm)}
          >
            Clear Cache
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="flex flex-col max-h-[80vh]">
      {/* Header */}
      <div className="px-6 pt-5 pb-4">
        <button
          onClick={onBack}
          className="flex items-center gap-1.5 text-muted-foreground/60 hover:text-muted-foreground mb-3 transition-colors"
        >
          <svg className="w-3 h-3" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="8 3 4 6 8 9" />
          </svg>
          <span className="text-[9px] font-mono tracking-[1.2px] uppercase">Back</span>
        </button>
        <span className="text-[9px] font-mono tracking-[1.2px] text-muted-foreground/60 uppercase block mb-1">
          Version History
        </span>
        <div className="flex items-baseline gap-3">
          <h1 className="text-[20px] font-[ArchitypeStedelijk] tracking-[1px] text-foreground uppercase truncate leading-tight">
            {plugin.name}
          </h1>
          <span className="text-[11px] font-mono text-muted-foreground/60 shrink-0">
            {sortedVersions.length} version{sortedVersions.length === 1 ? "" : "s"}
          </span>
        </div>
      </div>
      <Separator />

      {/* Error banner */}
      {error && (
        <>
          <div className="px-6 py-3 bg-destructive/10">
            <span className="text-[11px] font-mono text-destructive">{error}</span>
          </div>
          <Separator />
        </>
      )}

      {/* Version list */}
      <div className="flex-1 overflow-y-auto">
        {sortedVersions.map((version, index) => (
          <div key={version.id}>
            <div className="flex items-start gap-4 px-6 py-4">
              {/* Version badge */}
              <div className="flex flex-col items-center gap-1.5 shrink-0 pt-0.5">
                <span className="inline-flex items-center justify-center w-8 h-5 rounded bg-muted text-[10px] font-mono font-medium text-foreground">
                  v{version.versionNumber}
                </span>
                <span
                  className={`text-[8px] font-mono tracking-[0.8px] uppercase ${
                    versionType(version) === "CREATED"
                      ? "text-muted-foreground/60"
                      : "text-primary"
                  }`}
                >
                  {versionType(version)}
                </span>
              </div>

              {/* Content */}
              <div className="flex-1 min-w-0">
                <p className="text-[11px] font-mono text-muted-foreground leading-relaxed line-clamp-2">
                  {version.prompt}
                </p>
                <div className="flex items-center gap-2 mt-2 flex-wrap">
                  <span className="text-[9px] font-mono text-muted-foreground/50">
                    {formatDate(version.createdAt)}
                  </span>
                  {version.agent && (
                    <>
                      <span className="text-muted-foreground/25">·</span>
                      <span className="text-[9px] font-mono text-muted-foreground/50">
                        {version.agent}
                      </span>
                    </>
                  )}
                  {version.model && (
                    <>
                      <span className="text-muted-foreground/25">·</span>
                      <span className="text-[9px] font-mono text-muted-foreground/50">
                        {version.model.name}
                      </span>
                    </>
                  )}
                  <span className="text-muted-foreground/25">·</span>
                  <span className={`text-[9px] font-mono ${version.buildDirectory ? "text-green-500" : "text-muted-foreground/30"}`}>
                    {version.buildDirectory ? "CACHED" : "NO CACHE"}
                  </span>
                </div>
              </div>

              {/* Actions */}
              <div className="shrink-0 pt-0.5">
                {version.isActive ? (
                  <Badge variant="secondary" className="text-[9px] tracking-[0.8px] uppercase gap-1">
                    <svg
                      className="w-3 h-3"
                      viewBox="0 0 12 12"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      <polyline points="2 6 5 9 10 3" />
                    </svg>
                    Active
                  </Badge>
                ) : (
                  <DropdownMenu>
                    <DropdownMenuTrigger
                      render={
                        <button className="flex items-center justify-center w-7 h-7 text-muted-foreground/50 hover:text-muted-foreground hover:bg-muted rounded transition-colors">
                          <span className="text-[14px] font-bold leading-none">···</span>
                        </button>
                      }
                    />
                    <DropdownMenuContent align="end">
                      <DropdownMenuItem
                        onClick={() => handleRestore(version)}
                        disabled={!version.buildDirectory || restoring}
                      >
                        Restore this version
                      </DropdownMenuItem>
                      <DropdownMenuSeparator />
                      <DropdownMenuItem
                        onClick={() => setClearCacheConfirm(version)}
                        disabled={!version.buildDirectory}
                      >
                        Clear build cache
                      </DropdownMenuItem>
                    </DropdownMenuContent>
                  </DropdownMenu>
                )}
              </div>
            </div>
            {index < sortedVersions.length - 1 && <Separator />}
          </div>
        ))}
      </div>

      {/* Footer */}
      <Separator />
      <div className="flex items-center justify-end px-6 py-4">
        <Button size="lg" onClick={onBack}>
          Done
        </Button>
      </div>
    </div>
  )
}
