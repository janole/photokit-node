import Foundation
import PhotoKitProtocol

private let exitSoftware: Int32 = 70
private let exitUsage: Int32 = 64
private let exitVersionMismatch: Int32 = 78

func writeJSON<T: Encodable>(_ value: T) throws
{
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

func fail(
    operation: String?,
    code: ProtocolErrorCode,
    message: String,
    details: [String: JSONValue]? = nil,
    exitCode: Int32
) -> Never
{
    let response = ProtocolFailureEnvelope(
        operation: operation,
        error: ProtocolError(code: code, message: message, details: details)
    )

    do
    {
        try writeJSON(response)
    }
    catch
    {
        FileHandle.standardError.write(Data("photokit-helper: could not encode protocol error: \(error)\n".utf8))
    }

    exit(exitCode)
}

func requireEmptyParameters(_ request: ProtocolRequestEnvelope)
{
    guard request.parameters.isEmpty else
    {
        fail(
            operation: request.operation,
            code: .invalidRequest,
            message: "Operation \"\(request.operation)\" does not accept parameters.",
            exitCode: exitUsage
        )
    }
}

@main
struct PhotoKitHelper
{
    static func main() async
    {
        let arguments = Array(CommandLine.arguments.dropFirst())

        guard arguments.count == 1 else
        {
            fail(
                operation: nil,
                code: .invalidRequest,
                message: "Expected exactly one JSON request argument.",
                exitCode: exitUsage
            )
        }

        let request: ProtocolRequestEnvelope

        do
        {
            request = try JSONDecoder().decode(ProtocolRequestEnvelope.self, from: Data(arguments[0].utf8))
        }
        catch
        {
            fail(
                operation: nil,
                code: .invalidRequest,
                message: "Request is not a valid protocol envelope.",
                exitCode: exitUsage
            )
        }

        do
        {
            try assertCompatibleProtocolVersion(request.protocolVersion)
        }
        catch let error as IncompatibleProtocolVersionError
        {
            fail(
                operation: request.operation,
                code: .incompatibleProtocolVersion,
                message: "Protocol version \(error.received) is incompatible with version \(error.expected).",
                details: [
                    "expected": .number(Double(error.expected)),
                    "received": .number(Double(error.received)),
                ],
                exitCode: exitVersionMismatch
            )
        }
        catch
        {
            fail(
                operation: request.operation,
                code: .nativeFailure,
                message: "The native helper could not validate the protocol version.",
                exitCode: exitSoftware
            )
        }

        do
        {
            switch request.operation
            {
            case ProtocolOperation.version.rawValue:
                requireEmptyParameters(request)
                try writeJSON(ProtocolSuccessEnvelope(operation: .version, data: HelperVersionData()))
            case ProtocolOperation.authorizationStatus.rawValue:
                requireEmptyParameters(request)
                let data = AuthorizationStatusData(status: currentAuthorizationStatus())
                try writeJSON(ProtocolSuccessEnvelope(operation: .authorizationStatus, data: data))
            case ProtocolOperation.authorizationRequest.rawValue:
                requireEmptyParameters(request)
                let status = await requestPhotoLibraryAuthorization()
                try writeJSON(ProtocolSuccessEnvelope(
                    operation: .authorizationRequest,
                    data: AuthorizationStatusData(status: status)
                ))
            default:
                fail(
                    operation: request.operation,
                    code: .unknownOperation,
                    message: "Unknown operation \"\(request.operation)\".",
                    exitCode: exitUsage
                )
            }
        }
        catch
        {
            fail(
                operation: request.operation,
                code: .nativeFailure,
                message: "The native helper could not encode its response.",
                exitCode: exitSoftware
            )
        }
    }
}
