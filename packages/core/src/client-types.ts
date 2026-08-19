import type { AssetContentRepresentation, AssetMediaSubtype, AssetMediaType, PhotoExportVersion, PhotoLibraryAuthorizationStatus, ThumbnailContentMode, ThumbnailFormat } from "./protocol";

/** Construction options for the public PhotoKit client. */
export interface PhotoKitClientOptions
{
    contentTimeoutMs?: number;
    helperPath?: string;
    maxOutputBytes?: number;
    operationTimeoutMs?: number;
}

/** Runtime authorization information returned by the Photos library. */
export interface PhotoKitAuthorization
{
    canRequest: boolean;
    guidance: string;
    status: PhotoLibraryAuthorizationStatus;
}

/** Filters accepted when listing recent assets. */
export interface PhotoKitListAssetsOptions
{
    limit?: number;
    mediaType?: AssetMediaType;
}

/** Public metadata for one Photos asset. */
export interface PhotoKitAsset
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

/** Options for obtaining one bounded thumbnail. */
export interface PhotoKitThumbnailOptions
{
    allowNetworkAccess?: boolean;
    contentMode?: ThumbnailContentMode;
    format?: ThumbnailFormat;
    maxHeight: number;
    maxWidth: number;
    timeoutMs?: number;
}

/** Content metadata shared by thumbnails and exported photos. */
export interface PhotoKitContentMetadata
{
    assetIdentifier: string;
    byteLength: number;
    contentType: string;
    fileName: string;
    pixelHeight: number | null;
    pixelWidth: number | null;
    representation: AssetContentRepresentation;
    uniformTypeIdentifier: string;
}

/** A bounded thumbnail returned in Node-owned memory. */
export interface PhotoKitThumbnail extends PhotoKitContentMetadata
{
    bytes: Uint8Array;
    representation: "thumbnail";
}

/** Options for exporting one still-photo representation. */
export interface PhotoKitExportOptions
{
    allowNetworkAccess?: boolean;
    destinationDirectory: string;
    overwrite?: boolean;
    timeoutMs?: number;
    version: PhotoExportVersion;
}

/** A caller-owned photo file produced by the native helper. */
export interface PhotoKitExport extends PhotoKitContentMetadata
{
    path: string;
    representation: "current" | "original";
}
