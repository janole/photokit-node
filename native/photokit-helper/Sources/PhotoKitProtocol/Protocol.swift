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
        return "Run authorization-request to ask for Photos access."
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
