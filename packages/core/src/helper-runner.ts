import type { ExecFileException } from "node:child_process";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";

import type { JsonValue, ProtocolOperation, ProtocolResponseEnvelope } from "./protocol";
import { decodeProtocolResponse, encodeProtocolRequest, IncompatibleProtocolVersionError } from "./protocol";

/** Default maximum runtime for one helper invocation. */
export const defaultHelperTimeoutMs = 10_000;

/** Default maximum captured bytes for each helper output stream. */
export const defaultHelperMaxOutputBytes = 1024 * 1024;

/** Private execution controls for the native helper runner. */
export interface HelperRunnerOptions
{
    helperPath?: string;
    maxOutputBytes?: number;
    timeoutMs?: number;
}

/** Decoded result from one native helper invocation. */
export interface HelperRunResult
{
    exitCode: number;
    response: ProtocolResponseEnvelope;
    stderr: string;
}

/** A bounded native helper output stream. */
export type HelperOutputStream = "stderr" | "stdout";

/** Raised when the configured native helper path does not exist. */
export class HelperNotFoundError extends Error
{
    public readonly code = "helper-not-found";
    public readonly helperPath: string;

    public constructor(helperPath: string, options?: ErrorOptions)
    {
        super(`PhotoKit helper was not found at ${helperPath}.`, options);
        this.name = "HelperNotFoundError";
        this.helperPath = helperPath;
    }
}

/** Raised when the configured native helper cannot be executed. */
export class HelperNotExecutableError extends Error
{
    public readonly code = "helper-not-executable";
    public readonly helperPath: string;

    public constructor(helperPath: string, options?: ErrorOptions)
    {
        super(`PhotoKit helper is not executable at ${helperPath}.`, options);
        this.name = "HelperNotExecutableError";
        this.helperPath = helperPath;
    }
}

/** Raised when a native helper invocation exceeds its deadline. */
export class HelperTimeoutError extends Error
{
    public readonly code = "helper-timeout";
    public readonly helperPath: string;
    public readonly timeoutMs: number;

    public constructor(helperPath: string, timeoutMs: number, options?: ErrorOptions)
    {
        super(`PhotoKit helper exceeded the ${timeoutMs} ms timeout.`, options);
        this.name = "HelperTimeoutError";
        this.helperPath = helperPath;
        this.timeoutMs = timeoutMs;
    }
}

/** Raised when a native helper output stream exceeds its capture limit. */
export class HelperOutputLimitError extends Error
{
    public readonly code = "helper-output-limit";
    public readonly helperPath: string;
    public readonly maxOutputBytes: number;
    public readonly stream: HelperOutputStream;

    public constructor(
        helperPath: string,
        stream: HelperOutputStream,
        maxOutputBytes: number,
        options?: ErrorOptions,
    )
    {
        super(`PhotoKit helper ${stream} exceeded the ${maxOutputBytes} byte limit.`, options);
        this.name = "HelperOutputLimitError";
        this.helperPath = helperPath;
        this.maxOutputBytes = maxOutputBytes;
        this.stream = stream;
    }
}

/** Raised when the packaged helper does not support the current runtime. */
export class HelperPlatformUnsupportedError extends Error
{
    public readonly architecture: NodeJS.Architecture;
    public readonly code = "helper-platform-unsupported";
    public readonly platform: NodeJS.Platform;

    public constructor(platform: NodeJS.Platform, architecture: NodeJS.Architecture)
    {
        super(`The packaged PhotoKit helper supports darwin-arm64, not ${platform}-${architecture}.`);
        this.name = "HelperPlatformUnsupportedError";
        this.architecture = architecture;
        this.platform = platform;
    }
}

/** Raised when the native helper exits without a valid protocol response. */
export class HelperCrashedError extends Error
{
    public readonly code = "helper-crashed";
    public readonly exitCode: number | null;
    public readonly helperPath: string;
    public readonly signal: NodeJS.Signals | null;
    public readonly stderr: string;

    public constructor(
        helperPath: string,
        exitCode: number | null,
        signal: NodeJS.Signals | null,
        stderr: string,
        options?: ErrorOptions,
    )
    {
        const termination = signal ? `signal ${signal}` : `exit code ${exitCode ?? "unknown"}`;
        super(`PhotoKit helper terminated with ${termination}.`, options);
        this.name = "HelperCrashedError";
        this.exitCode = exitCode;
        this.helperPath = helperPath;
        this.signal = signal;
        this.stderr = stderr;
    }
}

/** Resolves an override or the helper bundled next to the core package. */
export function resolveHelperPath(helperPath?: string): string
{
    return helperPath ?? fileURLToPath(new URL("../native/photokit-helper", import.meta.url));
}

/** Rejects a default packaged-helper invocation on unsupported operating systems or architectures. */
export function assertSupportedHelperRuntime(
    platform: NodeJS.Platform = process.platform,
    architecture: NodeJS.Architecture = process.arch,
): void
{
    if (platform !== "darwin" || architecture !== "arm64")
    {
        throw new HelperPlatformUnsupportedError(platform, architecture);
    }
}

function requirePositiveInteger(value: number, name: string): void
{
    if (!Number.isInteger(value) || value <= 0)
    {
        throw new RangeError(`${name} must be a positive integer.`);
    }
}

function outputLimitStream(error: ExecFileException): HelperOutputStream
{
    return error.message.includes("stderr") ? "stderr" : "stdout";
}

function executeHelper(
    helperPath: string,
    request: string,
    timeoutMs: number,
    maxOutputBytes: number,
): Promise<HelperRunResult>
{
    return new Promise((resolve, reject) =>
    {
        execFile(helperPath, [request], {
            encoding: "utf8",
            killSignal: "SIGKILL",
            maxBuffer: maxOutputBytes,
            shell: false,
            timeout: timeoutMs,
            windowsHide: true,
        }, (error, stdout, stderr) =>
        {
            if (!error)
            {
                try
                {
                    resolve({
                        exitCode: 0,
                        response: decodeProtocolResponse(stdout),
                        stderr,
                    });
                }
                catch (decodeError)
                {
                    reject(decodeError);
                }
                return;
            }

            if (error.code === "ENOENT")
            {
                reject(new HelperNotFoundError(helperPath, { cause: error }));
                return;
            }

            if (error.code === "EACCES")
            {
                reject(new HelperNotExecutableError(helperPath, { cause: error }));
                return;
            }

            if (error.code === "ERR_CHILD_PROCESS_STDIO_MAXBUFFER")
            {
                reject(new HelperOutputLimitError(
                    helperPath,
                    outputLimitStream(error),
                    maxOutputBytes,
                    { cause: error },
                ));
                return;
            }

            if (error.killed)
            {
                reject(new HelperTimeoutError(helperPath, timeoutMs, { cause: error }));
                return;
            }

            if (typeof error.code === "number")
            {
                try
                {
                    resolve({
                        exitCode: error.code,
                        response: decodeProtocolResponse(stdout),
                        stderr,
                    });
                }
                catch (decodeError)
                {
                    if (decodeError instanceof IncompatibleProtocolVersionError)
                    {
                        reject(decodeError);
                        return;
                    }

                    reject(new HelperCrashedError(
                        helperPath,
                        error.code,
                        error.signal ?? null,
                        stderr,
                        { cause: decodeError },
                    ));
                }
                return;
            }

            reject(new HelperCrashedError(
                helperPath,
                null,
                error.signal ?? null,
                stderr,
                { cause: error },
            ));
        });
    });
}

/** Runs one helper operation through a bounded shell-free child process. */
export async function runHelper(
    operation: ProtocolOperation,
    parameters: Record<string, JsonValue> = {},
    options: HelperRunnerOptions = {},
): Promise<HelperRunResult>
{
    const timeoutMs = options.timeoutMs ?? defaultHelperTimeoutMs;
    const maxOutputBytes = options.maxOutputBytes ?? defaultHelperMaxOutputBytes;
    requirePositiveInteger(timeoutMs, "timeoutMs");
    requirePositiveInteger(maxOutputBytes, "maxOutputBytes");

    if (options.helperPath === undefined)
    {
        assertSupportedHelperRuntime();
    }

    const helperPath = resolveHelperPath(options.helperPath);
    const request = encodeProtocolRequest(operation, parameters);
    return executeHelper(helperPath, request, timeoutMs, maxOutputBytes);
}
