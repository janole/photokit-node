import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import type { PhotoKitAsset, PhotoKitAuthorization, PhotoKitExport, PhotoKitThumbnail } from "@photokit-node/core";
import { helperProtocolVersion, PhotoKitError } from "@photokit-node/core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { CliPhotoKitClient } from "../src/index";
import { runCli } from "../src/index";

const authorization: PhotoKitAuthorization = {
    canRequest: false,
    guidance: "Photo library access is available.",
    status: "authorized",
};
const asset: PhotoKitAsset = {
    creationDate: "2026-08-19T09:25:42Z",
    duration: null,
    favorite: true,
    hidden: false,
    localIdentifier: "image-local-id",
    mediaSubtypes: ["photo-hdr"],
    mediaType: "image",
    modificationDate: null,
    pixelHeight: 1_080,
    pixelWidth: 1_920,
};
const thumbnail: PhotoKitThumbnail = {
    assetIdentifier: asset.localIdentifier,
    byteLength: 15,
    bytes: new Uint8Array(Buffer.from("thumbnail-bytes")),
    contentType: "image/jpeg",
    fileName: "thumbnail.jpg",
    pixelHeight: 120,
    pixelWidth: 160,
    representation: "thumbnail",
    uniformTypeIdentifier: "public.jpeg",
};

interface Execution
{
    client: CliPhotoKitClient;
    exitCode: number;
    stderr: string;
    stdout: string;
}

let directory: string;

function fakeClient(overrides: Partial<CliPhotoKitClient> = {}): CliPhotoKitClient
{
    const exported: PhotoKitExport = {
        assetIdentifier: asset.localIdentifier,
        byteLength: 1_024,
        contentType: "image/jpeg",
        fileName: "IMG_0001.JPG",
        path: join(directory, "IMG_0001.JPG"),
        pixelHeight: asset.pixelHeight,
        pixelWidth: asset.pixelWidth,
        representation: "original",
        uniformTypeIdentifier: "public.jpeg",
    };

    return {
        authorizationStatus: vi.fn().mockResolvedValue(authorization),
        exportPhoto: vi.fn().mockResolvedValue(exported),
        getThumbnail: vi.fn().mockResolvedValue(thumbnail),
        listAssets: vi.fn().mockResolvedValue([asset]),
        requestAuthorization: vi.fn().mockResolvedValue(authorization),
        ...overrides,
    };
}

async function execute(arguments_: string[], overrides: Partial<CliPhotoKitClient> = {}): Promise<Execution>
{
    const stderr: string[] = [];
    const stdout: string[] = [];
    const client = fakeClient(overrides);
    const exitCode = await runCli(["node", "photokit-node", ...arguments_], {
        client,
        stderr: (text) => stderr.push(text),
        stdout: (text) => stdout.push(text),
    });

    return {
        client,
        exitCode,
        stderr: stderr.join(""),
        stdout: stdout.join(""),
    };
}

beforeEach(() =>
{
    directory = mkdtempSync(join(tmpdir(), "photokit-cli-"));
});

afterEach(() =>
{
    rmSync(directory, { force: true, recursive: true });
});

describe("photokit-node CLI", () =>
{
    it("preserves the protocol-version diagnostic", async () =>
    {
        const result = await execute(["protocol-version"]);

        expect(result).toMatchObject({ exitCode: 0, stderr: "", stdout: `${helperProtocolVersion}\n` });
    });

    it("prints authorization as human text or JSON and reflects unavailable access", async () =>
    {
        const human = await execute(["authorization", "status"]);
        expect(human).toMatchObject({
            exitCode: 0,
            stdout: "Authorization: authorized\nPhoto library access is available.\n",
        });

        const denied: PhotoKitAuthorization = {
            canRequest: false,
            guidance: "Access was denied.",
            status: "denied",
        };
        const json = await execute(["authorization", "request", "--json"], {
            requestAuthorization: vi.fn().mockResolvedValue(denied),
        });
        expect(json.exitCode).toBe(77);
        expect(JSON.parse(json.stdout)).toEqual(denied);
        expect(json.stderr).toBe("");
    });

    it("parses asset-list filters and returns stable JSON", async () =>
    {
        const result = await execute(["assets", "list", "--limit", "5", "--media-type", "image", "--json"]);

        expect(result.exitCode).toBe(0);
        expect(result.client.listAssets).toHaveBeenCalledWith({ limit: 5, mediaType: "image" });
        expect(JSON.parse(result.stdout)).toEqual({ assets: [asset] });
    });

    it("writes thumbnail bytes and omits them from its JSON descriptor", async () =>
    {
        const outputPath = join(directory, "preview.jpg");
        const result = await execute([
            "assets", "thumbnail", asset.localIdentifier,
            "--output", outputPath,
            "--max-width", "160",
            "--max-height", "120",
            "--json",
        ]);

        expect(result.exitCode).toBe(0);
        expect(result.client.getThumbnail).toHaveBeenCalledWith(asset.localIdentifier, {
            allowNetworkAccess: false,
            contentMode: "aspect-fit",
            format: "jpeg",
            maxHeight: 120,
            maxWidth: 160,
        });
        expect(readFileSync(outputPath, "utf8")).toBe("thumbnail-bytes");
        expect(JSON.parse(result.stdout)).toEqual({
            assetIdentifier: asset.localIdentifier,
            byteLength: 15,
            contentType: "image/jpeg",
            fileName: "preview.jpg",
            path: resolve(outputPath),
            pixelHeight: 120,
            pixelWidth: 160,
            representation: "thumbnail",
            uniformTypeIdentifier: "public.jpeg",
        });
        expect(result.stdout).not.toContain("bytes\"");
    });

    it("preserves existing thumbnail output unless overwrite is explicit", async () =>
    {
        const outputPath = join(directory, "preview.jpg");
        writeFileSync(outputPath, "existing");

        const collision = await execute([
            "assets", "thumbnail", asset.localIdentifier,
            "--output", outputPath,
            "--max-width", "160",
            "--max-height", "120",
        ]);
        expect(collision.exitCode).toBe(73);
        expect(collision.stderr).toContain("output-file-exists");
        expect(readFileSync(outputPath, "utf8")).toBe("existing");

        const replacement = await execute([
            "assets", "thumbnail", asset.localIdentifier,
            "--output", outputPath,
            "--max-width", "160",
            "--max-height", "120",
            "--overwrite",
        ]);
        expect(replacement.exitCode).toBe(0);
        expect(readFileSync(outputPath, "utf8")).toBe("thumbnail-bytes");
    });

    it("passes export ownership and network options through to the client", async () =>
    {
        const result = await execute([
            "assets", "export", asset.localIdentifier,
            "--output-directory", directory,
            "--version", "original",
            "--allow-network",
            "--overwrite",
            "--json",
        ]);

        expect(result.exitCode).toBe(0);
        expect(result.client.exportPhoto).toHaveBeenCalledWith(asset.localIdentifier, {
            allowNetworkAccess: true,
            destinationDirectory: directory,
            overwrite: true,
            version: "original",
        });
        expect(JSON.parse(result.stdout)).toMatchObject({ path: join(directory, "IMG_0001.JPG"), representation: "original" });
    });

    it("maps client errors to stable exit codes and JSON failures", async () =>
    {
        const result = await execute(["assets", "list", "--json"], {
            listAssets: vi.fn().mockRejectedValue(new PhotoKitError(
                "photo-library-access-unavailable",
                "Photos access is denied.",
                { details: { status: "denied" }, operation: "list-assets" },
            )),
        });

        expect(result.exitCode).toBe(77);
        expect(result.stdout).toBe("");
        expect(JSON.parse(result.stderr)).toEqual({
            error: {
                code: "photo-library-access-unavailable",
                details: { status: "denied" },
                message: "Photos access is denied.",
                operation: "list-assets",
            },
            success: false,
        });
    });

    it("uses the usage exit code for invalid Commander options", async () =>
    {
        const result = await execute(["assets", "list", "--limit", "201"]);

        expect(result.exitCode).toBe(64);
        expect(result.stderr).toContain("must not exceed 200");
        expect(result.client.listAssets).not.toHaveBeenCalled();
        expect(existsSync(join(directory, "IMG_0001.JPG"))).toBe(false);

        const json = await execute(["assets", "list", "--limit", "201", "--json"]);
        expect(json.exitCode).toBe(64);
        expect(JSON.parse(json.stderr)).toEqual({
            error: {
                code: "invalid-request",
                message: "error: option '--limit <count>' argument '201' is invalid. must not exceed 200",
            },
            success: false,
        });
    });
});
