import { cpSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryDirectory = dirname(dirname(fileURLToPath(import.meta.url)));
const sourceDirectory = join(repositoryDirectory, "skills", "photokit-node");
const packagedDirectory = join(repositoryDirectory, "packages", "cli", "skills", "photokit-node");

rmSync(packagedDirectory, { force: true, recursive: true });
mkdirSync(dirname(packagedDirectory), { recursive: true });
cpSync(sourceDirectory, packagedDirectory, { recursive: true });

process.stdout.write(`Staged ${packagedDirectory}.\n`);
