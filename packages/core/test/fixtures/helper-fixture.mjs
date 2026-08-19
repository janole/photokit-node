#!/usr/bin/env node

const requestText = process.argv[2];
const request = JSON.parse(requestText);
const mode = request.parameters.fixtureMode ?? "success";

function writeResponse(data)
{
    process.stdout.write(`${JSON.stringify({
        data,
        operation: request.operation,
        protocolVersion: 1,
        success: true,
    })}\n`);
}

switch (mode)
{
case "crash":
    process.stderr.write("fixture crash\n");
    process.exit(42);
    break;
case "delay":
    await new Promise((resolve) => setTimeout(resolve, request.parameters.delayMs));
    writeResponse({ delayed: true });
    break;
case "future-version":
    process.stdout.write(`${JSON.stringify({
        data: { protocolVersion: 2 },
        operation: request.operation,
        protocolVersion: 2,
        success: true,
    })}\n`);
    break;
case "malformed":
    process.stdout.write("not json\n");
    break;
case "protocol-failure":
    process.stdout.write(`${JSON.stringify({
        error: {
            code: "photo-library-access-unavailable",
            message: "fixture denied",
        },
        operation: request.operation,
        protocolVersion: 1,
        success: false,
    })}\n`);
    process.exit(77);
    break;
case "stderr-overflow":
    process.stderr.write("x".repeat(request.parameters.bytes));
    break;
case "stdout-overflow":
    process.stdout.write("x".repeat(request.parameters.bytes));
    break;
default:
    writeResponse({ receivedParameters: request.parameters });
}
