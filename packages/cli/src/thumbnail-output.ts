import { writeFile } from "node:fs/promises";
import { basename, resolve } from "node:path";

import type { PhotoKitThumbnail } from "@photokit-node/core";
import { PhotoKitError } from "@photokit-node/core";

import type { CliThumbnailDescriptor } from "./output";

function isFileExistsError(error: unknown): boolean
{
    return error instanceof Error && "code" in error && error.code === "EEXIST";
}

/** Places thumbnail bytes at the caller's output path with explicit overwrite behavior. */
export async function placeThumbnail(thumbnail: PhotoKitThumbnail, output: string, overwrite: boolean): Promise<CliThumbnailDescriptor>
{
    const outputPath = resolve(output);

    try
    {
        await writeFile(outputPath, thumbnail.bytes, { flag: overwrite ? "w" : "wx" });
    }
    catch (error)
    {
        if (isFileExistsError(error))
        {
            throw new PhotoKitError("output-file-exists", "The thumbnail output file already exists; pass --overwrite to replace it.", {
                cause: error,
                details: { path: outputPath },
                operation: "get-thumbnail",
            });
        }

        throw new PhotoKitError("output-write-failed", "The CLI could not write the thumbnail output file.", {
            cause: error,
            details: { path: outputPath },
            operation: "get-thumbnail",
        });
    }

    const { bytes: _bytes, ...metadata } = thumbnail;
    return {
        ...metadata,
        fileName: basename(outputPath),
        path: outputPath,
    };
}
