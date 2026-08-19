import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import { decodeProtocolResponse, encodeProtocolRequest, helperProtocolVersion, IncompatibleProtocolVersionError, InvalidProtocolResponseError } from "../src/index";

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
    });

    it("decodes success fixtures", () =>
    {
        const version = decodeProtocolResponse(readFixture("response-version-success"));
        const authorization = decodeProtocolResponse(readFixture("response-authorization-status-success"));

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
    });

    it.each([
        ["response-invalid-request", "invalid-request"],
        ["response-unknown-operation", "unknown-operation"],
        ["response-incompatible-version", "incompatible-protocol-version"],
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
});
