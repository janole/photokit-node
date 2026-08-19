import AppKit
import Foundation
@preconcurrency import Photos

/// Failures produced while resolving, rendering, or writing one thumbnail.
public enum ThumbnailRenderingError: Error, Equatable, Sendable
{
    case assetNotFound(assetIdentifier: String)
    case cancelled(assetIdentifier: String)
    case encodingFailed(assetIdentifier: String)
    case networkAccessRequired(assetIdentifier: String)
    case outputFileExists(path: String)
    case outputWriteFailed(path: String)
    case photoKitFailure(assetIdentifier: String)
    case unsupportedMedia(assetIdentifier: String, mediaType: String)
}

enum ThumbnailCallbackDecision<Image>
{
    case failure(ThumbnailRenderingError)
    case ignore
    case success(Image)
}

struct EncodedThumbnail: Equatable
{
    let data: Data
    let pixelHeight: Int
    let pixelWidth: Int
}

struct ThumbnailPixelLayout: Equatable
{
    let drawRect: CGRect
    let pixelHeight: Int
    let pixelWidth: Int
}

private struct SendableThumbnailImage: @unchecked Sendable
{
    let image: NSImage
}

private final class ThumbnailRequestCompletion: @unchecked Sendable
{
    private var continuation: CheckedContinuation<SendableThumbnailImage, any Error>?
    private let lock = NSLock()

    init(continuation: CheckedContinuation<SendableThumbnailImage, any Error>)
    {
        self.continuation = continuation
    }

    func receive(_ decision: ThumbnailCallbackDecision<NSImage>)
    {
        lock.lock()

        guard let continuation else
        {
            lock.unlock()
            return
        }

        switch decision
        {
        case .ignore:
            lock.unlock()
        case .failure(let error):
            self.continuation = nil
            lock.unlock()
            continuation.resume(throwing: error)
        case .success(let image):
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: SendableThumbnailImage(image: image))
        }
    }
}

func makeThumbnailRequestOptions(_ parameters: GetThumbnailParameters) -> PHImageRequestOptions
{
    let options = PHImageRequestOptions()
    options.deliveryMode = .highQualityFormat
    options.isNetworkAccessAllowed = parameters.allowNetworkAccess
    options.isSynchronous = false
    options.resizeMode = .exact
    options.version = .current
    return options
}

func photoKitContentMode(_ contentMode: ThumbnailContentMode) -> PHImageContentMode
{
    switch contentMode
    {
    case .aspectFill:
        return .aspectFill
    case .aspectFit:
        return .aspectFit
    }
}

func thumbnailTargetSize(_ parameters: GetThumbnailParameters) -> CGSize
{
    CGSize(width: parameters.maxWidth, height: parameters.maxHeight)
}

func isSupportedThumbnailMediaType(_ mediaType: PHAssetMediaType) -> Bool
{
    mediaType == .image || mediaType == .video
}

func thumbnailMediaTypeName(_ mediaType: PHAssetMediaType) -> String
{
    switch mediaType
    {
    case .audio:
        return "audio"
    case .image:
        return "image"
    case .unknown:
        return "unknown"
    case .video:
        return "video"
    @unknown default:
        return "unknown"
    }
}

func thumbnailCallbackDecision<Image>(
    image: Image?,
    info: [AnyHashable: Any]?,
    assetIdentifier: String
) -> ThumbnailCallbackDecision<Image>
{
    if (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true
    {
        return .failure(.cancelled(assetIdentifier: assetIdentifier))
    }

    if let error = info?[PHImageErrorKey] as? NSError
    {
        if error.domain == PHPhotosErrorDomain,
           error.code == PHPhotosError.networkAccessRequired.rawValue
        {
            return .failure(.networkAccessRequired(assetIdentifier: assetIdentifier))
        }

        if error.domain == PHPhotosErrorDomain,
           error.code == PHPhotosError.userCancelled.rawValue
        {
            return .failure(.cancelled(assetIdentifier: assetIdentifier))
        }

        return .failure(.photoKitFailure(assetIdentifier: assetIdentifier))
    }

    if (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true
    {
        return .ignore
    }

    if let image
    {
        return .success(image)
    }

    if (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue == true
    {
        return .failure(.networkAccessRequired(assetIdentifier: assetIdentifier))
    }

    return .failure(.photoKitFailure(assetIdentifier: assetIdentifier))
}

func thumbnailPixelLayout(
    sourceWidth: Int,
    sourceHeight: Int,
    maxWidth: Int,
    maxHeight: Int,
    contentMode: ThumbnailContentMode
) -> ThumbnailPixelLayout?
{
    guard sourceWidth > 0,
          sourceHeight > 0,
          maxWidth > 0,
          maxHeight > 0 else
    {
        return nil
    }

    let widthScale = Double(maxWidth) / Double(sourceWidth)
    let heightScale = Double(maxHeight) / Double(sourceHeight)

    switch contentMode
    {
    case .aspectFit:
        let scale = min(1, widthScale, heightScale)
        let pixelWidth = max(1, min(maxWidth, Int((Double(sourceWidth) * scale).rounded())))
        let pixelHeight = max(1, min(maxHeight, Int((Double(sourceHeight) * scale).rounded())))
        return ThumbnailPixelLayout(
            drawRect: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            pixelHeight: pixelHeight,
            pixelWidth: pixelWidth
        )
    case .aspectFill:
        let scale = max(widthScale, heightScale)
        let drawWidth = Double(sourceWidth) * scale
        let drawHeight = Double(sourceHeight) * scale
        return ThumbnailPixelLayout(
            drawRect: CGRect(
                x: (Double(maxWidth) - drawWidth) / 2,
                y: (Double(maxHeight) - drawHeight) / 2,
                width: drawWidth,
                height: drawHeight
            ),
            pixelHeight: maxHeight,
            pixelWidth: maxWidth
        )
    }
}

func encodeThumbnail(
    image: NSImage,
    parameters: GetThumbnailParameters
) throws -> EncodedThumbnail
{
    var proposedRect = CGRect(origin: .zero, size: image.size)

    guard let source = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
          let layout = thumbnailPixelLayout(
              sourceWidth: source.width,
              sourceHeight: source.height,
              maxWidth: parameters.maxWidth,
              maxHeight: parameters.maxHeight,
              contentMode: parameters.contentMode
          ),
          let bitmap = NSBitmapImageRep(
              bitmapDataPlanes: nil,
              pixelsWide: layout.pixelWidth,
              pixelsHigh: layout.pixelHeight,
              bitsPerSample: 8,
              samplesPerPixel: 4,
              hasAlpha: true,
              isPlanar: false,
              colorSpaceName: .deviceRGB,
              bitmapFormat: [],
              bytesPerRow: 0,
              bitsPerPixel: 0
          ),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else
    {
        throw ThumbnailRenderingError.encodingFailed(assetIdentifier: parameters.assetIdentifier)
    }

    bitmap.size = NSSize(width: layout.pixelWidth, height: layout.pixelHeight)
    let normalizedImage = NSImage(
        cgImage: source,
        size: NSSize(width: source.width, height: source.height)
    )

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    if parameters.format == .jpeg
    {
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: layout.pixelWidth, height: layout.pixelHeight).fill()
    }

    normalizedImage.draw(
        in: layout.drawRect,
        from: NSRect(x: 0, y: 0, width: source.width, height: source.height),
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    let data: Data?

    switch parameters.format
    {
    case .jpeg:
        data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    case .png:
        data = bitmap.representation(using: .png, properties: [:])
    }

    guard let data else
    {
        throw ThumbnailRenderingError.encodingFailed(assetIdentifier: parameters.assetIdentifier)
    }

    return EncodedThumbnail(
        data: data,
        pixelHeight: layout.pixelHeight,
        pixelWidth: layout.pixelWidth
    )
}

func writeThumbnailData(
    _ data: Data,
    outputPath: String,
    overwrite: Bool,
    fileManager: FileManager = .default,
    writePartial: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }
) throws -> Int
{
    let outputURL = URL(fileURLWithPath: outputPath)

    do
    {
        return try writeAssetContentData(
            data,
            outputURL: outputURL,
            overwrite: overwrite,
            fileManager: fileManager,
            writePartial: writePartial
        )
    }
    catch AssetFileOutputError.fileExists(let path)
    {
        throw ThumbnailRenderingError.outputFileExists(path: path)
    }
    catch AssetFileOutputError.writeFailed(let path)
    {
        throw ThumbnailRenderingError.outputWriteFailed(path: path)
    }
}

private func fetchThumbnailAsset(assetIdentifier: String) throws -> PHAsset
{
    let result = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)

    guard let asset = result.firstObject else
    {
        throw ThumbnailRenderingError.assetNotFound(assetIdentifier: assetIdentifier)
    }

    guard isSupportedThumbnailMediaType(asset.mediaType) else
    {
        throw ThumbnailRenderingError.unsupportedMedia(
            assetIdentifier: assetIdentifier,
            mediaType: thumbnailMediaTypeName(asset.mediaType)
        )
    }

    return asset
}

private func requestThumbnailImage(
    asset: PHAsset,
    parameters: GetThumbnailParameters
) async throws -> NSImage
{
    let result: SendableThumbnailImage = try await withCheckedThrowingContinuation
    { continuation in
        let completion = ThumbnailRequestCompletion(continuation: continuation)
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: thumbnailTargetSize(parameters),
            contentMode: photoKitContentMode(parameters.contentMode),
            options: makeThumbnailRequestOptions(parameters)
        )
        { image, info in
            completion.receive(thumbnailCallbackDecision(
                image: image,
                info: info,
                assetIdentifier: parameters.assetIdentifier
            ))
        }
    }

    return result.image
}

private func thumbnailContentType(_ format: ThumbnailFormat) -> String
{
    switch format
    {
    case .jpeg:
        return "image/jpeg"
    case .png:
        return "image/png"
    }
}

private func thumbnailUniformTypeIdentifier(_ format: ThumbnailFormat) -> String
{
    switch format
    {
    case .jpeg:
        return "public.jpeg"
    case .png:
        return "public.png"
    }
}

/// Resolves, renders, encodes, and writes one PhotoKit thumbnail.
public func renderThumbnail(parameters: GetThumbnailParameters) async throws -> AssetContentData
{
    let asset = try fetchThumbnailAsset(assetIdentifier: parameters.assetIdentifier)
    let image = try await requestThumbnailImage(asset: asset, parameters: parameters)
    let encoded = try encodeThumbnail(image: image, parameters: parameters)
    let byteLength = try writeThumbnailData(
        encoded.data,
        outputPath: parameters.outputPath,
        overwrite: parameters.overwrite
    )
    let outputURL = URL(fileURLWithPath: parameters.outputPath)

    return AssetContentData(
        assetIdentifier: parameters.assetIdentifier,
        file: AssetContentFileDescriptor(
            byteLength: byteLength,
            contentType: thumbnailContentType(parameters.format),
            fileName: outputURL.lastPathComponent,
            path: outputURL.path,
            pixelHeight: encoded.pixelHeight,
            pixelWidth: encoded.pixelWidth,
            representation: .thumbnail,
            uniformTypeIdentifier: thumbnailUniformTypeIdentifier(parameters.format)
        )
    )
}
