import Foundation
import ImageIO
@preconcurrency import Photos
import UniformTypeIdentifiers

/// Failures produced while resolving, reading, or writing one still-photo export.
public enum PhotoExportError: Error, Equatable, Sendable
{
    case assetNotFound(assetIdentifier: String)
    case cancelled(assetIdentifier: String)
    case networkAccessRequired(assetIdentifier: String)
    case outputFileExists(path: String)
    case outputWriteFailed(path: String)
    case photoKitFailure(assetIdentifier: String)
    case unsupportedMedia(assetIdentifier: String, mediaType: String)
}

struct ExportedPhotoBytes: Equatable, Sendable
{
    let data: Data
    let uniformTypeIdentifier: String
}

enum CurrentPhotoCallbackDecision
{
    case failure(PhotoExportError)
    case success(ExportedPhotoBytes)
}

private final class CurrentPhotoRequestCompletion: @unchecked Sendable
{
    private var continuation: CheckedContinuation<ExportedPhotoBytes, any Error>?
    private let lock = NSLock()

    init(continuation: CheckedContinuation<ExportedPhotoBytes, any Error>)
    {
        self.continuation = continuation
    }

    func receive(_ decision: CurrentPhotoCallbackDecision)
    {
        lock.lock()

        guard let continuation else
        {
            lock.unlock()
            return
        }

        self.continuation = nil
        lock.unlock()

        switch decision
        {
        case .failure(let error):
            continuation.resume(throwing: error)
        case .success(let result):
            continuation.resume(returning: result)
        }
    }
}

private final class OriginalPhotoRequestCompletion: @unchecked Sendable
{
    private var continuation: CheckedContinuation<Data, any Error>?
    private var data = Data()
    private let lock = NSLock()

    init(continuation: CheckedContinuation<Data, any Error>)
    {
        self.continuation = continuation
    }

    func receive(_ chunk: Data)
    {
        lock.lock()

        if continuation != nil
        {
            data.append(chunk)
        }

        lock.unlock()
    }

    func finish(error: NSError?, assetIdentifier: String)
    {
        lock.lock()

        guard let continuation else
        {
            lock.unlock()
            return
        }

        self.continuation = nil
        let result = data
        data.removeAll(keepingCapacity: false)
        lock.unlock()

        if let error
        {
            continuation.resume(throwing: photoExportError(
                error: error,
                assetIdentifier: assetIdentifier
            ))
        }
        else if result.isEmpty
        {
            continuation.resume(throwing: PhotoExportError.photoKitFailure(
                assetIdentifier: assetIdentifier
            ))
        }
        else
        {
            continuation.resume(returning: result)
        }
    }
}

func makeCurrentPhotoRequestOptions(_ parameters: ExportPhotoParameters) -> PHImageRequestOptions
{
    let options = PHImageRequestOptions()
    options.isNetworkAccessAllowed = parameters.allowNetworkAccess
    options.isSynchronous = false
    options.version = .current
    return options
}

func makeOriginalPhotoRequestOptions(_ parameters: ExportPhotoParameters) -> PHAssetResourceRequestOptions
{
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = parameters.allowNetworkAccess
    return options
}

func isSupportedPhotoExportMediaType(_ mediaType: PHAssetMediaType) -> Bool
{
    mediaType == .image
}

func originalPhotoResourceIndex(resourceTypes: [PHAssetResourceType]) -> Int?
{
    resourceTypes.firstIndex(of: .photo)
}

func photoExportError(error: NSError, assetIdentifier: String) -> PhotoExportError
{
    if error.domain == PHPhotosErrorDomain,
       error.code == PHPhotosError.networkAccessRequired.rawValue
    {
        return .networkAccessRequired(assetIdentifier: assetIdentifier)
    }

    if error.domain == PHPhotosErrorDomain,
       error.code == PHPhotosError.userCancelled.rawValue
    {
        return .cancelled(assetIdentifier: assetIdentifier)
    }

    return .photoKitFailure(assetIdentifier: assetIdentifier)
}

func currentPhotoCallbackDecision(
    data: Data?,
    uniformTypeIdentifier: String?,
    info: [AnyHashable: Any]?,
    assetIdentifier: String
) -> CurrentPhotoCallbackDecision
{
    if (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true
    {
        return .failure(.cancelled(assetIdentifier: assetIdentifier))
    }

    if let error = info?[PHImageErrorKey] as? NSError
    {
        return .failure(photoExportError(error: error, assetIdentifier: assetIdentifier))
    }

    if let data,
       !data.isEmpty,
       let uniformTypeIdentifier,
       !uniformTypeIdentifier.isEmpty
    {
        return .success(ExportedPhotoBytes(
            data: data,
            uniformTypeIdentifier: uniformTypeIdentifier
        ))
    }

    if (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue == true
    {
        return .failure(.networkAccessRequired(assetIdentifier: assetIdentifier))
    }

    return .failure(.photoKitFailure(assetIdentifier: assetIdentifier))
}

func photoExportContentType(uniformTypeIdentifier: String) -> String
{
    UTType(uniformTypeIdentifier)?.preferredMIMEType ?? "application/octet-stream"
}

func photoExportFileName(
    originalFilename: String,
    uniformTypeIdentifier: String,
    version: PhotoExportVersion
) -> String
{
    let leafName = (originalFilename as NSString).lastPathComponent
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let validLeafName = leafName.isEmpty || leafName == "." || leafName == ".."
        ? "photo"
        : leafName
    let originalExtension = (validLeafName as NSString).pathExtension
    let candidateBaseName = (validLeafName as NSString).deletingPathExtension
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let baseName = candidateBaseName.isEmpty ? "photo" : candidateBaseName
    let fileExtension = UTType(uniformTypeIdentifier)?.preferredFilenameExtension
        ?? (originalExtension.isEmpty ? "bin" : originalExtension)

    switch version
    {
    case .current:
        return "\(baseName)-current.\(fileExtension)"
    case .original:
        if !originalExtension.isEmpty, !candidateBaseName.isEmpty
        {
            return validLeafName
        }

        return "\(baseName).\(fileExtension)"
    }
}

func photoExportRepresentation(_ version: PhotoExportVersion) -> AssetContentRepresentation
{
    switch version
    {
    case .current:
        return .current
    case .original:
        return .original
    }
}

func imagePixelDimensions(_ data: Data) -> (pixelWidth: Int, pixelHeight: Int)?
{
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
          width.intValue > 0,
          height.intValue > 0 else
    {
        return nil
    }

    return (pixelWidth: width.intValue, pixelHeight: height.intValue)
}

func availablePixelDimension(_ value: Int) -> Int?
{
    value > 0 ? value : nil
}

func writePhotoExportData(
    _ data: Data,
    destinationDirectory: String,
    fileName: String,
    overwrite: Bool,
    fileManager: FileManager = .default,
    writePartial: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }
) throws -> (byteLength: Int, outputURL: URL)
{
    let directoryURL = URL(fileURLWithPath: destinationDirectory, isDirectory: true)
        .standardizedFileURL
    let outputURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)

    do
    {
        let byteLength = try writeAssetContentData(
            data,
            outputURL: outputURL,
            overwrite: overwrite,
            fileManager: fileManager,
            writePartial: writePartial
        )
        return (byteLength: byteLength, outputURL: outputURL)
    }
    catch AssetFileOutputError.fileExists(let path)
    {
        throw PhotoExportError.outputFileExists(path: path)
    }
    catch AssetFileOutputError.writeFailed(let path)
    {
        throw PhotoExportError.outputWriteFailed(path: path)
    }
}

private func fetchPhotoExportAsset(assetIdentifier: String) throws -> PHAsset
{
    let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)

    guard let asset = result.firstObject else
    {
        throw PhotoExportError.assetNotFound(assetIdentifier: assetIdentifier)
    }

    guard isSupportedPhotoExportMediaType(asset.mediaType) else
    {
        throw PhotoExportError.unsupportedMedia(
            assetIdentifier: assetIdentifier,
            mediaType: thumbnailMediaTypeName(asset.mediaType)
        )
    }

    return asset
}

private func primaryPhotoResource(asset: PHAsset) -> PHAssetResource?
{
    let resources = PHAssetResource.assetResources(for: asset)
    let resourceTypes = resources.map(\.type)

    return originalPhotoResourceIndex(resourceTypes: resourceTypes).map { resources[$0] }
}

private func requestCurrentPhotoData(
    asset: PHAsset,
    parameters: ExportPhotoParameters
) async throws -> ExportedPhotoBytes
{
    try await withCheckedThrowingContinuation
    { continuation in
        let completion = CurrentPhotoRequestCompletion(continuation: continuation)
        PHImageManager.default().requestImageDataAndOrientation(
            for: asset,
            options: makeCurrentPhotoRequestOptions(parameters)
        )
        { data, uniformTypeIdentifier, _, info in
            completion.receive(currentPhotoCallbackDecision(
                data: data,
                uniformTypeIdentifier: uniformTypeIdentifier,
                info: info,
                assetIdentifier: parameters.assetIdentifier
            ))
        }
    }
}

private func requestOriginalPhotoData(
    resource: PHAssetResource,
    parameters: ExportPhotoParameters
) async throws -> Data
{
    try await withCheckedThrowingContinuation
    { continuation in
        let completion = OriginalPhotoRequestCompletion(continuation: continuation)
        PHAssetResourceManager.default().requestData(
            for: resource,
            options: makeOriginalPhotoRequestOptions(parameters)
        )
        { chunk in
            completion.receive(chunk)
        }
        completionHandler:
        { error in
            completion.finish(
                error: error as NSError?,
                assetIdentifier: parameters.assetIdentifier
            )
        }
    }
}

private func photoExportDescriptor(
    asset: PHAsset,
    bytes: ExportedPhotoBytes,
    originalFilename: String,
    parameters: ExportPhotoParameters
) throws -> AssetContentData
{
    let fileName = photoExportFileName(
        originalFilename: originalFilename,
        uniformTypeIdentifier: bytes.uniformTypeIdentifier,
        version: parameters.version
    )
    let output = try writePhotoExportData(
        bytes.data,
        destinationDirectory: parameters.destinationDirectory,
        fileName: fileName,
        overwrite: parameters.overwrite
    )
    let dimensions = imagePixelDimensions(bytes.data)

    return AssetContentData(
        assetIdentifier: parameters.assetIdentifier,
        file: AssetContentFileDescriptor(
            byteLength: output.byteLength,
            contentType: photoExportContentType(
                uniformTypeIdentifier: bytes.uniformTypeIdentifier
            ),
            fileName: fileName,
            path: output.outputURL.path,
            pixelHeight: dimensions?.pixelHeight ?? availablePixelDimension(asset.pixelHeight),
            pixelWidth: dimensions?.pixelWidth ?? availablePixelDimension(asset.pixelWidth),
            representation: photoExportRepresentation(parameters.version),
            uniformTypeIdentifier: bytes.uniformTypeIdentifier
        )
    )
}

/// Resolves and writes the requested current or original still-photo representation.
public func exportPhoto(parameters: ExportPhotoParameters) async throws -> AssetContentData
{
    let asset = try fetchPhotoExportAsset(assetIdentifier: parameters.assetIdentifier)

    switch parameters.version
    {
    case .current:
        let bytes = try await requestCurrentPhotoData(asset: asset, parameters: parameters)
        return try photoExportDescriptor(
            asset: asset,
            bytes: bytes,
            originalFilename: primaryPhotoResource(asset: asset)?.originalFilename ?? "photo",
            parameters: parameters
        )
    case .original:
        guard let resource = primaryPhotoResource(asset: asset) else
        {
            throw PhotoExportError.photoKitFailure(assetIdentifier: parameters.assetIdentifier)
        }

        let data = try await requestOriginalPhotoData(resource: resource, parameters: parameters)
        return try photoExportDescriptor(
            asset: asset,
            bytes: ExportedPhotoBytes(
                data: data,
                uniformTypeIdentifier: resource.uniformTypeIdentifier
            ),
            originalFilename: resource.originalFilename,
            parameters: parameters
        )
    }
}
