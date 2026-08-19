import { chmodSync, copyFileSync, existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { HelperNotExecutableError, HelperNotFoundError, resolveHelperPath, runHelper } from "../src/helper-runner";
import { IncompatibleProtocolVersionError, InvalidProtocolResponseError } from "../src/protocol";

const fixtureSource = fileURLToPath(new URL("./fixtures/helper-fixture.mjs", import.meta.url));

let fixtureDirectory: string;
let helperPath: string;

beforeEach(() =>
{
    fixtureDirectory = mkdtempSync(join(tmpdir(), "photokit helper ; "));
    helperPath = join(fixtureDirectory, "fixture helper ; safe.mjs");
    copyFileSync(fixtureSource, helperPath);
    chmodSync(helperPath, 0o755);
});

afterEach(() =>
{
    rmSync(fixtureDirectory, { force: true, recursive: true });
});

describe("helper runner", () =>
{
    it("locates the packaged helper next to the core package", () =>
    {
        expect(resolveHelperPath()).toMatch(/packages\/core\/native\/photokit-helper$/);
    });

    it("runs paths with spaces and preserves shell metacharacters as data", async () =>
    {
        const markerPath = join(fixtureDirectory, "must-not-exist");
        const value = `$(touch '${markerPath}'); * & echo unsafe`;
        const result = await runHelper("version", {
            fixtureMode: "success",
            value,
        }, { helperPath });

        expect(result).toMatchObject({
            exitCode: 0,
            response: {
                data: {
                    receivedParameters: {
                        value,
                    },
                },
                success: true,
            },
        });
        expect(existsSync(markerPath)).toBe(false);
    });

    it("returns structured protocol failures from nonzero exits", async () =>
    {
        const result = await runHelper("list-assets", {
            fixtureMode: "protocol-failure",
        }, { helperPath });

        expect(result).toMatchObject({
            exitCode: 77,
            response: {
                error: { code: "photo-library-access-unavailable" },
                success: false,
            },
        });
    });

    it("distinguishes a missing helper", async () =>
    {
        await expect(runHelper("version", {}, {
            helperPath: join(fixtureDirectory, "missing helper"),
        })).rejects.toBeInstanceOf(HelperNotFoundError);
    });

    it("distinguishes a non-executable helper", async () =>
    {
        chmodSync(helperPath, 0o644);

        await expect(runHelper("version", {}, { helperPath })).rejects.toBeInstanceOf(HelperNotExecutableError);
    });

    it("terminates helpers that exceed the timeout", async () =>
    {
        await expect(runHelper("version", {
            delayMs: 5_000,
            fixtureMode: "delay",
        }, {
            helperPath,
            timeoutMs: 25,
        })).rejects.toMatchObject({
            code: "helper-timeout",
            timeoutMs: 25,
        });
    });

    it.each(["stdout", "stderr"] as const)("terminates helpers that exceed the %s cap", async (stream) =>
    {
        await expect(runHelper("version", {
            bytes: 4_096,
            fixtureMode: `${stream}-overflow`,
        }, {
            helperPath,
            maxOutputBytes: 128,
        })).rejects.toMatchObject({
            code: "helper-output-limit",
            maxOutputBytes: 128,
            stream,
        });
    });

    it("distinguishes a crashing helper", async () =>
    {
        await expect(runHelper("version", {
            fixtureMode: "crash",
        }, { helperPath })).rejects.toMatchObject({
            code: "helper-crashed",
            exitCode: 42,
            stderr: "fixture crash\n",
        });
    });

    it("preserves incompatible-version failures", async () =>
    {
        await expect(runHelper("version", {
            fixtureMode: "future-version",
        }, { helperPath })).rejects.toBeInstanceOf(IncompatibleProtocolVersionError);
    });

    it("preserves malformed-response failures", async () =>
    {
        await expect(runHelper("version", {
            fixtureMode: "malformed",
        }, { helperPath })).rejects.toBeInstanceOf(InvalidProtocolResponseError);
    });
});
