import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { decodeProtocolResponse, encodeProtocolRequest, helperProtocolVersion, IncompatibleProtocolVersionError, InvalidProtocolResponseError, maximumThumbnailDimension, protocolErrorCodes } from "../src/index";

function readFixture(name: string): string
{
    const url = new URL(`../../../native/photokit-helper/Tests/PhotoKitProtocolTests/Fixtures/${name}.json`, import.meta.url);
    return readFileSync(url, "utf8");
}

function parseFixture(name: string): unknown
{
    return JSON.parse(readFixture(name));
}

describe("helper protocol", () =>
{
    it("encodes requests matching the shared fixtures", () =>
    {
        expect(JSON.parse(encodeProtocolRequest("version"))).toEqual(parseFixture("request-version"));
        expect(JSON.parse(encodeProtocolRequest("authorization-status"))).toEqual(parseFixture("request-authorization-status"));
        expect(JSON.parse(encodeProtocolRequest("list-assets", { limit: 2, mediaType: "video" }))).toEqual(parseFixture("request-list-assets"));
        expect(JSON.parse(encodeProtocolRequest("get-thumbnail", {
            allowNetworkAccess: false,
            assetIdentifier: "image-local-id",
            contentMode: "aspect-fill",
            format: "jpeg",
            maxHeight: 256,
            maxWidth: 384,
            outputPath: "/tmp/photokit-node/thumbnail.jpg",
            overwrite: false,
        }))).toEqual(parseFixture("request-get-thumbnail"));
        expect(JSON.parse(encodeProtocolRequest("export-photo", {
            allowNetworkAccess: true,
            assetIdentifier: "image-local-id",
            destinationDirectory: "/tmp/photokit-node/exports",
            overwrite: false,
            version: "original",
        }))).toEqual(parseFixture("request-export-photo"));
    });

    it("decodes success fixtures", () =>
    {
        const version = decodeProtocolResponse(readFixture("response-version-success"));
        const authorization = decodeProtocolResponse(readFixture("response-authorization-status-success"));
        const assets = decodeProtocolResponse(readFixture("response-assets-success"));
        const emptyAssets = decodeProtocolResponse(readFixture("response-assets-empty"));
        const thumbnail = decodeProtocolResponse(readFixture("response-thumbnail-success"));
        const exportPhoto = decodeProtocolResponse(readFixture("response-photo-export-success"));

        expect(version).toMatchObject({
            data: { protocolVersion: helperProtocolVersion },
            operation: "version",
            success: true,
        });
        expect(authorization).toMatchObject({
            data: { status: "not-determined" },
            operation: "authorization-status",
            success: true,
        });
        expect(assets).toMatchObject({
            data: {
                assets: [
                    { localIdentifier: "video-local-id", mediaType: "video" },
                    { duration: null, localIdentifier: "image-local-id", mediaType: "image" },
                ],
            },
            operation: "list-assets",
            success: true,
        });
        expect(emptyAssets).toEqual({
            data: { assets: [] },
            operation: "list-assets",
            protocolVersion: helperProtocolVersion,
            success: true,
        });
        expect(thumbnail).toMatchObject({
            data: {
                assetIdentifier: "image-local-id",
                file: {
                    byteLength: 48_123,
                    contentType: "image/jpeg",
                    representation: "thumbnail",
                },
            },
            operation: "get-thumbnail",
            success: true,
        });
        expect(exportPhoto).toMatchObject({
            data: {
                assetIdentifier: "image-local-id",
                file: {
                    byteLength: 4_281_932,
                    representation: "original",
                    uniformTypeIdentifier: "public.heic",
                },
            },
            operation: "export-photo",
            success: true,
        });
    });

    it.each([
        ["response-invalid-request", "invalid-request"],
        ["response-unknown-operation", "unknown-operation"],
        ["response-incompatible-version", "incompatible-protocol-version"],
        ["response-photo-library-access-unavailable", "photo-library-access-unavailable"],
        ["response-network-access-required", "network-access-required"],
        ["response-asset-not-found", "asset-not-found"],
        ["response-unsupported-media", "unsupported-media"],
        ["response-output-write-failed", "output-write-failed"],
        ["response-output-file-exists", "output-file-exists"],
        ["response-operation-cancelled", "operation-cancelled"],
    ])("decodes structured failure fixture %s", (name, code) =>
    {
        const response = decodeProtocolResponse(readFixture(name));

        expect(response).toMatchObject({
            error: { code },
            success: false,
        });
    });

    it("rejects incompatible helper versions explicitly", () =>
    {
        expect(() => decodeProtocolResponse(readFixture("response-future-version"))).toThrow(IncompatibleProtocolVersionError);

        try
        {
            decodeProtocolResponse(readFixture("response-future-version"));
        }
        catch (error)
        {
            expect(error).toMatchObject({ expected: 1, received: 2 });
        }
    });

    it("rejects malformed helper output", () =>
    {
        expect(() => decodeProtocolResponse("not json")).toThrow(InvalidProtocolResponseError);
        expect(() => decodeProtocolResponse("{\"protocolVersion\":1,\"success\":true}")).toThrow(InvalidProtocolResponseError);
    });

    it("keeps asset content out of the JSON envelope", () =>
    {
        const responses = [
            parseFixture("response-thumbnail-success"),
            parseFixture("response-photo-export-success"),
        ] as Array<{ data: { file: Record<string, unknown> } }>;

        for (const response of responses)
        {
            expect(Object.keys(response.data.file).sort()).toEqual([
                "byteLength",
                "contentType",
                "fileName",
                "path",
                "pixelHeight",
                "pixelWidth",
                "representation",
                "uniformTypeIdentifier",
            ]);
            expect(JSON.stringify(response)).not.toMatch(/base64|data:/i);
        }
    });

    it("exports the shared thumbnail dimension bound", () =>
    {
        expect(maximumThumbnailDimension).toBe(4_096);
    });

    it("exports the asset-content error taxonomy", () =>
    {
        expect(protocolErrorCodes).toEqual(expect.arrayContaining([
            "asset-not-found",
            "network-access-required",
            "operation-cancelled",
            "output-file-exists",
            "output-write-failed",
            "unsupported-media",
        ]));
    });
});
