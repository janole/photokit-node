import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { IncompatibleProtocolVersionError, InvalidProtocolResponseError, PhotoKitClient, PhotoKitError } from "../src/index";

const fixtureSource = fileURLToPath(new URL("./fixtures/client-helper-fixture.mjs", import.meta.url));

interface FixtureOutput
{
    operation: string;
    outputPath: string;
}

let fixtureDirectory: string;
let handshakePath: string;
let helperPath: string;
let modePath: string;
let outputsPath: string;

function client(options: ConstructorParameters<typeof PhotoKitClient>[0] = {}): PhotoKitClient
{
    return new PhotoKitClient({ helperPath, ...options });
}

function fixtureOutputs(): FixtureOutput[]
{
    if (!existsSync(outputsPath))
    {
        return [];
    }

    return readFileSync(outputsPath, "utf8")
        .trim()
        .split("\n")
        .filter(Boolean)
        .map((line) => JSON.parse(line) as FixtureOutput);
}

function setFixtureMode(mode: string): void
{
    writeFileSync(modePath, mode);
}

beforeEach(() =>
{
    fixtureDirectory = mkdtempSync(join(tmpdir(), "photokit client ; "));
    helperPath = join(fixtureDirectory, "client helper ; safe.mjs");
    handshakePath = join(fixtureDirectory, "client-helper.handshakes");
    modePath = join(fixtureDirectory, "client-helper.mode");
    outputsPath = join(fixtureDirectory, "client-helper.outputs");
    copyFileSync(fixtureSource, helperPath);
    chmodSync(helperPath, 0o755);
});

afterEach(() =>
{
    rmSync(fixtureDirectory, { force: true, recursive: true });
});

describe("PhotoKitClient", () =>
{
    it("handshakes once before returning authorization and asset data", async () =>
    {
        const photos = client();
        const authorization = await photos.authorizationStatus();
        const assets = await photos.listAssets({ limit: 1, mediaType: "video" });

        expect(authorization).toEqual({
            canRequest: false,
            guidance: "Photo access is available.",
            status: "authorized",
        });
        expect(assets).toEqual([expect.objectContaining({
            duration: 12.5,
            localIdentifier: "video-local-id",
            mediaType: "video",
        })]);
        expect(readFileSync(handshakePath, "utf8")).toBe("1");
    });

    it("requests authorization through the typed operation", async () =>
    {
        await expect(client().requestAuthorization()).resolves.toMatchObject({
            canRequest: false,
            status: "authorized",
        });
    });

    it("returns bounded thumbnail bytes and removes Node-owned files", async () =>
    {
        const result = await client().getThumbnail("image-local-id", {
            format: "png",
            maxHeight: 128,
            maxWidth: 256,
        });

        expect(result).toMatchObject({
            assetIdentifier: "image-local-id",
            contentType: "image/png",
            pixelHeight: 1,
            pixelWidth: 2,
            representation: "thumbnail",
            uniformTypeIdentifier: "public.png",
        });
        expect(Buffer.from(result.bytes).toString("utf8")).toBe("thumbnail:image-local-id");

        const [output] = fixtureOutputs();
        expect(output?.operation).toBe("get-thumbnail");
        expect(existsSync(dirname(output?.outputPath ?? ""))).toBe(false);
    });

    it("isolates concurrent thumbnail operations and shares their handshake", async () =>
    {
        const photos = client();
        const [first, second] = await Promise.all([
            photos.getThumbnail("first", { maxHeight: 64, maxWidth: 64 }),
            photos.getThumbnail("second", { maxHeight: 64, maxWidth: 64 }),
        ]);

        expect(Buffer.from(first.bytes).toString("utf8")).toBe("thumbnail:first");
        expect(Buffer.from(second.bytes).toString("utf8")).toBe("thumbnail:second");

        const outputs = fixtureOutputs();
        expect(outputs).toHaveLength(2);
        expect(new Set(outputs.map((output) => dirname(output.outputPath))).size).toBe(2);
        expect(outputs.every((output) => !existsSync(dirname(output.outputPath)))).toBe(true);
        expect(readFileSync(handshakePath, "utf8")).toBe("1");
    });

    it("surfaces native failures with stable codes and still cleans thumbnails", async () =>
    {
        await expect(client().getThumbnail("network-required", {
            maxHeight: 64,
            maxWidth: 64,
        })).rejects.toMatchObject({
            code: "network-access-required",
            operation: "get-thumbnail",
        });

        const [output] = fixtureOutputs();
        expect(existsSync(dirname(output?.outputPath ?? ""))).toBe(false);
    });

    it.each(["outside-path", "byte-mismatch", "missing-output", "oversized", "wrong-asset", "wrong-representation"])(
        "rejects invalid thumbnail output for %s and cleans it",
        async (identifier) =>
        {
            await expect(client().getThumbnail(identifier, {
                maxHeight: 64,
                maxWidth: 64,
            })).rejects.toBeInstanceOf(InvalidProtocolResponseError);

            const [output] = fixtureOutputs();
            expect(existsSync(dirname(output?.outputPath ?? ""))).toBe(false);
        },
    );

    it("applies content deadlines and cleans timed-out thumbnail directories", async () =>
    {
        await expect(client({ contentTimeoutMs: 250 }).getThumbnail("delay", {
            maxHeight: 64,
            maxWidth: 64,
        })).rejects.toMatchObject({
            code: "helper-timeout",
            operation: "get-thumbnail",
        });

        const [output] = fixtureOutputs();
        expect(output).toBeDefined();
        expect(existsSync(dirname(output?.outputPath ?? ""))).toBe(false);
    });

    it("returns validated caller-owned exports without buffering or deleting them", async () =>
    {
        const destinationDirectory = join(fixtureDirectory, "exports");
        mkdirSync(destinationDirectory);
        const photos = client();
        const result = await photos.exportPhoto("image-local-id", {
            destinationDirectory: relative(process.cwd(), destinationDirectory),
            version: "original",
        });

        expect(result).toMatchObject({
            assetIdentifier: "image-local-id",
            contentType: "image/jpeg",
            fileName: "IMG_0001.JPG",
            representation: "original",
        });
        expect(readFileSync(result.path, "utf8")).toBe("export:original:image-local-id");

        await expect(photos.exportPhoto("image-local-id", {
            destinationDirectory,
            version: "original",
        })).rejects.toMatchObject({ code: "output-file-exists" });

        await expect(photos.exportPhoto("replacement", {
            destinationDirectory,
            overwrite: true,
            version: "original",
        })).resolves.toMatchObject({ representation: "original" });
        expect(readFileSync(result.path, "utf8")).toBe("export:original:replacement");
    });

    it.each(["outside-path", "byte-mismatch", "wrong-asset", "wrong-representation"])("rejects invalid caller-owned export output for %s", async (identifier) =>
    {
        const destinationDirectory = join(fixtureDirectory, `exports-${identifier}`);
        mkdirSync(destinationDirectory);

        await expect(client().exportPhoto(identifier, {
            destinationDirectory,
            version: "current",
        })).rejects.toBeInstanceOf(InvalidProtocolResponseError);
    });

    it("rejects malformed payloads, mismatched operations, and unknown native errors", async () =>
    {
        setFixtureMode("malformed-authorization");
        await expect(client().authorizationStatus()).rejects.toBeInstanceOf(InvalidProtocolResponseError);

        setFixtureMode("mismatched-operation");
        await expect(client().authorizationStatus()).rejects.toBeInstanceOf(InvalidProtocolResponseError);

        setFixtureMode("unknown-error");
        await expect(client().authorizationStatus()).rejects.toBeInstanceOf(InvalidProtocolResponseError);
    });

    it("rejects incompatible helpers during the explicit handshake", async () =>
    {
        setFixtureMode("future-version");
        await expect(client().authorizationStatus()).rejects.toBeInstanceOf(IncompatibleProtocolVersionError);
    });

    it("validates public inputs with stable invalid-request errors", async () =>
    {
        expect(() => new PhotoKitClient({ helperPath: "" })).toThrow(PhotoKitError);
        await expect(client().listAssets({ limit: 0 })).rejects.toMatchObject({ code: "invalid-request" });
        await expect(client().listAssets({ limit: 201 })).rejects.toMatchObject({ code: "invalid-request" });
        await expect(client().getThumbnail("", {
            maxHeight: 64,
            maxWidth: 64,
        })).rejects.toMatchObject({ code: "invalid-request" });
        await expect(client().exportPhoto("image-local-id", {
            destinationDirectory: "",
            version: "original",
        })).rejects.toMatchObject({ code: "invalid-request" });
    });
});
