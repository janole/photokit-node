import AppKit
import Foundation
import Photos
import Testing
import UniformTypeIdentifiers
@testable import PhotoKitProtocol

private struct StubPhotoExportWriteError: Error {}

private func photoExportParameters(
    allowNetworkAccess: Bool = false,
    destinationDirectory: String = "/tmp/photokit-node/exports",
    overwrite: Bool = false,
    version: PhotoExportVersion = .original
) throws -> ExportPhotoParameters
{
    try ExportPhotoParameters(parameters: [
        "allowNetworkAccess": .boolean(allowNetworkAccess),
        "assetIdentifier": .string("image-local-id"),
        "destinationDirectory": .string(destinationDirectory),
        "overwrite": .boolean(overwrite),
        "version": .string(version.rawValue),
    ])
}

private func temporaryPhotoExportDirectory() throws -> URL
{
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("photokit-photo-export-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func testPNGData(width: Int, height: Int) throws -> Data
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
    context.setFillColor(red: 0.1, green: 0.5, blue: 0.3, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let bitmap = NSBitmapImageRep(cgImage: image)
    return try #require(bitmap.representation(using: .png, properties: [:]))
}

@Test func photoExportOptionsAreVersionedAndNetworkAware() throws
{
    let parameters = try photoExportParameters(allowNetworkAccess: true, version: .current)
    let currentOptions = makeCurrentPhotoRequestOptions(parameters)
    let originalOptions = makeOriginalPhotoRequestOptions(parameters)

    #expect(currentOptions.version == .current)
    #expect(currentOptions.isNetworkAccessAllowed)
    #expect(!currentOptions.isSynchronous)
    #expect(originalOptions.isNetworkAccessAllowed)

    let localOnly = try photoExportParameters()
    #expect(!makeCurrentPhotoRequestOptions(localOnly).isNetworkAccessAllowed)
    #expect(!makeOriginalPhotoRequestOptions(localOnly).isNetworkAccessAllowed)
}

@Test func photoExportSupportsStillImagesOnly()
{
    #expect(isSupportedPhotoExportMediaType(.image))
    #expect(!isSupportedPhotoExportMediaType(.video))
    #expect(!isSupportedPhotoExportMediaType(.audio))
    #expect(!isSupportedPhotoExportMediaType(.unknown))
}

@Test func originalPhotoSelectionUsesThePrimaryStillResource()
{
    let resourceTypes: [PHAssetResourceType] = [
        .fullSizePhoto,
        .pairedVideo,
        .photo,
        .adjustmentData,
    ]

    #expect(originalPhotoResourceIndex(resourceTypes: resourceTypes) == 2)
    #expect(originalPhotoResourceIndex(resourceTypes: [.pairedVideo, .fullSizePhoto]) == nil)
}

@Test func currentPhotoCallbacksReturnDataAndType()
{
    let expected = ExportedPhotoBytes(
        data: Data("photo".utf8),
        uniformTypeIdentifier: "public.jpeg"
    )
    let decision = currentPhotoCallbackDecision(
        data: expected.data,
        uniformTypeIdentifier: expected.uniformTypeIdentifier,
        info: nil,
        assetIdentifier: "image-local-id"
    )

    guard case .success(let result) = decision else
    {
        Issue.record("Expected current photo data to succeed.")
        return
    }

    #expect(result == expected)
}

@Test func currentPhotoCloudCallbacksRequireOptInNetworkAccess()
{
    let decision = currentPhotoCallbackDecision(
        data: nil,
        uniformTypeIdentifier: nil,
        info: [PHImageResultIsInCloudKey: true],
        assetIdentifier: "cloud-image-id"
    )

    guard case .failure(let error) = decision else
    {
        Issue.record("Expected cloud-only current photo data to fail.")
        return
    }

    #expect(error == .networkAccessRequired(assetIdentifier: "cloud-image-id"))
}

@Test func currentPhotoCancellationTakesPrecedenceOverData()
{
    let decision = currentPhotoCallbackDecision(
        data: Data("photo".utf8),
        uniformTypeIdentifier: "public.jpeg",
        info: [PHImageCancelledKey: true],
        assetIdentifier: "image-local-id"
    )

    guard case .failure(let error) = decision else
    {
        Issue.record("Expected cancelled current photo data to fail.")
        return
    }

    #expect(error == .cancelled(assetIdentifier: "image-local-id"))
}

@Test func PhotoKitNetworkErrorsUseTheStablePhotoExportFailure()
{
    let error = NSError(
        domain: PHPhotosErrorDomain,
        code: PHPhotosError.networkAccessRequired.rawValue
    )

    #expect(photoExportError(
        error: error,
        assetIdentifier: "cloud-image-id"
    ) == .networkAccessRequired(assetIdentifier: "cloud-image-id"))
}

@Test func PhotoKitCancellationErrorsUseTheStablePhotoExportFailure()
{
    let error = NSError(
        domain: PHPhotosErrorDomain,
        code: PHPhotosError.userCancelled.rawValue
    )

    #expect(photoExportError(
        error: error,
        assetIdentifier: "image-local-id"
    ) == .cancelled(assetIdentifier: "image-local-id"))
}

@Test func photoExportFileNamesAreSafeAndRepresentationSpecific() throws
{
    let jpegExtension = try #require(UTType.jpeg.preferredFilenameExtension)

    #expect(photoExportFileName(
        originalFilename: "../../IMG_0001.HEIC",
        uniformTypeIdentifier: "public.heic",
        version: .original
    ) == "IMG_0001.HEIC")
    #expect(photoExportFileName(
        originalFilename: "IMG_0001.HEIC",
        uniformTypeIdentifier: "public.jpeg",
        version: .current
    ) == "IMG_0001-current.\(jpegExtension)")
    #expect(photoExportFileName(
        originalFilename: "..",
        uniformTypeIdentifier: "public.jpeg",
        version: .original
    ) == "photo.\(jpegExtension)")
    #expect(photoExportContentType(uniformTypeIdentifier: "public.jpeg") == "image/jpeg")
    #expect(photoExportRepresentation(.current) == .current)
    #expect(photoExportRepresentation(.original) == .original)
}

@Test func imageDimensionsAreReadWithoutRendering() throws
{
    let dimensions = imagePixelDimensions(try testPNGData(width: 37, height: 23))

    #expect(dimensions?.pixelWidth == 37)
    #expect(dimensions?.pixelHeight == 23)
    #expect(availablePixelDimension(37) == 37)
    #expect(availablePixelDimension(0) == nil)
}

@Test func photoExportWriterPlacesDataAndRefusesCollisions() throws
{
    let directory = try temporaryPhotoExportDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = Data("original-photo".utf8)

    let output = try writePhotoExportData(
        data,
        destinationDirectory: directory.path,
        fileName: "IMG_0001.HEIC",
        overwrite: false
    )

    #expect(output.byteLength == data.count)
    #expect(output.outputURL.lastPathComponent == "IMG_0001.HEIC")
    #expect(try Data(contentsOf: output.outputURL) == data)
    #expect(throws: PhotoExportError.self)
    {
        try writePhotoExportData(
            Data("replacement".utf8),
            destinationDirectory: directory.path,
            fileName: "IMG_0001.HEIC",
            overwrite: false
        )
    }
    #expect(try Data(contentsOf: output.outputURL) == data)
}

@Test func photoExportWriterReplacesOutputAndCleansPartialFailures() throws
{
    let directory = try temporaryPhotoExportDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileName = "IMG_0001.HEIC"
    let outputURL = directory.appendingPathComponent(fileName)
    let replacement = Data("replacement".utf8)
    try Data("existing".utf8).write(to: outputURL)

    let output = try writePhotoExportData(
        replacement,
        destinationDirectory: directory.path,
        fileName: fileName,
        overwrite: true
    )

    #expect(output.byteLength == replacement.count)
    #expect(try Data(contentsOf: outputURL) == replacement)

    try FileManager.default.removeItem(at: outputURL)
    #expect(throws: PhotoExportError.self)
    {
        try writePhotoExportData(
            Data("partial".utf8),
            destinationDirectory: directory.path,
            fileName: fileName,
            overwrite: false
        )
        { data, partialURL in
            try data.write(to: partialURL)
            throw StubPhotoExportWriteError()
        }
    }

    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@Test func photoExportWriterRequiresAnExistingDestinationDirectory()
{
    let missingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("missing-photo-export-directory-\(UUID().uuidString)")

    #expect(throws: PhotoExportError.self)
    {
        try writePhotoExportData(
            Data("photo".utf8),
            destinationDirectory: missingDirectory.path,
            fileName: "IMG_0001.JPG",
            overwrite: false
        )
    }
    #expect(!FileManager.default.fileExists(atPath: missingDirectory.path))
}
