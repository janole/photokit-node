import { helperProtocolVersion } from "@photokit-node/core";
import { Command } from "commander";

/** Creates the photokit-node command-line program. */
export function createProgram(): Command
{
    const program = new Command();

    program
        .name("photokit-node")
        .description("Access the macOS Photos library through a native PhotoKit helper.")
        .version("0.1.0");

    program
        .command("protocol-version")
        .description("Print the native-helper protocol version.")
        .action(() =>
        {
            process.stdout.write(`${helperProtocolVersion}\n`);
        });

    return program;
}

/** Parses command-line arguments and runs the selected command. */
export async function runCli(argv: readonly string[]): Promise<void>
{
    await createProgram().parseAsync(argv);
}
