import type { JsonValue, ProtocolErrorCode, ProtocolOperation } from "./protocol";

/** Client-side failures that can occur around the native protocol. */
export const clientErrorCodes = [
    "helper-crashed",
    "helper-not-executable",
    "helper-not-found",
    "helper-output-limit",
    "helper-platform-unsupported",
    "helper-timeout",
    "output-cleanup-failed",
] as const;

/** Stable error codes surfaced by the public PhotoKit client. */
export type PhotoKitErrorCode = ProtocolErrorCode | typeof clientErrorCodes[number];

interface PhotoKitErrorOptions extends ErrorOptions
{
    details?: Record<string, JsonValue>;
    operation?: ProtocolOperation;
}

/** A stable native-operation or client-runtime failure. */
export class PhotoKitError extends Error
{
    public readonly code: PhotoKitErrorCode;
    public readonly details?: Record<string, JsonValue>;
    public readonly operation?: ProtocolOperation;

    public constructor(code: PhotoKitErrorCode, message: string, options: PhotoKitErrorOptions = {})
    {
        super(message, options);
        this.name = "PhotoKitError";
        this.code = code;
        this.details = options.details;
        this.operation = options.operation;
    }
}
