import Foundation
import Photos

/// Protocol version shared by the native helper and Node client.
public let helperProtocolVersion = 1

/// Operations supported by the current helper protocol.
public enum ProtocolOperation: String, Codable, Sendable
{
    case authorizationRequest = "authorization-request"
    case authorizationStatus = "authorization-status"
    case version
}

/// Stable boundary-level errors returned by the helper.
public enum ProtocolErrorCode: String, Codable, Sendable
{
    case incompatibleProtocolVersion = "incompatible-protocol-version"
    case invalidRequest = "invalid-request"
    case nativeFailure = "native-failure"
    case unknownOperation = "unknown-operation"
}

/// A value representable in a JSON document.
public indirect enum JSONValue: Codable, Equatable, Sendable
{
    case array([JSONValue])
    case boolean(Bool)
    case null
    case number(Double)
    case object([String: JSONValue])
    case string(String)

    public init(from decoder: Decoder) throws
    {
        let container = try decoder.singleValueContainer()

        if container.decodeNil()
        {
            self = .null
        }
        else if let value = try? container.decode(Bool.self)
        {
            self = .boolean(value)
        }
        else if let value = try? container.decode(Double.self)
        {
            self = .number(value)
        }
        else if let value = try? container.decode(String.self)
        {
            self = .string(value)
        }
        else if let value = try? container.decode([JSONValue].self)
        {
            self = .array(value)
        }
        else
        {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.singleValueContainer()

        switch self
        {
        case .array(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .number(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

/// Request decoded from the helper's single JSON argument.
public struct ProtocolRequestEnvelope: Codable, Equatable, Sendable
{
    public let operation: String
    public let parameters: [String: JSONValue]
    public let protocolVersion: Int

    public init(
        protocolVersion: Int = helperProtocolVersion,
        operation: String,
        parameters: [String: JSONValue] = [:]
    )
    {
        self.operation = operation
        self.parameters = parameters
        self.protocolVersion = protocolVersion
    }
}

/// Indicates that a peer uses a different helper protocol version.
public struct IncompatibleProtocolVersionError: Error, Equatable, Sendable
{
    public let expected: Int
    public let received: Int

    public init(expected: Int = helperProtocolVersion, received: Int)
    {
        self.expected = expected
        self.received = received
    }
}

/// Rejects a protocol version that the current helper cannot serve.
public func assertCompatibleProtocolVersion(_ received: Int) throws
{
    guard received == helperProtocolVersion else
    {
        throw IncompatibleProtocolVersionError(received: received)
    }
}

/// Successful response encoded by the helper.
public struct ProtocolSuccessEnvelope<Data: Codable & Equatable & Sendable>: Codable, Equatable, Sendable
{
    public let data: Data
    public let operation: String
    public let protocolVersion: Int
    public let success: Bool

    public init(operation: ProtocolOperation, data: Data)
    {
        self.data = data
        self.operation = operation.rawValue
        self.protocolVersion = helperProtocolVersion
        self.success = true
    }
}

/// Structured failure information encoded by the helper.
public struct ProtocolError: Codable, Equatable, Sendable
{
    public let code: ProtocolErrorCode
    public let details: [String: JSONValue]?
    public let message: String

    public init(code: ProtocolErrorCode, message: String, details: [String: JSONValue]? = nil)
    {
        self.code = code
        self.details = details
        self.message = message
    }
}

/// Failed response encoded by the helper.
public struct ProtocolFailureEnvelope: Codable, Equatable, Sendable
{
    public let error: ProtocolError
    public let operation: String?
    public let protocolVersion: Int
    public let success: Bool

    public init(operation: String?, error: ProtocolError)
    {
        self.error = error
        self.operation = operation
        self.protocolVersion = helperProtocolVersion
        self.success = false
    }

    private enum CodingKeys: String, CodingKey
    {
        case error
        case operation
        case protocolVersion
        case success
    }

    public init(from decoder: Decoder) throws
    {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.error = try container.decode(ProtocolError.self, forKey: .error)
        self.operation = try container.decodeIfPresent(String.self, forKey: .operation)
        self.protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        self.success = try container.decode(Bool.self, forKey: .success)
    }

    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(error, forKey: .error)
        try container.encode(operation, forKey: .operation)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(success, forKey: .success)
    }
}

/// Data returned by the version operation.
public struct HelperVersionData: Codable, Equatable, Sendable
{
    public let protocolVersion: Int

    public init(protocolVersion: Int = helperProtocolVersion)
    {
        self.protocolVersion = protocolVersion
    }
}

/// Photo library authorization states returned by PhotoKit.
public enum PhotoLibraryAuthorizationStatus: String, Codable, Sendable
{
    case authorized
    case denied
    case limited
    case notDetermined = "not-determined"
    case restricted
}

/// Data returned by authorization operations.
public struct AuthorizationStatusData: Codable, Equatable, Sendable
{
    public let canRequest: Bool
    public let guidance: String
    public let status: PhotoLibraryAuthorizationStatus

    public init(status: PhotoLibraryAuthorizationStatus)
    {
        self.canRequest = status == .notDetermined
        self.guidance = authorizationGuidance(for: status)
        self.status = status
    }
}

func authorizationGuidance(for status: PhotoLibraryAuthorizationStatus) -> String
{
    switch status
    {
    case .authorized:
        return "Photo library access is available."
    case .denied:
        return "Enable Photos access in System Settings > Privacy & Security > Photos."
    case .limited:
        return "Photo library access is limited to the selected assets."
    case .notDetermined:
        return "Send an authorization-request operation to ask for Photos access."
    case .restricted:
        return "Photos access is restricted by a system policy and cannot be requested."
    }
}

func photoLibraryAuthorizationStatus(from status: PHAuthorizationStatus) -> PhotoLibraryAuthorizationStatus
{
    switch status
    {
    case .authorized:
        return .authorized
    case .denied:
        return .denied
    case .limited:
        return .limited
    case .notDetermined:
        return .notDetermined
    case .restricted:
        return .restricted
    @unknown default:
        return .restricted
    }
}

/// Returns the current read/write authorization without prompting.
public func currentAuthorizationStatus() -> PhotoLibraryAuthorizationStatus
{
    photoLibraryAuthorizationStatus(from: PHPhotoLibrary.authorizationStatus(for: .readWrite))
}

func authorizationStatusAfterRequest(
    currentStatus: PhotoLibraryAuthorizationStatus,
    request: () async -> PhotoLibraryAuthorizationStatus
) async -> PhotoLibraryAuthorizationStatus
{
    guard currentStatus == .notDetermined else
    {
        return currentStatus
    }

    return await request()
}

/// Requests read/write authorization only while the status is undetermined.
public func requestPhotoLibraryAuthorization() async -> PhotoLibraryAuthorizationStatus
{
    await authorizationStatusAfterRequest(currentStatus: currentAuthorizationStatus())
    {
        await withCheckedContinuation
        { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite)
            { status in
                continuation.resume(returning: photoLibraryAuthorizationStatus(from: status))
            }
        }
    }
}
