import Foundation
import Photos
import Testing
@testable import PhotoKitProtocol

private struct FakeAsset: AssetMetadataSource
{
    let creationDate: Date?
    let duration: TimeInterval
    let isFavorite: Bool
    let isHidden: Bool
    let localIdentifier: String
    let mediaSubtypes: PHAssetMediaSubtype
    let mediaType: PHAssetMediaType
    let modificationDate: Date?
    let pixelHeight: Int
    let pixelWidth: Int
}

private func assetFixtureData(_ name: String) throws -> Data
{
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

private func date(_ value: String) throws -> Date
{
    try #require(ISO8601DateFormatter().date(from: value))
}

private func metadata(identifier: String, creationDate: Date?) -> AssetMetadata
{
    AssetMetadata(
        creationDate: creationDate,
        duration: nil,
        favorite: false,
        hidden: false,
        localIdentifier: identifier,
        mediaSubtypes: [],
        mediaType: .image,
        modificationDate: nil,
        pixelHeight: 1,
        pixelWidth: 1
    )
}

@Test func listAssetsParametersApplyDefaults() throws
{
    let parameters = try ListAssetsParameters(parameters: [:])

    #expect(parameters.limit == defaultAssetLimit)
    #expect(parameters.mediaType == nil)
}

@Test func listAssetsParametersDecodeFilterAndLimit() throws
{
    let parameters = try ListAssetsParameters(parameters: [
        "limit": .number(8),
        "mediaType": .string("video"),
    ])

    #expect(parameters.limit == 8)
    #expect(parameters.mediaType == .video)
}

@Test func listAssetsParametersAcceptMaximumLimit() throws
{
    let parameters = try ListAssetsParameters(parameters: [
        "limit": .number(Double(maximumAssetLimit)),
    ])

    #expect(parameters.limit == maximumAssetLimit)
}

@Test(arguments: [
    ["limit": JSONValue.number(0)],
    ["limit": JSONValue.number(201)],
    ["limit": JSONValue.number(1.5)],
    ["limit": JSONValue.string("20")],
    ["mediaType": JSONValue.string("audio")],
    ["unexpected": JSONValue.boolean(true)],
])
func listAssetsParametersRejectInvalidValues(parameters: [String: JSONValue])
{
    #expect(throws: InvalidListAssetsParametersError.self)
    {
        try ListAssetsParameters(parameters: parameters)
    }
}

@Test func fetchOptionsAreBoundedAndUseSupportedSorting() throws
{
    let parameters = try ListAssetsParameters(parameters: [
        "limit": .number(7),
        "mediaType": .string("image"),
    ])
    let options = makeAssetFetchOptions(parameters)

    #expect(options.fetchLimit == 7)
    #expect(options.includeHiddenAssets)
    #expect(options.sortDescriptors?.map(\.key) == ["creationDate"])
    #expect(options.sortDescriptors?.map(\.ascending) == [false])
    #expect(options.predicate?.evaluate(with: ["mediaType": PHAssetMediaType.image.rawValue]) == true)
    #expect(options.predicate?.evaluate(with: ["mediaType": PHAssetMediaType.video.rawValue]) == false)
}

@Test func metadataSortIsNewestFirstDeterministicAndBounded() throws
{
    let newestDate = try date("2026-08-19T10:00:00Z")
    let olderDate = try date("2026-08-18T10:00:00Z")
    let assets = [
        metadata(identifier: "older", creationDate: olderDate),
        metadata(identifier: "z-tie", creationDate: newestDate),
        metadata(identifier: "no-date", creationDate: nil),
        metadata(identifier: "a-tie", creationDate: newestDate),
    ]

    #expect(recentAssetMetadata(assets, limit: 3).map(\.localIdentifier) == [
        "a-tie",
        "z-tie",
        "older",
    ])
}

@Test func unfilteredFetchIncludesOnlyImagesAndVideos() throws
{
    let options = makeAssetFetchOptions(try ListAssetsParameters(parameters: [:]))

    #expect(options.predicate?.evaluate(with: ["mediaType": PHAssetMediaType.image.rawValue]) == true)
    #expect(options.predicate?.evaluate(with: ["mediaType": PHAssetMediaType.video.rawValue]) == true)
    #expect(options.predicate?.evaluate(with: ["mediaType": PHAssetMediaType.audio.rawValue]) == false)
}

@Test func mapsImageMetadataWithoutDuration() throws
{
    let source = FakeAsset(
        creationDate: nil,
        duration: 0,
        isFavorite: false,
        isHidden: true,
        localIdentifier: "image-local-id",
        mediaSubtypes: [.photoScreenshot],
        mediaType: .image,
        modificationDate: nil,
        pixelHeight: 3024,
        pixelWidth: 4032
    )
    let metadata = try #require(assetMetadata(from: source))

    #expect(metadata.duration == nil)
    #expect(metadata.mediaSubtypes == [.photoScreenshot])
    #expect(metadata.mediaType == .image)
    #expect(metadata.hidden)
}

@Test func mapsVideoMetadataAndSubtypeFlags() throws
{
    let source = FakeAsset(
        creationDate: try date("2026-08-19T10:00:00Z"),
        duration: 4.25,
        isFavorite: true,
        isHidden: false,
        localIdentifier: "video-local-id",
        mediaSubtypes: [.videoHighFrameRate, .videoCinematic],
        mediaType: .video,
        modificationDate: try date("2026-08-19T10:05:00Z"),
        pixelHeight: 1080,
        pixelWidth: 1920
    )
    let metadata = try #require(assetMetadata(from: source))

    #expect(metadata.duration == 4.25)
    #expect(metadata.favorite)
    #expect(metadata.mediaSubtypes == [.videoHighFrameRate, .videoCinematic])
    #expect(metadata.mediaType == .video)
}

@Test func assetListMatchesSharedContractFixture() throws
{
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let response = try decoder.decode(
        ProtocolSuccessEnvelope<AssetListData>.self,
        from: assetFixtureData("response-assets-success")
    )

    #expect(response.operation == ProtocolOperation.listAssets.rawValue)
    #expect(response.data.assets.count == 2)
    #expect(response.data.assets[0].localIdentifier == "video-local-id")
    #expect(response.data.assets[1].duration == nil)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let encoded = try #require(try JSONSerialization.jsonObject(with: encoder.encode(response)) as? NSDictionary)
    let fixture = try #require(try JSONSerialization.jsonObject(
        with: assetFixtureData("response-assets-success")
    ) as? NSDictionary)

    #expect(encoded == fixture)
}

@Test func emptyAssetListIsASuccessfulContractResponse() throws
{
    let response = try JSONDecoder().decode(
        ProtocolSuccessEnvelope<AssetListData>.self,
        from: assetFixtureData("response-assets-empty")
    )

    #expect(response.success)
    #expect(response.data.assets.isEmpty)
}

@Test(arguments: [
    (PhotoLibraryAuthorizationStatus.authorized, true),
    (PhotoLibraryAuthorizationStatus.limited, true),
    (PhotoLibraryAuthorizationStatus.denied, false),
    (PhotoLibraryAuthorizationStatus.notDetermined, false),
    (PhotoLibraryAuthorizationStatus.restricted, false),
])
func readAccessMatchesAuthorizationStatus(status: PhotoLibraryAuthorizationStatus, expected: Bool)
{
    #expect(isPhotoLibraryReadAccessAvailable(status) == expected)
}
