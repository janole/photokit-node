import Foundation
import Testing
@testable import PhotoKitProtocol

private func contentFixtureData(_ name: String) throws -> Data
{
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

private func validThumbnailParameters() -> [String: JSONValue]
{
    [
        "assetIdentifier": .string("image-local-id"),
        "maxHeight": .number(256),
        "maxWidth": .number(384),
        "outputPath": .string("/tmp/photokit-node/thumbnail.jpg"),
    ]
}

private func validExportParameters() -> [String: JSONValue]
{
    [
        "assetIdentifier": .string("image-local-id"),
        "destinationDirectory": .string("/tmp/photokit-node/exports"),
        "version": .string("original"),
    ]
}

@Test func thumbnailRequestMatchesSharedContractFixture() throws
{
    let request = try JSONDecoder().decode(
        ProtocolRequestEnvelope.self,
        from: contentFixtureData("request-get-thumbnail")
    )
    let parameters = try GetThumbnailParameters(parameters: request.parameters)

    #expect(request.operation == ProtocolOperation.getThumbnail.rawValue)
    #expect(parameters.assetIdentifier == "image-local-id")
    #expect(parameters.maxHeight == 256)
    #expect(parameters.maxWidth == 384)
    #expect(parameters.contentMode == .aspectFill)
    #expect(parameters.format == .jpeg)
    #expect(!parameters.allowNetworkAccess)
    #expect(!parameters.overwrite)
}

@Test func exportRequestMatchesSharedContractFixture() throws
{
    let request = try JSONDecoder().decode(
        ProtocolRequestEnvelope.self,
        from: contentFixtureData("request-export-photo")
    )
    let parameters = try ExportPhotoParameters(parameters: request.parameters)

    #expect(request.operation == ProtocolOperation.exportPhoto.rawValue)
    #expect(parameters.assetIdentifier == "image-local-id")
    #expect(parameters.destinationDirectory == "/tmp/photokit-node/exports")
    #expect(parameters.version == .original)
    #expect(parameters.allowNetworkAccess)
    #expect(!parameters.overwrite)
}

@Test func thumbnailParametersApplySafeDefaults() throws
{
    let parameters = try GetThumbnailParameters(parameters: validThumbnailParameters())

    #expect(parameters.contentMode == .aspectFit)
    #expect(parameters.format == .jpeg)
    #expect(!parameters.allowNetworkAccess)
    #expect(!parameters.overwrite)
}

@Test func exportParametersApplySafeDefaults() throws
{
    let parameters = try ExportPhotoParameters(parameters: validExportParameters())

    #expect(!parameters.allowNetworkAccess)
    #expect(!parameters.overwrite)
}

@Test func exportParametersAcceptCurrentRepresentation() throws
{
    var values = validExportParameters()
    values["version"] = .string("current")

    let parameters = try ExportPhotoParameters(parameters: values)

    #expect(parameters.version == .current)
}

@Test func thumbnailParametersAcceptMaximumDimensions() throws
{
    var values = validThumbnailParameters()
    values["maxHeight"] = .number(Double(maximumThumbnailDimension))
    values["maxWidth"] = .number(Double(maximumThumbnailDimension))

    let parameters = try GetThumbnailParameters(parameters: values)

    #expect(parameters.maxHeight == maximumThumbnailDimension)
    #expect(parameters.maxWidth == maximumThumbnailDimension)
}

@Test(arguments: [
    ["assetIdentifier": JSONValue.string("   ")],
    ["contentMode": JSONValue.string("stretch")],
    ["format": JSONValue.string("gif")],
    ["maxHeight": JSONValue.number(0)],
    ["maxHeight": JSONValue.number(4_097)],
    ["maxWidth": JSONValue.number(1.5)],
    ["outputPath": JSONValue.string("relative/thumbnail.jpg")],
    ["overwrite": JSONValue.string("false")],
    ["unexpected": JSONValue.boolean(true)],
])
func thumbnailParametersRejectInvalidValues(overrides: [String: JSONValue])
{
    var values = validThumbnailParameters()
    values.merge(overrides, uniquingKeysWith: { _, replacement in replacement })

    #expect(throws: InvalidAssetContentParametersError.self)
    {
        try GetThumbnailParameters(parameters: values)
    }
}

@Test(arguments: [
    ["allowNetworkAccess": JSONValue.string("true")],
    ["assetIdentifier": JSONValue.string("")],
    ["destinationDirectory": JSONValue.string("relative/exports")],
    ["overwrite": JSONValue.number(1)],
    ["unexpected": JSONValue.boolean(true)],
    ["version": JSONValue.string("adjusted")],
])
func exportParametersRejectInvalidValues(overrides: [String: JSONValue])
{
    var values = validExportParameters()
    values.merge(overrides, uniquingKeysWith: { _, replacement in replacement })

    #expect(throws: InvalidAssetContentParametersError.self)
    {
        try ExportPhotoParameters(parameters: values)
    }
}

@Test func exportParametersRequireAnExplicitVersion()
{
    var values = validExportParameters()
    values.removeValue(forKey: "version")

    #expect(throws: InvalidAssetContentParametersError.self)
    {
        try ExportPhotoParameters(parameters: values)
    }
}

@Test func thumbnailSuccessMatchesSharedContractFixture() throws
{
    let fixture = try JSONDecoder().decode(
        ProtocolSuccessEnvelope<AssetContentData>.self,
        from: contentFixtureData("response-thumbnail-success")
    )
    let response = ProtocolSuccessEnvelope(
        operation: .getThumbnail,
        data: AssetContentData(
            assetIdentifier: "image-local-id",
            file: AssetContentFileDescriptor(
                byteLength: 48_123,
                contentType: "image/jpeg",
                fileName: "thumbnail.jpg",
                path: "/tmp/photokit-node/thumbnail.jpg",
                pixelHeight: 256,
                pixelWidth: 341,
                representation: .thumbnail,
                uniformTypeIdentifier: "public.jpeg"
            )
        )
    )

    #expect(response == fixture)
}

@Test func photoExportSuccessMatchesSharedContractFixture() throws
{
    let fixture = try JSONDecoder().decode(
        ProtocolSuccessEnvelope<AssetContentData>.self,
        from: contentFixtureData("response-photo-export-success")
    )
    let response = ProtocolSuccessEnvelope(
        operation: .exportPhoto,
        data: AssetContentData(
            assetIdentifier: "image-local-id",
            file: AssetContentFileDescriptor(
                byteLength: 4_281_932,
                contentType: "image/heic",
                fileName: "IMG_0001.HEIC",
                path: "/tmp/photokit-node/exports/IMG_0001.HEIC",
                pixelHeight: 3_024,
                pixelWidth: 4_032,
                representation: .original,
                uniformTypeIdentifier: "public.heic"
            )
        )
    )

    #expect(response == fixture)
}
