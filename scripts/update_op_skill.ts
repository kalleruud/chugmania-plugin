#!/usr/bin/env bun

import { mkdir, writeFile } from 'node:fs/promises'
import path from 'node:path'

const references = [
  [
    'plugin-dependencies.html',
    'https://openplanet.dev/docs/tutorials/plugin-dependencies',
  ],
  ['info-toml.html', 'https://openplanet.dev/docs/reference/info-toml'],
  ['callbacks.html', 'https://openplanet.dev/docs/reference/plugin-callbacks'],
  ['icons.html', 'https://openplanet.dev/docs/reference/icons'],
  ['settings.html', 'https://openplanet.dev/docs/reference/settings'],
  ['imports.html', 'https://openplanet.dev/docs/reference/imports'],
  ['preprocessor.html', 'https://openplanet.dev/docs/reference/preprocessor'],
  ['authentication.html', 'https://openplanet.dev/docs/reference/auth'],
  ['nadeoservices.html', 'https://openplanet.dev/docs/reference/nadeoservices'],
  ['vehiclestate.html', 'https://openplanet.dev/docs/reference/vehiclestate'],
  ['camera.html', 'https://openplanet.dev/docs/reference/camera'],
  ['controls.html', 'https://openplanet.dev/docs/reference/controls'],
] as const

const repoRoot = path.resolve(import.meta.dir, '..')
const referencesDir = path.join(
  repoRoot,
  '.agents',
  'skills',
  'openplanet',
  'references'
)

async function fetchPage(url: string) {
  const response = await fetch(url, {
    headers: {
      'user-agent': 'chugmania-plugin openplanet skill sync',
    },
  })
  if (!response.ok) {
    throw new Error(
      `Failed to download ${url}: ${response.status} ${response.statusText}`
    )
  }

  const html = await response.text()
  if (!html.includes('<html')) {
    throw new Error(`Downloaded content from ${url} does not look like HTML`)
  }

  return html
}

await mkdir(referencesDir, { recursive: true })

for (const [fileName, url] of references) {
  const html = await fetchPage(url)
  const outputPath = path.join(referencesDir, fileName)
  await writeFile(outputPath, html, 'utf8')
  console.log(`Updated ${path.relative(repoRoot, outputPath)} <- ${url}`)
}
