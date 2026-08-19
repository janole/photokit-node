import Foundation
import Photos

/// Default number of recent assets returned by the helper.
public let defaultAssetLimit = 20

/// Largest asset limit accepted by the helper.
public let maximumAssetLimit = 200

/// Image and video media types exposed by the helper.
public enum AssetMediaType: String, Codable, Equatable, Sendable
{
    case image
    case video
}

/// Stable names for PhotoKit media-subtype flags.
public enum AssetMediaSubtype: String, Codable, Equatable, Sendable
{
    case photoDepthEffect = "photo-depth-effect"
    case photoHDR = "photo-hdr"
    case photoLive = "photo-live"
    case photoPanorama = "photo-panorama"
    case photoScreenshot = "photo-screenshot"
    case spatialMedia = "spatial-media"
    case videoCinematic = "video-cinematic"
    case videoHighFrameRate = "video-high-frame-rate"
    case videoStreamed = "video-streamed"
    case videoTimelapse = "video-timelapse"
}

/// Indicates that list-assets parameters do not match the protocol contract.
public struct InvalidListAssetsParametersError: Error, Equatable, Sendable
{
    public let message: String

    public init(message: String)
    {
        self.message = message
    }
}

/// Validated parameters for a recent-asset listing operation.
public struct ListAssetsParameters: Equatable, Sendable
{
    public let limit: Int
    public let mediaType: AssetMediaType?

    public init(parameters: [String: JSONValue]) throws
    {
        let supportedKeys = Set(["limit", "mediaType"])

        if let unsupportedKey = parameters.keys.filter({ !supportedKeys.contains($0) }).sorted().first
        {
            throw InvalidListAssetsParametersError(message: "Unsupported list-assets parameter \"\(unsupportedKey)\".")
        }

        self.limit = try Self.decodeLimit(parameters["limit"])
        self.mediaType = try Self.decodeMediaType(parameters["mediaType"])
    }

    private static func decodeLimit(_ value: JSONValue?) throws -> Int
    {
        guard let value else
        {
            return defaultAssetLimit
        }

        guard case .number(let number) = value,
              number.rounded(.towardZero) == number,
              number >= 1,
              number <= Double(maximumAssetLimit) else
        {
            throw InvalidListAssetsParametersError(
                message: "list-assets limit must be an integer from 1 through \(maximumAssetLimit)."
            )
        }

        return Int(number)
    }

    private static func decodeMediaType(_ value: JSONValue?) throws -> AssetMediaType?
    {
        guard let value else
        {
            return nil
        }

        guard case .string(let rawValue) = value,
              let mediaType = AssetMediaType(rawValue: rawValue) else
        {
            throw InvalidListAssetsParametersError(
                message: "list-assets mediaType must be \"image\" or \"video\"."
            )
        }

        return mediaType
    }
}

/// Metadata returned for one PhotoKit asset without requesting its content.
public struct AssetMetadata: Codable, Equatable, Sendable
{
    public let creationDate: Date?
    public let duration: Double?
    public let favorite: Bool
    public let hidden: Bool
    public let localIdentifier: String
    public let mediaSubtypes: [AssetMediaSubtype]
    public let mediaType: AssetMediaType
    public let modificationDate: Date?
    public let pixelHeight: Int
    public let pixelWidth: Int

    public init(
        creationDate: Date?,
        duration: Double?,
        favorite: Bool,
        hidden: Bool,
        localIdentifier: String,
        mediaSubtypes: [AssetMediaSubtype],
        mediaType: AssetMediaType,
        modificationDate: Date?,
        pixelHeight: Int,
        pixelWidth: Int
    )
    {
        self.creationDate = creationDate
        self.duration = duration
        self.favorite = favorite
        self.hidden = hidden
        self.localIdentifier = localIdentifier
        self.mediaSubtypes = mediaSubtypes
        self.mediaType = mediaType
        self.modificationDate = modificationDate
        self.pixelHeight = pixelHeight
        self.pixelWidth = pixelWidth
    }

    private enum CodingKeys: String, CodingKey
    {
        case creationDate
        case duration
        case favorite
        case hidden
        case localIdentifier
        case mediaSubtypes
        case mediaType
        case modificationDate
        case pixelHeight
        case pixelWidth
    }

    public func encode(to encoder: Encoder) throws
    {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(creationDate, forKey: .creationDate)
        try container.encode(duration, forKey: .duration)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(hidden, forKey: .hidden)
        try container.encode(localIdentifier, forKey: .localIdentifier)
        try container.encode(mediaSubtypes, forKey: .mediaSubtypes)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(modificationDate, forKey: .modificationDate)
        try container.encode(pixelHeight, forKey: .pixelHeight)
        try container.encode(pixelWidth, forKey: .pixelWidth)
    }
}

/// Data returned by the list-assets operation.
public struct AssetListData: Codable, Equatable, Sendable
{
    public let assets: [AssetMetadata]

    public init(assets: [AssetMetadata])
    {
        self.assets = assets
    }
}

protocol AssetMetadataSource
{
    var creationDate: Date? { get }
    var duration: TimeInterval { get }
    var isFavorite: Bool { get }
    var isHidden: Bool { get }
    var localIdentifier: String { get }
    var mediaSubtypes: PHAssetMediaSubtype { get }
    var mediaType: PHAssetMediaType { get }
    var modificationDate: Date? { get }
    var pixelHeight: Int { get }
    var pixelWidth: Int { get }
}

extension PHAsset: AssetMetadataSource {}

/// Reports whether PhotoKit may return readable assets for an authorization status.
public func isPhotoLibraryReadAccessAvailable(_ status: PhotoLibraryAuthorizationStatus) -> Bool
{
    status == .authorized || status == .limited
}

func makeAssetFetchOptions(_ parameters: ListAssetsParameters) -> PHFetchOptions
{
    let options = PHFetchOptions()
    options.fetchLimit = parameters.limit
    options.includeHiddenAssets = true
    // PhotoKit raises NSInvalidArgumentException when localIdentifier is a fetch sort descriptor on macOS.
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

    switch parameters.mediaType
    {
    case .image:
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
    case .video:
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
    case nil:
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaType.video.rawValue
        )
    }

    return options
}

func recentAssetMetadata(_ assets: [AssetMetadata], limit: Int) -> [AssetMetadata]
{
    let sorted = assets.sorted
    { left, right in
        if left.creationDate != right.creationDate
        {
            switch (left.creationDate, right.creationDate)
            {
            case (.some(let leftDate), .some(let rightDate)):
                return leftDate > rightDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }
        }

        return left.localIdentifier < right.localIdentifier
    }

    return Array(sorted.prefix(limit))
}

func assetMetadata(from asset: AssetMetadataSource) -> AssetMetadata?
{
    let mediaType: AssetMediaType

    switch asset.mediaType
    {
    case .image:
        mediaType = .image
    case .video:
        mediaType = .video
    default:
        return nil
    }

    return AssetMetadata(
        creationDate: asset.creationDate,
        duration: mediaType == .video ? asset.duration : nil,
        favorite: asset.isFavorite,
        hidden: asset.isHidden,
        localIdentifier: asset.localIdentifier,
        mediaSubtypes: assetMediaSubtypes(from: asset.mediaSubtypes),
        mediaType: mediaType,
        modificationDate: asset.modificationDate,
        pixelHeight: asset.pixelHeight,
        pixelWidth: asset.pixelWidth
    )
}

func assetMediaSubtypes(from subtypes: PHAssetMediaSubtype) -> [AssetMediaSubtype]
{
    let knownSubtypes: [(PHAssetMediaSubtype, AssetMediaSubtype)] = [
        (.photoPanorama, .photoPanorama),
        (.photoHDR, .photoHDR),
        (.photoScreenshot, .photoScreenshot),
        (.photoLive, .photoLive),
        (.photoDepthEffect, .photoDepthEffect),
        (.spatialMedia, .spatialMedia),
        (.videoStreamed, .videoStreamed),
        (.videoHighFrameRate, .videoHighFrameRate),
        (.videoTimelapse, .videoTimelapse),
        (.videoCinematic, .videoCinematic),
    ]

    return knownSubtypes.compactMap
    { flag, name in
        subtypes.contains(flag) ? name : nil
    }
}

/// Fetches recent image/video metadata without requesting asset resources.
public func listRecentAssets(parameters: ListAssetsParameters) -> AssetListData
{
    let result = PHAsset.fetchAssets(with: makeAssetFetchOptions(parameters))
    var assets: [AssetMetadata] = []
    assets.reserveCapacity(result.count)

    result.enumerateObjects
    { asset, _, _ in
        if let metadata = assetMetadata(from: asset)
        {
            assets.append(metadata)
        }
    }

    return AssetListData(assets: recentAssetMetadata(assets, limit: parameters.limit))
}
