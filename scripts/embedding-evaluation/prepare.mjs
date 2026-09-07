import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Reuse an existing dependency checkout; this script never invokes Git or downloads packages.
if (process.argv.length !== 3) {
  throw new Error("Usage: node scripts/embedding-evaluation/prepare.mjs /path/to/existing/GRDB.swift");
}
const scriptRoot = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptRoot, "../..");
const grdbRoot = realpathSync(process.argv[2]);
if (!existsSync(join(grdbRoot, "Package.swift"))) throw new Error("GRDB checkout must contain Package.swift");
const appProject = readFileSync(join(repoRoot, "Remember/Remember.xcodeproj/project.pbxproj"), "utf8");
const team = appProject.match(/DEVELOPMENT_TEAM = ([A-Z0-9]+);/)?.[1];
if (!team) throw new Error("No development team found in the app project");
function plistPath(value) {
  if (/[\r\n]/.test(value)) throw new Error("Project paths must not contain line breaks");
  return JSON.stringify(value).slice(1, -1);
}
const projectText = readFileSync(join(scriptRoot, "project.pbxproj.template"), "utf8")
  .replaceAll("__REPO_ROOT__", plistPath(repoRoot))
  .replaceAll("__GRDB_ROOT__", plistPath(grdbRoot))
  .replaceAll("__DEVELOPMENT_TEAM__", team);
const output = mkdtempSync(join(tmpdir(), "RememberEmbeddingProbe-"));
mkdirSync(join(output, "Sources"));
mkdirSync(join(output, "EmbeddingProbe.xcodeproj"));
copyFileSync(join(scriptRoot, "EmbeddingProbe.swift"), join(output, "Sources/EmbeddingProbe.swift"));
writeFileSync(join(output, "EmbeddingProbe.xcodeproj/project.pbxproj"), projectText);
console.log(JSON.stringify({
  project: join(output, "EmbeddingProbe.xcodeproj"),
  derivedData: join(output, "build"),
  bundleIdentifier: "SimpleStudio.Remember.EmbeddingProbe",
  app: join(output, "build/Build/Products/Debug-iphoneos/EmbeddingProbe.app")
}, null, 2));
