import type { PhotoKitAsset, PhotoKitAuthorization, PhotoKitExport, PhotoKitThumbnail } from "@photokit-node/core";
import { helperProtocolVersion, maximumPhotoKitAssetLimit, PhotoKitClient, PhotoKitError } from "@photokit-node/core";
import type { CommanderError } from "commander";
import { Command, InvalidArgumentError, Option } from "commander";

import type { CliOutput } from "./output";
import { cliExitCodes, exitCodeForError, writeAssets, writeAuthorization, writeCliError, writeExportResult, writeThumbnailResult } from "./output";
import { placeThumbnail } from "./thumbnail-output";

export * from "@photokit-node/core";

/** PhotoKit client operations consumed by the thin CLI layer. */
export interface CliPhotoKitClient
{
    authorizationStatus: () => Promise<PhotoKitAuthorization>;
    exportPhoto: PhotoKitClient["exportPhoto"];
    getThumbnail: (identifier: string, options: Parameters<PhotoKitClient["getThumbnail"]>[1]) => Promise<PhotoKitThumbnail>;
    listAssets: (options?: Parameters<PhotoKitClient["listAssets"]>[0]) => Promise<PhotoKitAsset[]>;
    requestAuthorization: () => Promise<PhotoKitAuthorization>;
}

/** Injectable dependencies for programmatic CLI use and deterministic tests. */
export interface CliOptions
{
    client?: CliPhotoKitClient;
    stderr?: (text: string) => void;
    stdout?: (text: string) => void;
}

interface JsonOption
{
    json?: boolean;
}

interface ListOptions extends JsonOption
{
    limit: number;
    mediaType?: "image" | "video";
}

interface ThumbnailOptions extends JsonOption
{
    allowNetwork: boolean;
    contentMode: "aspect-fill" | "aspect-fit";
    format: "jpeg" | "png";
    maxHeight: number;
    maxWidth: number;
    output: string;
    overwrite: boolean;
}

interface ExportOptions extends JsonOption
{
    allowNetwork: boolean;
    outputDirectory: string;
    overwrite: boolean;
    version: "current" | "original";
}

class ReportedExit extends Error
{
    public readonly exitCode: number;

    public constructor(exitCode: number)
    {
        super("CLI result requires a non-zero exit code.");
        this.name = "ReportedExit";
        this.exitCode = exitCode;
    }
}

function positiveInteger(value: string): number
{
    const number = Number(value);
    if (!Number.isInteger(number) || number <= 0)
    {
        throw new InvalidArgumentError("must be a positive integer");
    }

    return number;
}

function assetLimit(value: string): number
{
    const limit = positiveInteger(value);
    if (limit > maximumPhotoKitAssetLimit)
    {
        throw new InvalidArgumentError(`must not exceed ${maximumPhotoKitAssetLimit}`);
    }

    return limit;
}

function defaultClient(): PhotoKitClient
{
    const helperPath = process.env.PHOTOKIT_NODE_HELPER_PATH;
    return new PhotoKitClient(helperPath ? { helperPath } : {});
}

function output(options: CliOptions): CliOutput
{
    return {
        stderr: options.stderr ?? ((text) => process.stderr.write(text)),
        stdout: options.stdout ?? ((text) => process.stdout.write(text)),
    };
}

function requiresAuthorization(status: PhotoKitAuthorization): void
{
    if (status.status !== "authorized" && status.status !== "limited")
    {
        throw new ReportedExit(cliExitCodes.noPermission);
    }
}

function addJsonOption(command: Command): Command
{
    return command.option("--json", "Print machine-readable JSON.");
}

function authorizationCommands(program: Command, client: CliPhotoKitClient, io: CliOutput): void
{
    const authorization = program.command("authorization").description("Inspect or request Photos authorization.").action(() => authorization.help());
    const status = addJsonOption(authorization.command("status").description("Print the current Photos authorization status."));
    status.action(async () =>
    {
        const value = await client.authorizationStatus();
        writeAuthorization(value, status.opts<JsonOption>().json ?? false, io);
        requiresAuthorization(value);
    });

    const request = addJsonOption(authorization.command("request").description("Request Photos authorization when not yet determined."));
    request.action(async () =>
    {
        const value = await client.requestAuthorization();
        writeAuthorization(value, request.opts<JsonOption>().json ?? false, io);
        requiresAuthorization(value);
    });
}

function listCommand(assets: Command, client: CliPhotoKitClient, io: CliOutput): void
{
    const list = addJsonOption(assets.command("list").description("List recent image and video metadata."))
        .addOption(new Option("--limit <count>", "Maximum assets to return.").argParser(assetLimit).default(20))
        .addOption(new Option("--media-type <type>", "Filter by image or video.").choices(["image", "video"]));

    list.action(async () =>
    {
        const options = list.opts<ListOptions>();
        const values = await client.listAssets({ limit: options.limit, mediaType: options.mediaType });
        writeAssets(values, options.json ?? false, io);
    });
}

function thumbnailCommand(assets: Command, client: CliPhotoKitClient, io: CliOutput): void
{
    const thumbnail = addJsonOption(assets.command("thumbnail <local-identifier>").description("Write one bounded asset thumbnail."))
        .requiredOption("--output <path>", "Thumbnail output path.")
        .addOption(new Option("--max-width <pixels>", "Maximum thumbnail width.").argParser(positiveInteger).makeOptionMandatory())
        .addOption(new Option("--max-height <pixels>", "Maximum thumbnail height.").argParser(positiveInteger).makeOptionMandatory())
        .addOption(new Option("--format <format>", "Thumbnail encoding.").choices(["jpeg", "png"]).default("jpeg"))
        .addOption(new Option("--content-mode <mode>", "Thumbnail crop behavior.").choices(["aspect-fit", "aspect-fill"]).default("aspect-fit"))
        .option("--allow-network", "Allow PhotoKit to retrieve iCloud content.", false)
        .option("--overwrite", "Replace an existing thumbnail output file.", false);

    thumbnail.action(async (identifier: string) =>
    {
        const options = thumbnail.opts<ThumbnailOptions>();
        const value = await client.getThumbnail(identifier, {
            allowNetworkAccess: options.allowNetwork,
            contentMode: options.contentMode,
            format: options.format,
            maxHeight: options.maxHeight,
            maxWidth: options.maxWidth,
        });
        const descriptor = await placeThumbnail(value, options.output, options.overwrite);
        writeThumbnailResult(descriptor, options.json ?? false, io);
    });
}

function exportCommand(assets: Command, client: CliPhotoKitClient, io: CliOutput): void
{
    const photoExport = addJsonOption(assets.command("export <local-identifier>").description("Export current or original still-photo content."))
        .requiredOption("--output-directory <path>", "Existing export destination directory.")
        .addOption(new Option("--version <version>", "Photo representation to export.").choices(["current", "original"]).makeOptionMandatory())
        .option("--allow-network", "Allow PhotoKit to retrieve iCloud content.", false)
        .option("--overwrite", "Replace an existing export with the selected filename.", false);

    photoExport.action(async (identifier: string) =>
    {
        const options = photoExport.opts<ExportOptions>();
        const value: PhotoKitExport = await client.exportPhoto(identifier, {
            allowNetworkAccess: options.allowNetwork,
            destinationDirectory: options.outputDirectory,
            overwrite: options.overwrite,
            version: options.version,
        });
        writeExportResult(value, options.json ?? false, io);
    });
}

/** Creates the Commander program for the photokit-node CLI. */
export function createProgram(options: CliOptions = {}): Command
{
    const client = options.client ?? defaultClient();
    const io = output(options);
    const program = new Command();

    program
        .name("photokit-node")
        .description("Access the macOS Photos library through a native PhotoKit helper.")
        .version("0.1.0")
        .enablePositionalOptions()
        .exitOverride()
        .configureOutput({ writeErr: io.stderr, writeOut: io.stdout })
        .showHelpAfterError()
        .action(() => program.help());

    program
        .command("protocol-version")
        .description("Print the native-helper protocol version.")
        .action(() => io.stdout(`${helperProtocolVersion}\n`));

    authorizationCommands(program, client, io);
    const assets = program.command("assets").description("List assets and access their image content.").action(() => assets.help());
    listCommand(assets, client, io);
    thumbnailCommand(assets, client, io);
    exportCommand(assets, client, io);

    return program;
}

function wantsJson(argv: readonly string[]): boolean
{
    return argv.includes("--json");
}

function isCommanderError(error: unknown): error is CommanderError
{
    return error instanceof Error
        && "code" in error
        && typeof error.code === "string"
        && error.code.startsWith("commander.")
        && "exitCode" in error
        && typeof error.exitCode === "number";
}

/** Parses arguments, writes any failure, and returns the stable process exit code. */
export async function runCli(argv: readonly string[], options: CliOptions = {}): Promise<number>
{
    const io = output(options);
    const json = wantsJson(argv);
    const program = createProgram({
        ...options,
        stderr: json ? () => undefined : io.stderr,
        stdout: io.stdout,
    });

    try
    {
        await program.parseAsync([...argv]);
        return 0;
    }
    catch (error)
    {
        if (error instanceof ReportedExit)
        {
            return error.exitCode;
        }

        if (isCommanderError(error))
        {
            if (error.exitCode !== 0 && json)
            {
                writeCliError(new PhotoKitError("invalid-request", error.message), true, io);
            }

            return error.exitCode === 0 ? 0 : cliExitCodes.usage;
        }

        writeCliError(error, json, io);
        return exitCodeForError(error);
    }
}
