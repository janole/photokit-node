import { execFileSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryDirectory = dirname(dirname(fileURLToPath(import.meta.url)));
const packageDirectory = join(repositoryDirectory, "packages", "cli");
const nativeDirectory = join(packageDirectory, "native");
const appPath = join(nativeDirectory, "PhotoKit Node Helper.app");
const binaryPath = join(appPath, "Contents", "MacOS", "photokit-helper");
const launcherPath = join(nativeDirectory, "photokit-helper");
const packageJson = JSON.parse(readFileSync(join(packageDirectory, "package.json"), "utf8"));
const publicDeclarations = readFileSync(join(packageDirectory, "dist", "index.d.ts"), "utf8");

function requireCondition(condition, message)
{
    if (!condition)
    {
        throw new Error(message);
    }
}

requireCondition(process.platform === "darwin", "Package verification requires macOS.");
requireCondition(process.arch === "arm64", `Package verification requires arm64, received ${process.arch}.`);
requireCondition(packageJson.os?.length === 1 && packageJson.os[0] === "darwin", "Package metadata must declare darwin only.");
requireCondition(packageJson.cpu?.length === 1 && packageJson.cpu[0] === "arm64", "Package metadata must declare arm64 only.");
requireCondition((statSync(launcherPath).mode & 0o111) !== 0, "Packaged helper launcher must be executable.");
requireCondition(publicDeclarations.includes("declare class PhotoKitClient"), "Public declarations must export PhotoKitClient.");
requireCondition(!publicDeclarations.includes("@photokit-node/core"), "Public declarations must not depend on the private core package.");

const architectures = execFileSync("lipo", ["-archs", binaryPath], { encoding: "utf8" }).trim();
requireCondition(architectures === "arm64", `Packaged helper must contain only arm64, received ${architectures}.`);
execFileSync("codesign", ["--verify", "--strict", appPath]);

const bundleVersion = execFileSync("plutil", [
    "-extract",
    "CFBundleShortVersionString",
    "raw",
    join(appPath, "Contents", "Info.plist"),
], { encoding: "utf8" }).trim();
requireCondition(bundleVersion === packageJson.version, "Native bundle and npm package versions must match.");

const packOutput = execFileSync("npm", ["pack", "--dry-run", "--ignore-scripts", "--json"], {
    cwd: packageDirectory,
    encoding: "utf8",
});
const [packResult] = JSON.parse(packOutput);
const files = new Map(packResult.files.map((file) => [file.path, file]));
const requiredFiles = [
    "LICENSE",
    "README.md",
    "dist/bin.js",
    "dist/index.d.ts",
    "dist/index.js",
    "native/PhotoKit Node Helper.app/Contents/Info.plist",
    "native/PhotoKit Node Helper.app/Contents/MacOS/photokit-helper",
    "native/photokit-helper",
    "package.json",
];

for (const path of requiredFiles)
{
    requireCondition(files.has(path), `npm pack is missing ${path}.`);
}

requireCondition([...files.keys()].some((path) => /^dist\/chunk-.+\.js$/.test(path)), "npm pack is missing the bundled CLI chunk.");
requireCondition(![...files.keys()].some((path) => path.includes(".build/")), "npm pack must not contain Swift build intermediates.");

process.stdout.write(`Verified ${packResult.filename}: ${files.size} files, ${packResult.size} bytes, darwin-arm64.\n`);
