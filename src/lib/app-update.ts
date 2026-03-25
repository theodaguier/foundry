import { relaunch } from "@tauri-apps/plugin-process"
import {
  check,
  type DownloadEvent,
  type Update,
} from "@tauri-apps/plugin-updater"

import type { AppUpdateInfo } from "@/lib/types"

let preparedUpdate: Update | null = null

async function setPreparedUpdate(next: Update | null) {
  if (preparedUpdate && preparedUpdate !== next) {
    try {
      await preparedUpdate.close()
    } catch (error) {
      console.warn("Failed to close prepared update resource:", error)
    }
  }

  preparedUpdate = next
}

function toUpdateInfo(update: Update): AppUpdateInfo {
  return {
    version: update.version,
    date: update.date,
    notes: update.body,
  }
}

export async function clearPreparedUpdate() {
  await setPreparedUpdate(null)
}

export async function checkForPreparedUpdate(): Promise<AppUpdateInfo | null> {
  const update = await check()
  await setPreparedUpdate(update)
  return update ? toUpdateInfo(update) : null
}

export async function installPreparedUpdate(
  onEvent?: (event: DownloadEvent) => void,
) {
  if (!preparedUpdate) {
    throw new Error("No update is ready to install.")
  }

  await preparedUpdate.downloadAndInstall(onEvent)

  try {
    await relaunch()
  } finally {
    await clearPreparedUpdate()
  }
}
