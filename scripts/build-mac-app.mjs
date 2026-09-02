// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import { spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const macPackage = new URL("../apps/macos/", import.meta.url);
const developerDir = "/Applications/Xcode.app/Contents/Developer";
const environment = { ...process.env, DEVELOPER_DIR: developerDir };
const build = spawnSync("xcrun", ["swift", "build", "--configuration", "debug"], {
  cwd: macPackage,
  stdio: "inherit",
  env: environment,
});
if (build.error) throw build.error;
if (build.status !== 0) process.exit(build.status ?? 1);

const binPath = spawnSync(
  "xcrun",
  ["swift", "build", "--configuration", "debug", "--show-bin-path"],
  { cwd: macPackage, encoding: "utf8", env: environment },
);
if (binPath.error) throw binPath.error;
if (binPath.status !== 0) process.exit(binPath.status ?? 1);

const bundle = new URL("../build/Conatus.app/", import.meta.url);
const contents = new URL("Contents/", bundle);
const macos = new URL("MacOS/", contents);
mkdirSync(macos, { recursive: true });
const bundledBinary = new URL("ConatusMac", macos);
copyFileSync(`${binPath.stdout.trim()}/ConatusMac`, bundledBinary);
chmodSync(bundledBinary, 0o755);

writeFileSync(new URL("Info.plist", contents), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>ConatusMac</string>
  <key>CFBundleIdentifier</key><string>com.conatus.mac.dev</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Conatus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Conatus listens locally for “Hey Conatus” and captures only the activated command.</string>
</dict></plist>
`);

console.log(fileURLToPath(bundle));
