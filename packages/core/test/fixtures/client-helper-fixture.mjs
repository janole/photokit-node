#!/usr/bin/env node

import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const request = JSON.parse(process.argv[2]);
const helperPath = fileURLToPath(import.meta.url);
const helperDirectory = dirname(helperPath);
const handshakePath = join(helperDirectory, "client-helper.handshakes");
const modePath = join(helperDirectory, "client-helper.mode");
const outputsPath = join(helperDirectory, "client-helper.outputs");
const mode = existsSync(modePath) ? readFileSync(modePath, "utf8").trim() : "success";

function response(operation, data, protocolVersion = 1)
{
    process.stdout.write(`${JSON.stringify({
        data,
        operation,
        protocolVersion,
        success: true,
    })}\n`);
}

function failure(code, message, exitCode = 70)
{
    process.stdout.write(`${JSON.stringify({
        error: { code, message },
        operation: request.operation,
        protocolVersion: 1,
        success: false,
    })}\n`);
    process.exit(exitCode);
}

function recordOutput(outputPath)
{
    appendFileSync(outputsPath, `${JSON.stringify({
        operation: request.operation,
        outputPath,
    })}\n`);
}

if (request.operation === "version")
{
    if (mode === "future-version")
    {
        response("version", { protocolVersion: 2 }, 2);
    }
    else
    {
        const count = existsSync(handshakePath) ? Number(readFileSync(handshakePath, "utf8")) : 0;
        writeFileSync(handshakePath, String(count + 1));
        response("version", { protocolVersion: 1 });
    }
}
else if (!existsSync(handshakePath))
{
    failure("native-failure", "version handshake required");
}
else if (mode === "mismatched-operation")
{
    response("version", {});
}
else if (mode === "unknown-error")
{
    failure("future-error", "unknown fixture error");
}
else
{
    switch (request.operation)
    {
    case "authorization-status":
        if (mode === "malformed-authorization")
        {
            response(request.operation, { status: "authorized" });
        }
        else
        {
            response(request.operation, {
                canRequest: false,
                guidance: "Photo access is available.",
                status: "authorized",
            });
        }
        break;
    case "authorization-request":
        response(request.operation, {
            canRequest: false,
            guidance: "Photo access is available.",
            status: "authorized",
        });
        break;
    case "list-assets":
    {
        const mediaType = request.parameters.mediaType ?? "image";
        response(request.operation, {
            assets: [{
                creationDate: "2026-08-19T09:25:42Z",
                duration: mediaType === "video" ? 12.5 : null,
                favorite: false,
                hidden: false,
                localIdentifier: `${mediaType}-local-id`,
                mediaSubtypes: [],
                mediaType,
                modificationDate: null,
                pixelHeight: 1_080,
                pixelWidth: 1_920,
            }],
        });
        break;
    }
    case "get-thumbnail":
    {
        const identifier = request.parameters.assetIdentifier;
        const outputPath = request.parameters.outputPath;
        recordOutput(outputPath);

        if (mode === "malformed-thumbnail" || mode === "crashed-thumbnail")
        {
            writeFileSync(outputPath, "partial thumbnail");

            if (mode === "malformed-thumbnail")
            {
                process.stdout.write("not-json\n");
                break;
            }

            process.stderr.write("fixture crash\n");
            process.exit(42);
        }

        if (identifier === "delay")
        {
            await new Promise((resolve) => setTimeout(resolve, 5_000));
        }

        if (identifier === "network-required")
        {
            failure("network-access-required", "fixture requires network", 69);
        }

        const bytes = Buffer.from(`thumbnail:${identifier}`);
        if (identifier !== "missing-output")
        {
            writeFileSync(outputPath, bytes);
        }

        const format = request.parameters.format;
        const describedPath = identifier === "outside-path" ? helperPath : outputPath;
        response(request.operation, {
            assetIdentifier: identifier === "wrong-asset" ? "other-asset" : identifier,
            file: {
                byteLength: identifier === "byte-mismatch" ? bytes.length + 1 : bytes.length,
                contentType: format === "png" ? "image/png" : "image/jpeg",
                fileName: basename(describedPath),
                path: describedPath,
                pixelHeight: identifier === "oversized" ? request.parameters.maxHeight + 1 : 1,
                pixelWidth: 2,
                representation: identifier === "wrong-representation" ? "original" : "thumbnail",
                uniformTypeIdentifier: format === "png" ? "public.png" : "public.jpeg",
            },
        });
        break;
    }
    case "export-photo":
    {
        const identifier = request.parameters.assetIdentifier;
        const version = request.parameters.version;
        const fileName = version === "current" ? "IMG_0001-current.jpeg" : "IMG_0001.JPG";
        const outputPath = join(request.parameters.destinationDirectory, fileName);
        recordOutput(outputPath);

        if (existsSync(outputPath) && !request.parameters.overwrite)
        {
            failure("output-file-exists", "fixture collision", 73);
        }

        const bytes = Buffer.from(`export:${version}:${identifier}`);
        writeFileSync(outputPath, bytes);
        const describedPath = identifier === "outside-path" ? helperPath : outputPath;
        response(request.operation, {
            assetIdentifier: identifier === "wrong-asset" ? "other-asset" : identifier,
            file: {
                byteLength: identifier === "byte-mismatch" ? bytes.length + 1 : bytes.length,
                contentType: "image/jpeg",
                fileName: basename(describedPath),
                path: describedPath,
                pixelHeight: 1_080,
                pixelWidth: 1_920,
                representation: identifier === "wrong-representation" ? "thumbnail" : version,
                uniformTypeIdentifier: "public.jpeg",
            },
        });
        break;
    }
    default:
        failure("unknown-operation", "unsupported fixture operation", 64);
    }
}
