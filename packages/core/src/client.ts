import { lstat, mkdtemp, readFile, realpath, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";

import type { PhotoKitAsset, PhotoKitAuthorization, PhotoKitClientOptions, PhotoKitContentMetadata, PhotoKitExport, PhotoKitExportOptions, PhotoKitListAssetsOptions, PhotoKitThumbnail, PhotoKitThumbnailOptions } from "./client-types";
import { PhotoKitError } from "./errors";
import type { HelperRunnerOptions } from "./helper-runner";
import { defaultHelperMaxOutputBytes, defaultHelperTimeoutMs, HelperCrashedError, HelperNotExecutableError, HelperNotFoundError, HelperOutputLimitError, HelperPlatformUnsupportedError, HelperTimeoutError, runHelper } from "./helper-runner";
import type { AssetContentData, JsonValue, ProtocolErrorCode, ProtocolOperation, ProtocolResponseEnvelope, ThumbnailContentMode, ThumbnailFormat } from "./protocol";
import { IncompatibleProtocolVersionError, InvalidProtocolResponseError, maximumThumbnailDimension, protocolErrorCodes } from "./protocol";
import { validateAssetContentData, validateAssetListData, validateAuthorizationStatusData, validateHelperVersionData } from "./validation";

/** Default deadline for an operation that can retrieve image content. */
export const defaultPhotoKitContentTimeoutMs = 120_000;

/** Largest recent-asset result accepted by the native helper. */
export const maximumPhotoKitAssetLimit = 200;

function invalidRequest(message: string): never
{
    throw new PhotoKitError("invalid-request", message);
}

function positiveInteger(value: number, label: string): number
{
    if (!Number.isInteger(value) || value <= 0)
    {
        invalidRequest(`${label} must be a positive integer.`);
    }

    return value;
}

function optionalBoolean(value: boolean | undefined, label: string): boolean | undefined
{
    if (value !== undefined && typeof value !== "boolean")
    {
        invalidRequest(`${label} must be a boolean when provided.`);
    }

    return value;
}

function assetIdentifier(value: string): string
{
    if (typeof value !== "string" || value.trim().length === 0)
    {
        invalidRequest("assetIdentifier must be a non-empty string.");
    }

    return value;
}

function isProtocolErrorCode(value: string): value is ProtocolErrorCode
{
    return (protocolErrorCodes as readonly string[]).includes(value);
}

function acceptResponse(response: ProtocolResponseEnvelope, operation: ProtocolOperation): unknown
{
    if (response.operation !== operation)
    {
        throw new InvalidProtocolResponseError(`Expected operation "${operation}", received "${response.operation ?? "null"}".`);
    }

    if (!response.success)
    {
        if (!isProtocolErrorCode(response.error.code))
        {
            throw new InvalidProtocolResponseError(`Helper returned unknown error code "${response.error.code}".`);
        }

        throw new PhotoKitError(response.error.code, response.error.message, {
            details: response.error.details,
            operation,
        });
    }

    return response.data;
}

function contentParameters(options: { allowNetworkAccess?: boolean; timeoutMs?: number }): boolean
{
    if (options.timeoutMs !== undefined)
    {
        positiveInteger(options.timeoutMs, "timeoutMs");
    }

    return optionalBoolean(options.allowNetworkAccess, "allowNetworkAccess") ?? false;
}

function thumbnailDimension(value: number, label: string): number
{
    const dimension = positiveInteger(value, label);
    if (dimension > maximumThumbnailDimension)
    {
        invalidRequest(`Thumbnail dimensions cannot exceed ${maximumThumbnailDimension} pixels.`);
    }

    return dimension;
}

function thumbnailFormat(value: ThumbnailFormat | undefined): ThumbnailFormat
{
    const format = value ?? "jpeg";
    if (!["jpeg", "png"].includes(format))
    {
        invalidRequest("format must be jpeg or png.");
    }

    return format;
}

function thumbnailContentMode(value: ThumbnailContentMode | undefined): ThumbnailContentMode
{
    const contentMode = value ?? "aspect-fit";
    if (!["aspect-fit", "aspect-fill"].includes(contentMode))
    {
        invalidRequest("contentMode must be aspect-fit or aspect-fill.");
    }

    return contentMode;
}

function metadata(data: AssetContentData): PhotoKitContentMetadata
{
    return {
        assetIdentifier: data.assetIdentifier,
        byteLength: data.file.byteLength,
        contentType: data.file.contentType,
        fileName: data.file.fileName,
        pixelHeight: data.file.pixelHeight,
        pixelWidth: data.file.pixelWidth,
        representation: data.file.representation,
        uniformTypeIdentifier: data.file.uniformTypeIdentifier,
    };
}

async function regularFile(path: string): Promise<{ canonicalPath: string; size: number }>
{
    try
    {
        const information = await lstat(path);
        if (!information.isFile() || information.isSymbolicLink())
        {
            throw new InvalidProtocolResponseError("Native output must be a regular file.");
        }

        return {
            canonicalPath: await realpath(path),
            size: information.size,
        };
    }
    catch (error)
    {
        if (error instanceof InvalidProtocolResponseError)
        {
            throw error;
        }

        throw new InvalidProtocolResponseError("Native output file is missing or inaccessible.", { cause: error });
    }
}

async function removeThumbnailDirectory(directory: string): Promise<void>
{
    try
    {
        await rm(directory, { force: true, recursive: true });
    }
    catch (error)
    {
        throw new PhotoKitError(
            "output-cleanup-failed",
            "Could not remove the Node-owned thumbnail files.",
            { cause: error, operation: "get-thumbnail" },
        );
    }
}

async function createThumbnailDirectory(): Promise<string>
{
    try
    {
        return await mkdtemp(join(tmpdir(), "photokit-node-thumbnail-"));
    }
    catch (error)
    {
        throw new PhotoKitError(
            "output-write-failed",
            "Could not create Node-owned thumbnail storage.",
            { cause: error, operation: "get-thumbnail" },
        );
    }
}

function validateFileIdentity(data: AssetContentData, canonicalPath: string, size: number): void
{
    if (data.file.byteLength !== size)
    {
        throw new InvalidProtocolResponseError("Native output byteLength does not match the file on disk.");
    }

    if (data.file.fileName !== basename(canonicalPath))
    {
        throw new InvalidProtocolResponseError("Native output fileName does not match its final path.");
    }
}

async function thumbnailResult(
    data: AssetContentData,
    outputPath: string,
    format: ThumbnailFormat,
    maxHeight: number,
    maxWidth: number,
): Promise<PhotoKitThumbnail>
{
    const expectedFile = await regularFile(outputPath);
    const describedFile = await regularFile(data.file.path);

    if (expectedFile.canonicalPath !== describedFile.canonicalPath)
    {
        throw new InvalidProtocolResponseError("Thumbnail response points outside its Node-owned temporary path.");
    }

    validateFileIdentity(data, describedFile.canonicalPath, describedFile.size);
    if (data.file.pixelHeight === null || data.file.pixelWidth === null
        || data.file.pixelHeight > maxHeight || data.file.pixelWidth > maxWidth)
    {
        throw new InvalidProtocolResponseError("Thumbnail dimensions exceed the requested bounds.");
    }

    const expectedContentType = format === "png" ? "image/png" : "image/jpeg";
    const expectedTypeIdentifier = format === "png" ? "public.png" : "public.jpeg";
    if (data.file.contentType !== expectedContentType
        || data.file.uniformTypeIdentifier !== expectedTypeIdentifier)
    {
        throw new InvalidProtocolResponseError("Thumbnail encoding metadata does not match the requested format.");
    }

    const bytes = await readFile(outputPath);
    if (bytes.byteLength !== data.file.byteLength)
    {
        throw new InvalidProtocolResponseError("Thumbnail byteLength does not match the bytes read by Node.");
    }

    return {
        ...metadata(data),
        bytes: new Uint8Array(bytes),
        representation: "thumbnail",
    };
}

/** Typed, read-only access to the macOS Photos library through the native helper. */
export class PhotoKitClient
{
    readonly #contentTimeoutMs: number;
    readonly #helperPath?: string;
    #handshake?: Promise<void>;
    readonly #maxOutputBytes: number;
    readonly #operationTimeoutMs: number;

    public constructor(options: PhotoKitClientOptions = {})
    {
        this.#contentTimeoutMs = positiveInteger(
            options.contentTimeoutMs ?? defaultPhotoKitContentTimeoutMs,
            "contentTimeoutMs",
        );
        this.#operationTimeoutMs = positiveInteger(
            options.operationTimeoutMs ?? defaultHelperTimeoutMs,
            "operationTimeoutMs",
        );
        this.#maxOutputBytes = positiveInteger(
            options.maxOutputBytes ?? defaultHelperMaxOutputBytes,
            "maxOutputBytes",
        );

        if (options.helperPath !== undefined
            && (typeof options.helperPath !== "string" || options.helperPath.length === 0))
        {
            invalidRequest("helperPath must be a non-empty string when provided.");
        }

        this.#helperPath = options.helperPath;
    }

    /** Reads the current Photos authorization state without prompting. */
    public async authorizationStatus(): Promise<PhotoKitAuthorization>
    {
        return validateAuthorizationStatusData(await this.#invoke(
            "authorization-status",
            {},
            this.#operationTimeoutMs,
        ));
    }

    /** Requests Photos authorization when the state is not yet determined. */
    public async requestAuthorization(): Promise<PhotoKitAuthorization>
    {
        return validateAuthorizationStatusData(await this.#invoke(
            "authorization-request",
            {},
            this.#operationTimeoutMs,
        ));
    }

    /** Lists recent image and video metadata without requesting content bytes. */
    public async listAssets(options: PhotoKitListAssetsOptions = {}): Promise<PhotoKitAsset[]>
    {
        const parameters: Record<string, JsonValue> = {};

        if (options.limit !== undefined)
        {
            const limit = positiveInteger(options.limit, "limit");
            if (limit > maximumPhotoKitAssetLimit)
            {
                invalidRequest(`limit cannot exceed ${maximumPhotoKitAssetLimit}.`);
            }

            parameters.limit = limit;
        }

        if (options.mediaType !== undefined)
        {
            if (!["image", "video"].includes(options.mediaType))
            {
                invalidRequest("mediaType must be image or video.");
            }

            parameters.mediaType = options.mediaType;
        }

        return validateAssetListData(await this.#invoke(
            "list-assets",
            parameters,
            this.#operationTimeoutMs,
        ));
    }

    /** Returns one bounded thumbnail and always removes its temporary file. */
    public async getThumbnail(identifier: string, options: PhotoKitThumbnailOptions): Promise<PhotoKitThumbnail>
    {
        const validatedIdentifier = assetIdentifier(identifier);
        const maxHeight = thumbnailDimension(options.maxHeight, "maxHeight");
        const maxWidth = thumbnailDimension(options.maxWidth, "maxWidth");
        const format = thumbnailFormat(options.format);
        const contentMode = thumbnailContentMode(options.contentMode);
        const timeoutMs = options.timeoutMs ?? this.#contentTimeoutMs;
        const directory = await createThumbnailDirectory();
        const outputPath = join(directory, format === "png" ? "thumbnail.png" : "thumbnail.jpg");
        let result: PhotoKitThumbnail;

        try
        {
            const data = validateAssetContentData(await this.#invoke(
                "get-thumbnail",
                {
                    allowNetworkAccess: contentParameters(options),
                    assetIdentifier: validatedIdentifier,
                    contentMode,
                    format,
                    maxHeight,
                    maxWidth,
                    outputPath,
                    overwrite: false,
                },
                timeoutMs,
            ), validatedIdentifier, "thumbnail");
            result = await thumbnailResult(data, outputPath, format, maxHeight, maxWidth);
        }
        catch (error)
        {
            await removeThumbnailDirectory(directory);
            throw error;
        }

        await removeThumbnailDirectory(directory);
        return result;
    }

    /** Exports one current or original still-photo representation to a caller-owned directory. */
    public async exportPhoto(identifier: string, options: PhotoKitExportOptions): Promise<PhotoKitExport>
    {
        const validatedIdentifier = assetIdentifier(identifier);
        if (typeof options.destinationDirectory !== "string" || options.destinationDirectory.length === 0)
        {
            invalidRequest("destinationDirectory must be a non-empty path.");
        }

        if (!["current", "original"].includes(options.version))
        {
            invalidRequest("version must be current or original.");
        }

        const timeoutMs = options.timeoutMs ?? this.#contentTimeoutMs;
        contentParameters(options);
        const overwrite = optionalBoolean(options.overwrite, "overwrite") ?? false;
        const destinationPath = await realpath(resolve(options.destinationDirectory)).catch((error: unknown) =>
        {
            throw new PhotoKitError("output-write-failed", "The destination directory is missing or inaccessible.", {
                cause: error,
                operation: "export-photo",
            });
        });
        const destinationInformation = await lstat(destinationPath);
        if (!destinationInformation.isDirectory())
        {
            invalidRequest("destinationDirectory must identify a directory.");
        }

        const data = validateAssetContentData(await this.#invoke(
            "export-photo",
            {
                allowNetworkAccess: options.allowNetworkAccess ?? false,
                assetIdentifier: validatedIdentifier,
                destinationDirectory: destinationPath,
                overwrite,
                version: options.version,
            },
            timeoutMs,
        ), validatedIdentifier, options.version);
        const output = await regularFile(data.file.path);

        if (dirname(output.canonicalPath) !== destinationPath)
        {
            throw new InvalidProtocolResponseError("Photo export response points outside the requested destination directory.");
        }

        validateFileIdentity(data, output.canonicalPath, output.size);

        return {
            ...metadata(data),
            path: output.canonicalPath,
            representation: options.version,
        };
    }

    async #ensureHandshake(): Promise<void>
    {
        this.#handshake ??= this.#performHandshake();
        await this.#handshake;
    }

    async #invoke(
        operation: ProtocolOperation,
        parameters: Record<string, JsonValue>,
        timeoutMs: number,
    ): Promise<unknown>
    {
        await this.#ensureHandshake();
        return acceptResponse(await this.#run(operation, parameters, timeoutMs), operation);
    }

    async #performHandshake(): Promise<void>
    {
        validateHelperVersionData(acceptResponse(
            await this.#run("version", {}, this.#operationTimeoutMs),
            "version",
        ));
    }

    async #run(
        operation: ProtocolOperation,
        parameters: Record<string, JsonValue>,
        timeoutMs: number,
    ): Promise<ProtocolResponseEnvelope>
    {
        const options: HelperRunnerOptions = {
            helperPath: this.#helperPath,
            maxOutputBytes: this.#maxOutputBytes,
            timeoutMs: positiveInteger(timeoutMs, "timeoutMs"),
        };

        try
        {
            return (await runHelper(operation, parameters, options)).response;
        }
        catch (error)
        {
            if (error instanceof IncompatibleProtocolVersionError
                || error instanceof InvalidProtocolResponseError)
            {
                throw error;
            }

            if (error instanceof HelperNotFoundError)
            {
                throw new PhotoKitError(error.code, "The native PhotoKit helper was not found.", { cause: error, operation });
            }

            if (error instanceof HelperNotExecutableError)
            {
                throw new PhotoKitError(error.code, "The native PhotoKit helper is not executable.", { cause: error, operation });
            }

            if (error instanceof HelperTimeoutError)
            {
                throw new PhotoKitError(error.code, "The PhotoKit operation exceeded its configured deadline.", { cause: error, operation });
            }

            if (error instanceof HelperOutputLimitError)
            {
                throw new PhotoKitError(error.code, "The native PhotoKit helper response exceeded its safety limit.", { cause: error, operation });
            }

            if (error instanceof HelperPlatformUnsupportedError)
            {
                throw new PhotoKitError(error.code, error.message, {
                    cause: error,
                    details: {
                        architecture: error.architecture,
                        platform: error.platform,
                        supported: "darwin-arm64",
                    },
                    operation,
                });
            }

            if (error instanceof HelperCrashedError)
            {
                throw new PhotoKitError(error.code, "The native PhotoKit helper stopped before completing the operation.", { cause: error, operation });
            }

            throw error;
        }
    }
}
