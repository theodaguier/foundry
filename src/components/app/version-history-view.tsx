import { useState } from "react"
import type { Plugin, PluginVersion } from "@/lib/types"
import { installVersion, clearBuildCache } from "@/lib/commands"
import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"


import { Separator } from "@/components/ui/separator"
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
} from "@/components/ui/dropdown-menu"
import { MoreHorizontal, Check } from "lucide-react"

interface Props {
  plugin: Plugin
  onVersionRestored?: (plugin: Plugin) => void
}

export function VersionHistoryView({ plugin, onVersionRestored }: Props) {
  const [restoring, setRestoring] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const sortedVersions = [...plugin.versions].sort(
    (a, b) => b.versionNumber - a.versionNumber
  )

  const handleRestore = async (version: PluginVersion) => {
    setRestoring(true)
    setError(null)
    try {
      const updated = await installVersion(plugin.id, version.versionNumber)
      onVersionRestored?.(updated)
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
    } catch (e) {
      setError(String(e))
    }
  }

  if (sortedVersions.length === 0) return null

  return (
    <div className="flex flex-col gap-3">
      <div className="text-[10px] font-medium tracking-[1.5px] uppercase text-muted-foreground/50">Versions</div>
      {error && (
        <span className="text-xs font-mono text-destructive">{error}</span>
      )}
      <Card size="sm">
        <CardContent className="flex flex-col">
          {sortedVersions.map((version, i) => (
            <div key={version.id}>
              {i > 0 && <Separator />}
              <div className="flex items-center gap-3 py-2">
                <span className="text-xs font-mono text-muted-foreground shrink-0 w-6 text-right">
                  v{version.versionNumber}
                </span>
                <span className="flex-1 min-w-0 text-xs text-muted-foreground truncate">
                  {version.prompt}
                </span>
                <div className="shrink-0">
                  {version.isActive ? (
                    <Check className="size-3.5 text-foreground/40" />
                  ) : (
                    <DropdownMenu>
                      <DropdownMenuTrigger
                        render={
                          <Button variant="ghost" size="icon" className="size-6">
                            <MoreHorizontal className="size-3.5" />
                          </Button>
                        }
                      />
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem
                          onClick={() => handleRestore(version)}
                          disabled={!version.buildDirectory || restoring}
                        >
                          Restore
                        </DropdownMenuItem>
                        <DropdownMenuSeparator />
                        <DropdownMenuItem
                          onClick={() => handleClearCache(version)}
                          disabled={!version.buildDirectory}
                        >
                          Clear cache
                        </DropdownMenuItem>
                      </DropdownMenuContent>
                    </DropdownMenu>
                  )}
                </div>
              </div>
            </div>
          ))}
        </CardContent>
      </Card>
    </div>
  )
}
