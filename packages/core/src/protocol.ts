/** Protocol version shared by the Node wrapper and native helper. */
export const helperProtocolVersion = 1;

/** Operations defined by protocol version one. */
export const protocolOperations = [
    "version",
    "authorization-status",
    "authorization-request",
    "list-assets",
    "get-thumbnail",
    "export-photo",
] as const;

/** Stable errors returned by protocol version one. */
export const protocolErrorCodes = [
    "asset-not-found",
    "incompatible-protocol-version",
    "invalid-request",
    "native-failure",
    "network-access-required",
    "operation-cancelled",
    "output-file-exists",
    "output-write-failed",
    "photo-library-access-unavailable",
    "unsupported-media",
    "unknown-operation",
] as const;

/** A value representable in a JSON document. */
export type JsonValue = boolean | null | number | string | JsonValue[] | { [key: string]: JsonValue };

/** An operation supported by the current helper protocol. */
export type ProtocolOperation = typeof protocolOperations[number];

/** A stable helper protocol error code. */
export type ProtocolErrorCode = typeof protocolErrorCodes[number];

/** Request passed to the native helper as one JSON argument. */
export interface ProtocolRequestEnvelope
{
    operation: string;
    parameters: Record<string, JsonValue>;
    protocolVersion: number;
}

/** Structured failure information returned by the native helper. */
export interface ProtocolError
{
    code: string;
    details?: Record<string, JsonValue>;
    message: string;
}

/** Successful response returned by the native helper. */
export interface ProtocolSuccessEnvelope<TData = JsonValue>
{
    data: TData;
    operation: string;
    protocolVersion: number;
    success: true;
}

/** Failed response returned by the native helper. */
export interface ProtocolFailureEnvelope
{
    error: ProtocolError;
    operation: string | null;
    protocolVersion: number;
    success: false;
}

/** Response returned by the native helper. */
export type ProtocolResponseEnvelope<TData = JsonValue> = ProtocolFailureEnvelope | ProtocolSuccessEnvelope<TData>;

/** Photo library authorization states returned by the native helper. */
export type PhotoLibraryAuthorizationStatus = "authorized" | "denied" | "limited" | "not-determined" | "restricted";

/** Data returned by the native helper's version operation. */
export interface HelperVersionData
{
    protocolVersion: number;
}

/** Data returned by the native helper's authorization operations. */
export interface AuthorizationStatusData
{
    canRequest: boolean;
    guidance: string;
    status: PhotoLibraryAuthorizationStatus;
}

/** Image and video media types exposed by the helper. */
export type AssetMediaType = "image" | "video";

/** Stable names for PhotoKit media-subtype flags. */
export type AssetMediaSubtype = "photo-depth-effect" | "photo-hdr" | "photo-live" | "photo-panorama" | "photo-screenshot" | "spatial-media" | "video-cinematic" | "video-high-frame-rate" | "video-streamed" | "video-timelapse";

/** Parameters accepted by the list-assets operation. */
export interface ListAssetsParameters
{
    limit?: number;
    mediaType?: AssetMediaType;
}

/** Metadata returned for one PhotoKit asset without requesting its content. */
export interface AssetMetadata
{
    creationDate: string | null;
    duration: number | null;
    favorite: boolean;
    hidden: boolean;
    localIdentifier: string;
    mediaSubtypes: AssetMediaSubtype[];
    mediaType: AssetMediaType;
    modificationDate: string | null;
    pixelHeight: number;
    pixelWidth: number;
}

/** Data returned by the list-assets operation. */
export interface AssetListData
{
    assets: AssetMetadata[];
}

/** Maximum width or height accepted by the thumbnail contract. */
export const maximumThumbnailDimension = 4_096;

/** Crop behavior for a rendered thumbnail. */
export type ThumbnailContentMode = "aspect-fill" | "aspect-fit";

/** Encodings supported for rendered thumbnails. */
export type ThumbnailFormat = "jpeg" | "png";

/** Parameters accepted by the get-thumbnail operation. */
export interface GetThumbnailParameters
{
    allowNetworkAccess?: boolean;
    assetIdentifier: string;
    contentMode?: ThumbnailContentMode;
    format?: ThumbnailFormat;
    maxHeight: number;
    maxWidth: number;
    outputPath: string;
    overwrite?: boolean;
}

/** Still-photo representation selected for export. */
export type PhotoExportVersion = "current" | "original";

/** Parameters accepted by the export-photo operation. */
export interface ExportPhotoParameters
{
    allowNetworkAccess?: boolean;
    assetIdentifier: string;
    destinationDirectory: string;
    overwrite?: boolean;
    version: PhotoExportVersion;
}

/** Kind of image content written by an asset-content operation. */
export type AssetContentRepresentation = "current" | "original" | "thumbnail";

/** File produced out of band by an asset-content operation. */
export interface AssetContentFileDescriptor
{
    byteLength: number;
    contentType: string;
    fileName: string;
    path: string;
    pixelHeight: number | null;
    pixelWidth: number | null;
    representation: AssetContentRepresentation;
    uniformTypeIdentifier: string;
}

/** Data returned by get-thumbnail and export-photo. */
export interface AssetContentData
{
    assetIdentifier: string;
    file: AssetContentFileDescriptor;
}

/** Indicates that a helper response does not match the protocol envelope. */
export class InvalidProtocolResponseError extends Error
{
    public readonly code = "invalid-native-response";

    public constructor(message: string, options?: ErrorOptions)
    {
        super(message, options);
        this.name = "InvalidProtocolResponseError";
    }
}

/** Indicates that the native helper uses a different protocol version. */
export class IncompatibleProtocolVersionError extends Error
{
    public readonly code = "incompatible-protocol-version";
    public readonly expected: number;
    public readonly received: number;

    public constructor(expected: number, received: number)
    {
        super(`Expected helper protocol version ${expected}, received ${received}.`);
        this.name = "IncompatibleProtocolVersionError";
        this.expected = expected;
        this.received = received;
    }
}

function isRecord(value: unknown): value is Record<string, unknown>
{
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isJsonValue(value: unknown): value is JsonValue
{
    if (value === null || ["boolean", "number", "string"].includes(typeof value))
    {
        return typeof value !== "number" || Number.isFinite(value);
    }

    if (Array.isArray(value))
    {
        return value.every(isJsonValue);
    }

    return isRecord(value) && Object.values(value).every(isJsonValue);
}

function decodeError(value: unknown): ProtocolError
{
    if (!isRecord(value) || typeof value.code !== "string" || typeof value.message !== "string")
    {
        throw new InvalidProtocolResponseError("Helper failure is missing a structured error.");
    }

    if (value.details !== undefined && (!isRecord(value.details) || !isJsonValue(value.details)))
    {
        throw new InvalidProtocolResponseError("Helper failure contains invalid error details.");
    }

    return {
        code: value.code,
        details: value.details,
        message: value.message,
    };
}

/** Encodes one operation as the native helper's JSON request argument. */
export function encodeProtocolRequest(
    operation: ProtocolOperation,
    parameters: Record<string, JsonValue> = {},
): string
{
    const request: ProtocolRequestEnvelope = {
        operation,
        parameters,
        protocolVersion: helperProtocolVersion,
    };

    return JSON.stringify(request);
}

/** Decodes and validates one JSON response from the native helper. */
export function decodeProtocolResponse(input: string): ProtocolResponseEnvelope
{
    let value: unknown;

    try
    {
        value = JSON.parse(input);
    }
    catch (error)
    {
        throw new InvalidProtocolResponseError("Helper response is not valid JSON.", { cause: error });
    }

    if (!isRecord(value) || !Number.isInteger(value.protocolVersion))
    {
        throw new InvalidProtocolResponseError("Helper response is missing an integer protocolVersion.");
    }

    if (value.protocolVersion !== helperProtocolVersion)
    {
        throw new IncompatibleProtocolVersionError(helperProtocolVersion, value.protocolVersion as number);
    }

    if (value.success === true && typeof value.operation === "string" && isJsonValue(value.data))
    {
        return {
            data: value.data,
            operation: value.operation,
            protocolVersion: value.protocolVersion as number,
            success: true,
        };
    }

    if (value.success === false && (typeof value.operation === "string" || value.operation === null))
    {
        return {
            error: decodeError(value.error),
            operation: value.operation,
            protocolVersion: value.protocolVersion as number,
            success: false,
        };
    }

    throw new InvalidProtocolResponseError("Helper response does not match a success or failure envelope.");
}
