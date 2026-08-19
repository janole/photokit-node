import AppKit
import Foundation
import Photos
import Testing
@testable import PhotoKitProtocol

private struct StubWriteError: Error {}

private func thumbnailParameters(
    format: ThumbnailFormat = .jpeg,
    contentMode: ThumbnailContentMode = .aspectFit,
    outputPath: String = "/tmp/photokit-node/thumbnail.jpg",
    overwrite: Bool = false
) throws -> GetThumbnailParameters
{
    try GetThumbnailParameters(parameters: [
        "assetIdentifier": .string("image-local-id"),
        "contentMode": .string(contentMode.rawValue),
        "format": .string(format.rawValue),
        "maxHeight": .number(200),
        "maxWidth": .number(200),
        "outputPath": .string(outputPath),
        "overwrite": .boolean(overwrite),
    ])
}

private func testImage(width: Int, height: Int) throws -> NSImage
{
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    return NSImage(cgImage: image, size: NSSize(width: width, height: height))
}

private func temporaryThumbnailDirectory() throws -> URL
{
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("photokit-thumbnail-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func thumbnailRequestOptionsAreFinalBoundedAndNetworkAware() throws
{
    var values: [String: JSONValue] = [
        "allowNetworkAccess": .boolean(true),
        "assetIdentifier": .string("image-local-id"),
        "maxHeight": .number(240),
        "maxWidth": .number(320),
        "outputPath": .string("/tmp/photokit-node/thumbnail.jpg"),
    ]
    let parameters = try GetThumbnailParameters(parameters: values)
    let options = makeThumbnailRequestOptions(parameters)

    #expect(options.deliveryMode == .highQualityFormat)
    #expect(options.resizeMode == .exact)
    #expect(options.version == .current)
    #expect(options.isNetworkAccessAllowed)
    #expect(!options.isSynchronous)
    #expect(thumbnailTargetSize(parameters) == CGSize(width: 320, height: 240))

    values["allowNetworkAccess"] = .boolean(false)
    #expect(!makeThumbnailRequestOptions(try GetThumbnailParameters(parameters: values)).isNetworkAccessAllowed)
}

@Test func thumbnailContentModesMapToPhotoKit()
{
    #expect(photoKitContentMode(.aspectFit) == .aspectFit)
    #expect(photoKitContentMode(.aspectFill) == .aspectFill)
}

@Test func thumbnailMediaSelectionAllowsImagesAndVideosOnly()
{
    #expect(isSupportedThumbnailMediaType(.image))
    #expect(isSupportedThumbnailMediaType(.video))
    #expect(!isSupportedThumbnailMediaType(.audio))
    #expect(!isSupportedThumbnailMediaType(.unknown))
    #expect(thumbnailMediaTypeName(.audio) == "audio")
}

@Test func degradedThumbnailCallbacksAreIgnored()
{
    let decision = thumbnailCallbackDecision(
        image: "preview",
        info: [PHImageResultIsDegradedKey: true],
        assetIdentifier: "image-local-id"
    )

    guard case .ignore = decision else
    {
        Issue.record("Expected a degraded callback to be ignored.")
        return
    }
}

@Test func finalThumbnailCallbacksSucceed()
{
    let decision = thumbnailCallbackDecision(
        image: "final",
        info: [PHImageResultIsDegradedKey: false],
        assetIdentifier: "image-local-id"
    )

    guard case .success(let image) = decision else
    {
        Issue.record("Expected a final callback to succeed.")
        return
    }

    #expect(image == "final")
}

@Test func cloudOnlyThumbnailCallbacksRequireOptInNetworkAccess()
{
    let decision: ThumbnailCallbackDecision<String> = thumbnailCallbackDecision(
        image: nil,
        info: [PHImageResultIsInCloudKey: true],
        assetIdentifier: "cloud-image-id"
    )

    guard case .failure(let error) = decision else
    {
        Issue.record("Expected a cloud-only callback to fail.")
        return
    }

    #expect(error == .networkAccessRequired(assetIdentifier: "cloud-image-id"))
}

@Test func PhotoKitNetworkErrorsUseTheStableNetworkFailure()
{
    let photoKitError = NSError(
        domain: PHPhotosErrorDomain,
        code: PHPhotosError.networkAccessRequired.rawValue
    )
    let decision: ThumbnailCallbackDecision<String> = thumbnailCallbackDecision(
        image: nil,
        info: [PHImageErrorKey: photoKitError],
        assetIdentifier: "cloud-image-id"
    )

    guard case .failure(let error) = decision else
    {
        Issue.record("Expected a PhotoKit network error to fail.")
        return
    }

    #expect(error == .networkAccessRequired(assetIdentifier: "cloud-image-id"))
}

@Test func cancelledThumbnailCallbacksUseTheStableCancellationFailure()
{
    let decision: ThumbnailCallbackDecision<String> = thumbnailCallbackDecision(
        image: nil,
        info: [PHImageCancelledKey: true],
        assetIdentifier: "image-local-id"
    )

    guard case .failure(let error) = decision else
    {
        Issue.record("Expected a cancelled callback to fail.")
        return
    }

    #expect(error == .cancelled(assetIdentifier: "image-local-id"))
}

@Test func cancelledThumbnailCallbacksTakePrecedenceOverDegradedResults()
{
    let decision: ThumbnailCallbackDecision<String> = thumbnailCallbackDecision(
        image: "preview",
        info: [
            PHImageCancelledKey: true,
            PHImageResultIsDegradedKey: true,
        ],
        assetIdentifier: "image-local-id"
    )

    guard case .failure(let error) = decision else
    {
        Issue.record("Expected a cancelled degraded callback to fail.")
        return
    }

    #expect(error == .cancelled(assetIdentifier: "image-local-id"))
}

@Test func thumbnailLayoutsAreBoundedAndPreserveContentMode()
{
    let fit = thumbnailPixelLayout(
        sourceWidth: 800,
        sourceHeight: 400,
        maxWidth: 200,
        maxHeight: 200,
        contentMode: .aspectFit
    )
    let fill = thumbnailPixelLayout(
        sourceWidth: 800,
        sourceHeight: 400,
        maxWidth: 200,
        maxHeight: 200,
        contentMode: .aspectFill
    )

    #expect(fit?.pixelWidth == 200)
    #expect(fit?.pixelHeight == 100)
    #expect(fit?.drawRect == CGRect(x: 0, y: 0, width: 200, height: 100))
    #expect(fill?.pixelWidth == 200)
    #expect(fill?.pixelHeight == 200)
    #expect(fill?.drawRect == CGRect(x: -100, y: 0, width: 400, height: 200))
}

@Test func thumbnailEncodingProducesBoundedJPEGAndPNGData() throws
{
    let source = try testImage(width: 800, height: 400)
    let jpeg = try encodeThumbnail(
        image: source,
        parameters: thumbnailParameters(format: .jpeg, contentMode: .aspectFit)
    )
    let png = try encodeThumbnail(
        image: source,
        parameters: thumbnailParameters(format: .png, contentMode: .aspectFill)
    )

    #expect(jpeg.pixelWidth == 200)
    #expect(jpeg.pixelHeight == 100)
    #expect(jpeg.data.starts(with: [0xFF, 0xD8]))
    #expect(png.pixelWidth == 200)
    #expect(png.pixelHeight == 200)
    #expect(png.data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
}

@Test func thumbnailWriterRefusesExistingOutputByDefault() throws
{
    let directory = try temporaryThumbnailDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("thumbnail.jpg")
    try Data("existing".utf8).write(to: output)

    #expect(throws: ThumbnailRenderingError.self)
    {
        try writeThumbnailData(Data("replacement".utf8), outputPath: output.path, overwrite: false)
    }
    #expect(try Data(contentsOf: output) == Data("existing".utf8))
}

@Test func thumbnailWriterAtomicallyReplacesOutputWhenEnabled() throws
{
    let directory = try temporaryThumbnailDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("thumbnail.jpg")
    let replacement = Data("replacement".utf8)
    try Data("existing".utf8).write(to: output)

    let byteLength = try writeThumbnailData(
        replacement,
        outputPath: output.path,
        overwrite: true
    )

    #expect(byteLength == replacement.count)
    #expect(try Data(contentsOf: output) == replacement)
}

@Test func thumbnailWriterRemovesPartialOutputAfterFailure() throws
{
    let directory = try temporaryThumbnailDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let output = directory.appendingPathComponent("thumbnail.jpg")

    #expect(throws: ThumbnailRenderingError.self)
    {
        try writeThumbnailData(
            Data("partial".utf8),
            outputPath: output.path,
            overwrite: false
        )
        { data, partialURL in
            try data.write(to: partialURL)
            throw StubWriteError()
        }
    }

    #expect(!FileManager.default.fileExists(atPath: output.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}
