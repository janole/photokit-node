import { isAbsolute } from "node:path";

import type { PhotoKitAsset } from "./client-types";
import type { AssetContentData, AssetContentFileDescriptor, AssetMediaSubtype, AssetMediaType, AuthorizationStatusData, HelperVersionData, PhotoLibraryAuthorizationStatus } from "./protocol";
import { helperProtocolVersion, InvalidProtocolResponseError } from "./protocol";

const authorizationStatuses = new Set<PhotoLibraryAuthorizationStatus>([
    "authorized",
    "denied",
    "limited",
    "not-determined",
    "restricted",
]);
const mediaTypes = new Set<AssetMediaType>(["image", "video"]);
const mediaSubtypes = new Set<AssetMediaSubtype>([
    "photo-depth-effect",
    "photo-hdr",
    "photo-live",
    "photo-panorama",
    "photo-screenshot",
    "spatial-media",
    "video-cinematic",
    "video-high-frame-rate",
    "video-streamed",
    "video-timelapse",
]);

function invalid(message: string): never
{
    throw new InvalidProtocolResponseError(message);
}

function record(value: unknown, label: string): Record<string, unknown>
{
    if (typeof value !== "object" || value === null || Array.isArray(value))
    {
        invalid(`${label} must be an object.`);
    }

    return value as Record<string, unknown>;
}

function nonEmptyString(value: unknown, label: string): string
{
    if (typeof value !== "string" || value.length === 0)
    {
        invalid(`${label} must be a non-empty string.`);
    }

    return value;
}

function booleanValue(value: unknown, label: string): boolean
{
    if (typeof value !== "boolean")
    {
        invalid(`${label} must be a boolean.`);
    }

    return value;
}

function integer(value: unknown, label: string, minimum: number): number
{
    if (!Number.isInteger(value) || (value as number) < minimum)
    {
        invalid(`${label} must be an integer greater than or equal to ${minimum}.`);
    }

    return value as number;
}

function nullablePositiveInteger(value: unknown, label: string): number | null
{
    if (value === null)
    {
        return null;
    }

    return integer(value, label, 1);
}

function nullableDate(value: unknown, label: string): string | null
{
    if (value === null)
    {
        return null;
    }

    const text = nonEmptyString(value, label);
    if (!Number.isFinite(Date.parse(text)))
    {
        invalid(`${label} must be a valid date string or null.`);
    }

    return text;
}

/** Validates the version handshake payload. */
export function validateHelperVersionData(value: unknown): HelperVersionData
{
    const data = record(value, "Version data");
    if (data.protocolVersion !== helperProtocolVersion)
    {
        invalid(`Version data must report protocol version ${helperProtocolVersion}.`);
    }

    return { protocolVersion: helperProtocolVersion };
}

/** Validates one authorization operation payload. */
export function validateAuthorizationStatusData(value: unknown): AuthorizationStatusData
{
    const data = record(value, "Authorization data");
    const status = nonEmptyString(data.status, "Authorization status");

    if (!authorizationStatuses.has(status as PhotoLibraryAuthorizationStatus))
    {
        invalid(`Authorization status "${status}" is unsupported.`);
    }

    return {
        canRequest: booleanValue(data.canRequest, "Authorization canRequest"),
        guidance: nonEmptyString(data.guidance, "Authorization guidance"),
        status: status as PhotoLibraryAuthorizationStatus,
    };
}

/** Validates one recent-asset listing payload. */
export function validateAssetListData(value: unknown): PhotoKitAsset[]
{
    const data = record(value, "Asset-list data");
    if (!Array.isArray(data.assets))
    {
        invalid("Asset-list data must contain an assets array.");
    }

    return data.assets.map((item, index) =>
    {
        const asset = record(item, `Asset ${index}`);
        const mediaType = nonEmptyString(asset.mediaType, `Asset ${index} mediaType`);
        if (!mediaTypes.has(mediaType as AssetMediaType))
        {
            invalid(`Asset ${index} mediaType "${mediaType}" is unsupported.`);
        }

        if (!Array.isArray(asset.mediaSubtypes))
        {
            invalid(`Asset ${index} mediaSubtypes must be an array.`);
        }

        const subtypes = asset.mediaSubtypes.map((subtype, subtypeIndex) =>
        {
            const name = nonEmptyString(subtype, `Asset ${index} mediaSubtypes[${subtypeIndex}]`);
            if (!mediaSubtypes.has(name as AssetMediaSubtype))
            {
                invalid(`Asset ${index} media subtype "${name}" is unsupported.`);
            }

            return name as AssetMediaSubtype;
        });

        let duration: number | null;
        if (asset.duration === null)
        {
            duration = null;
        }
        else if (typeof asset.duration === "number" && Number.isFinite(asset.duration) && asset.duration >= 0)
        {
            duration = asset.duration;
        }
        else
        {
            invalid(`Asset ${index} duration must be a non-negative number or null.`);
        }

        return {
            creationDate: nullableDate(asset.creationDate, `Asset ${index} creationDate`),
            duration,
            favorite: booleanValue(asset.favorite, `Asset ${index} favorite`),
            hidden: booleanValue(asset.hidden, `Asset ${index} hidden`),
            localIdentifier: nonEmptyString(asset.localIdentifier, `Asset ${index} localIdentifier`),
            mediaSubtypes: subtypes,
            mediaType: mediaType as AssetMediaType,
            modificationDate: nullableDate(asset.modificationDate, `Asset ${index} modificationDate`),
            pixelHeight: integer(asset.pixelHeight, `Asset ${index} pixelHeight`, 0),
            pixelWidth: integer(asset.pixelWidth, `Asset ${index} pixelWidth`, 0),
        };
    });
}

function validateFileDescriptor(value: unknown): AssetContentFileDescriptor
{
    const file = record(value, "Asset-content file");
    const path = nonEmptyString(file.path, "Asset-content path");
    if (!isAbsolute(path))
    {
        invalid("Asset-content path must be absolute.");
    }

    const representation = nonEmptyString(file.representation, "Asset-content representation");
    if (!["current", "original", "thumbnail"].includes(representation))
    {
        invalid(`Asset-content representation "${representation}" is unsupported.`);
    }

    return {
        byteLength: integer(file.byteLength, "Asset-content byteLength", 1),
        contentType: nonEmptyString(file.contentType, "Asset-content contentType"),
        fileName: nonEmptyString(file.fileName, "Asset-content fileName"),
        path,
        pixelHeight: nullablePositiveInteger(file.pixelHeight, "Asset-content pixelHeight"),
        pixelWidth: nullablePositiveInteger(file.pixelWidth, "Asset-content pixelWidth"),
        representation: representation as AssetContentFileDescriptor["representation"],
        uniformTypeIdentifier: nonEmptyString(file.uniformTypeIdentifier, "Asset-content uniformTypeIdentifier"),
    };
}

/** Validates one thumbnail or photo-export payload and its operation invariants. */
export function validateAssetContentData(
    value: unknown,
    expectedAssetIdentifier: string,
    expectedRepresentation: AssetContentFileDescriptor["representation"],
): AssetContentData
{
    const data = record(value, "Asset-content data");
    const assetIdentifier = nonEmptyString(data.assetIdentifier, "Asset-content assetIdentifier");
    if (assetIdentifier !== expectedAssetIdentifier)
    {
        invalid("Asset-content response uses an unexpected asset identifier.");
    }

    const file = validateFileDescriptor(data.file);
    if (file.representation !== expectedRepresentation)
    {
        invalid(`Asset-content response uses representation "${file.representation}" instead of "${expectedRepresentation}".`);
    }

    return { assetIdentifier, file };
}
