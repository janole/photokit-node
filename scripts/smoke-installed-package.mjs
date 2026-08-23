import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryDirectory = dirname(dirname(fileURLToPath(import.meta.url)));
const packageDirectory = join(repositoryDirectory, "packages", "cli");
const temporaryDirectory = mkdtempSync(join(tmpdir(), "photokit package smoke ; "));
const installationDirectory = join(temporaryDirectory, "installation");

try
{
    const packOutput = execFileSync("npm", [
        "pack",
        packageDirectory,
        "--ignore-scripts",
        "--json",
        "--pack-destination",
        temporaryDirectory,
    ], { encoding: "utf8" });
    const [packResult] = JSON.parse(packOutput);
    const tarballPath = join(temporaryDirectory, packResult.filename);

    mkdirSync(installationDirectory);
    execFileSync("npm", [
        "install",
        "--ignore-scripts",
        "--no-audit",
        "--no-fund",
        "--no-package-lock",
        "--prefix",
        installationDirectory,
        tarballPath,
    ], { stdio: "pipe" });

    const importResult = spawnSync(process.execPath, [
        "--input-type=module",
        "--eval",
        "import { PhotoKitClient } from 'photokit-node'; if (typeof PhotoKitClient !== 'function') process.exit(1);",
    ], {
        cwd: installationDirectory,
        encoding: "utf8",
    });

    if (importResult.status !== 0)
    {
        throw new Error(`Installed package did not export PhotoKitClient: ${importResult.stderr}`);
    }

    const executable = join(installationDirectory, "node_modules", ".bin", "photokit-node");
    const environment = { ...process.env };
    delete environment.PHOTOKIT_NODE_HELPER_PATH;
    const result = spawnSync(executable, ["authorization", "status", "--json"], {
        cwd: temporaryDirectory,
        encoding: "utf8",
        env: environment,
    });

    if (result.status !== 0 && result.status !== 77)
    {
        throw new Error(`Installed CLI failed with exit ${result.status}: ${result.stderr}`);
    }

    const authorization = JSON.parse(result.stdout);
    if (typeof authorization.status !== "string" || typeof authorization.guidance !== "string")
    {
        throw new Error("Installed CLI did not return an authorization payload.");
    }

    process.stdout.write(`Installed package discovered its helper; authorization status: ${authorization.status}.\n`);
}
finally
{
    rmSync(temporaryDirectory, { force: true, recursive: true });
}
