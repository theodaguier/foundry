import { readFile, writeFile } from "node:fs/promises"
import path from "node:path"

function requireEnv(name) {
  const value = process.env[name]
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`)
  }
  return value
}

async function readSignature(assetsDir, filename) {
  const signaturePath = path.join(assetsDir, filename)
  return (await readFile(signaturePath, "utf8")).trim()
}

async function main() {
  const releaseTag = requireEnv("RELEASE_TAG")
  const publishedAt = requireEnv("RELEASE_PUBLISHED_AT")
  const repository = process.env.GITHUB_REPOSITORY ?? "theodaguier/foundry"
  const [owner, repo] = repository.split("/")

  if (!owner || !repo) {
    throw new Error(`Invalid GITHUB_REPOSITORY value: ${repository}`)
  }

  const version = releaseTag.replace(/^v/, "")
  const assetsDir = path.resolve(process.cwd(), process.env.ASSETS_DIR ?? "release-assets")
  const outputPath = path.resolve(process.cwd(), process.env.OUTPUT_PATH ?? path.join(assetsDir, "latest.json"))
  const notesFile = process.env.RELEASE_NOTES_FILE
  const notes = notesFile ? await readFile(notesFile, "utf8") : ""
  const releaseBaseUrl = `https://github.com/${owner}/${repo}/releases/download/${releaseTag}`
  const assetBase = `Foundry_${version}`

  const manifest = {
    version,
    notes,
    pub_date: publishedAt,
    platforms: {
      "darwin-aarch64": {
        signature: await readSignature(assetsDir, `${assetBase}_darwin_aarch64.app.tar.gz.sig`),
        url: `${releaseBaseUrl}/${assetBase}_darwin_aarch64.app.tar.gz`,
      },
      "darwin-x86_64": {
        signature: await readSignature(assetsDir, `${assetBase}_darwin_x86_64.app.tar.gz.sig`),
        url: `${releaseBaseUrl}/${assetBase}_darwin_x86_64.app.tar.gz`,
      },
      "windows-x86_64": {
        signature: await readSignature(assetsDir, `${assetBase}_windows_x86_64-setup.exe.sig`),
        url: `${releaseBaseUrl}/${assetBase}_windows_x86_64-setup.exe`,
      },
    },
  }

  await writeFile(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
