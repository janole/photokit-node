import Foundation
import PhotoKitProtocol

private let exitSoftware: Int32 = 70
private let exitUsage: Int32 = 64
private let exitVersionMismatch: Int32 = 78
private let exitNoPermission: Int32 = 77
private let exitNoInput: Int32 = 66
private let exitUnavailable: Int32 = 69
private let exitCannotCreate: Int32 = 73
private let exitTemporaryFailure: Int32 = 75

func writeJSON<T: Encodable>(_ value: T) throws
{
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
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

func requirePhotoLibraryAccess(operation: String)
{
    let status = currentAuthorizationStatus()

    guard isPhotoLibraryReadAccessAvailable(status) else
    {
        let authorization = AuthorizationStatusData(status: status)
        fail(
            operation: operation,
            code: .photoLibraryAccessUnavailable,
            message: authorization.guidance,
            details: ["status": .string(status.rawValue)],
            exitCode: exitNoPermission
        )
    }
}

func failThumbnail(operation: String, error: ThumbnailRenderingError) -> Never
{
    switch error
    {
    case .assetNotFound(let assetIdentifier):
        fail(
            operation: operation,
            code: .assetNotFound,
            message: "The requested asset is not visible or available to this photo library.",
            details: ["assetIdentifier": .string(assetIdentifier)],
            exitCode: exitNoInput
        )
    case .cancelled(let assetIdentifier):
        fail(
            operation: operation,
            code: .operationCancelled,
            message: "The asset-content operation was cancelled.",
            details: ["assetIdentifier": .string(assetIdentifier)],
            exitCode: exitTemporaryFailure
        )
    case .encodingFailed:
        fail(
            operation: operation,
            code: .nativeFailure,
            message: "The helper could not encode the requested thumbnail.",
            exitCode: exitSoftware
        )
    case .networkAccessRequired(let assetIdentifier):
        fail(
            operation: operation,
            code: .networkAccessRequired,
            message: "Asset content is not available locally; retry with allowNetworkAccess enabled.",
            details: ["assetIdentifier": .string(assetIdentifier)],
            exitCode: exitUnavailable
        )
    case .outputFileExists(let path):
        fail(
            operation: operation,
            code: .outputFileExists,
            message: "The output file already exists; enable overwrite to replace it.",
            details: ["path": .string(path)],
            exitCode: exitCannotCreate
        )
    case .outputWriteFailed(let path):
        fail(
            operation: operation,
            code: .outputWriteFailed,
            message: "The helper could not write the requested output file.",
            details: ["path": .string(path)],
            exitCode: exitCannotCreate
        )
    case .photoKitFailure:
        fail(
            operation: operation,
            code: .nativeFailure,
            message: "PhotoKit could not produce the requested thumbnail.",
            exitCode: exitSoftware
        )
    case .unsupportedMedia(let assetIdentifier, let mediaType):
        fail(
            operation: operation,
            code: .unsupportedMedia,
            message: "get-thumbnail supports image and video assets only.",
            details: [
                "assetIdentifier": .string(assetIdentifier),
                "mediaType": .string(mediaType),
            ],
            exitCode: exitNoInput
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
            case ProtocolOperation.getThumbnail.rawValue:
                let parameters: GetThumbnailParameters

                do
                {
                    parameters = try GetThumbnailParameters(parameters: request.parameters)
                }
                catch let error as InvalidAssetContentParametersError
                {
                    fail(
                        operation: request.operation,
                        code: .invalidRequest,
                        message: error.message,
                        exitCode: exitUsage
                    )
                }

                requirePhotoLibraryAccess(operation: request.operation)

                do
                {
                    let data = try await renderThumbnail(parameters: parameters)
                    try writeJSON(ProtocolSuccessEnvelope(operation: .getThumbnail, data: data))
                }
                catch let error as ThumbnailRenderingError
                {
                    failThumbnail(operation: request.operation, error: error)
                }
            case ProtocolOperation.listAssets.rawValue:
                let parameters: ListAssetsParameters

                do
                {
                    parameters = try ListAssetsParameters(parameters: request.parameters)
                }
                catch let error as InvalidListAssetsParametersError
                {
                    fail(
                        operation: request.operation,
                        code: .invalidRequest,
                        message: error.message,
                        exitCode: exitUsage
                    )
                }

                requirePhotoLibraryAccess(operation: request.operation)
                let data = listRecentAssets(parameters: parameters)
                try writeJSON(ProtocolSuccessEnvelope(operation: .listAssets, data: data))
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
