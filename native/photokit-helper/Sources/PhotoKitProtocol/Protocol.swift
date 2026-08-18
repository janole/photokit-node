import Foundation
import Photos

public let helperProtocolVersion = 1

public struct HelperVersionResponse: Codable, Equatable, Sendable
{
    public let protocolVersion: Int

    public init(protocolVersion: Int = helperProtocolVersion)
    {
        self.protocolVersion = protocolVersion
    }
}

public enum PhotoLibraryAuthorizationStatus: String, Codable, Sendable
{
    case authorized
    case denied
    case limited
    case notDetermined = "not-determined"
    case restricted
}

public struct AuthorizationStatusResponse: Codable, Equatable, Sendable
{
    public let status: PhotoLibraryAuthorizationStatus

    public init(status: PhotoLibraryAuthorizationStatus)
    {
        self.status = status
    }
}

public func currentAuthorizationStatus() -> PhotoLibraryAuthorizationStatus
{
    switch PHPhotoLibrary.authorizationStatus(for: .readWrite)
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
