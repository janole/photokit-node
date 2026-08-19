import type { PhotoKitAsset, PhotoKitAuthorization, PhotoKitContentMetadata, PhotoKitExport } from "@photokit-node/core";

/** Stable CLI exit codes based on the BSD sysexits values used by the native helper. */
export const cliExitCodes = {
    cannotCreate: 73,
    noInput: 66,
    noPermission: 77,
    software: 70,
    temporaryFailure: 75,
    unavailable: 69,
    usage: 64,
    versionMismatch: 78,
} as const;

/** Output sinks used by the CLI and its tests. */
export interface CliOutput
{
    stderr: (text: string) => void;
    stdout: (text: string) => void;
}

interface ErrorShape
{
    code: string;
    details?: unknown;
    message: string;
    operation?: unknown;
}

const errorExitCodes: Readonly<Record<string, number>> = {
    "asset-not-found": cliExitCodes.noInput,
    "helper-crashed": cliExitCodes.software,
    "helper-not-executable": cliExitCodes.unavailable,
    "helper-not-found": cliExitCodes.unavailable,
    "helper-output-limit": cliExitCodes.software,
    "helper-platform-unsupported": cliExitCodes.unavailable,
    "helper-timeout": cliExitCodes.temporaryFailure,
    "incompatible-protocol-version": cliExitCodes.versionMismatch,
    "invalid-native-response": cliExitCodes.software,
    "invalid-request": cliExitCodes.usage,
    "native-failure": cliExitCodes.software,
    "network-access-required": cliExitCodes.unavailable,
    "operation-cancelled": cliExitCodes.temporaryFailure,
    "output-cleanup-failed": cliExitCodes.software,
    "output-file-exists": cliExitCodes.cannotCreate,
    "output-write-failed": cliExitCodes.cannotCreate,
    "photo-library-access-unavailable": cliExitCodes.noPermission,
    "unknown-operation": cliExitCodes.usage,
    "unsupported-media": cliExitCodes.noInput,
};

function isRecord(value: unknown): value is Record<string, unknown>
{
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function errorShape(error: unknown): ErrorShape
{
    if (error instanceof Error && "code" in error && typeof error.code === "string")
    {
        const candidate = error as Error & { code: string; details?: unknown; operation?: unknown };
        return {
            code: candidate.code,
            details: candidate.details,
            message: candidate.message,
            operation: candidate.operation,
        };
    }

    if (error instanceof Error)
    {
        return { code: "native-failure", message: error.message };
    }

    return { code: "native-failure", message: "An unexpected CLI failure occurred." };
}

/** Returns the stable process exit code for a client or protocol failure. */
export function exitCodeForError(error: unknown): number
{
    return errorExitCodes[errorShape(error).code] ?? cliExitCodes.software;
}

/** Writes one client failure in human-readable or JSON form. */
export function writeCliError(error: unknown, json: boolean, output: CliOutput): void
{
    const failure = errorShape(error);

    if (json)
    {
        const details = isRecord(failure.details) ? failure.details : undefined;
        const operation = typeof failure.operation === "string" ? failure.operation : undefined;
        output.stderr(`${JSON.stringify({
            error: {
                code: failure.code,
                details,
                message: failure.message,
                operation,
            },
            success: false,
        })}\n`);
        return;
    }

    output.stderr(`photokit-node: ${failure.code}: ${failure.message}\n`);
}

/** Writes authorization data in human-readable or JSON form. */
export function writeAuthorization(value: PhotoKitAuthorization, json: boolean, output: CliOutput): void
{
    if (json)
    {
        output.stdout(`${JSON.stringify(value)}\n`);
        return;
    }

    output.stdout(`Authorization: ${value.status}\n${value.guidance}\n`);
}

function assetLine(asset: PhotoKitAsset): string
{
    const created = asset.creationDate ?? "unknown date";
    const duration = asset.duration === null ? "" : ` · ${asset.duration}s`;
    const flags = [asset.favorite ? "favorite" : "", asset.hidden ? "hidden" : ""].filter(Boolean);
    const suffix = flags.length === 0 ? "" : ` · ${flags.join(", ")}`;
    return `${asset.localIdentifier}\n  ${asset.mediaType} · ${asset.pixelWidth}×${asset.pixelHeight} · ${created}${duration}${suffix}`;
}

/** Writes recent assets in human-readable or JSON form. */
export function writeAssets(assets: PhotoKitAsset[], json: boolean, output: CliOutput): void
{
    if (json)
    {
        output.stdout(`${JSON.stringify({ assets })}\n`);
        return;
    }

    output.stdout(assets.length === 0 ? "No assets found.\n" : `${assets.map(assetLine).join("\n\n")}\n`);
}

/** JSON-safe thumbnail descriptor after the CLI has placed the bytes. */
export interface CliThumbnailDescriptor extends PhotoKitContentMetadata
{
    path: string;
    representation: "thumbnail";
}

/** Writes a placed thumbnail descriptor without embedding its bytes. */
export function writeThumbnailResult(value: CliThumbnailDescriptor, json: boolean, output: CliOutput): void
{
    if (json)
    {
        output.stdout(`${JSON.stringify(value)}\n`);
        return;
    }

    output.stdout(`Thumbnail written to ${value.path} (${value.pixelWidth}×${value.pixelHeight}, ${value.byteLength} bytes).\n`);
}

/** Writes a photo-export descriptor in human-readable or JSON form. */
export function writeExportResult(value: PhotoKitExport, json: boolean, output: CliOutput): void
{
    if (json)
    {
        output.stdout(`${JSON.stringify(value)}\n`);
        return;
    }

    output.stdout(`Photo exported to ${value.path} (${value.byteLength} bytes, ${value.representation}).\n`);
}
