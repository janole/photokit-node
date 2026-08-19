import Foundation

/// Maximum width or height accepted by the thumbnail contract.
public let maximumThumbnailDimension = 4_096

/// Crop behavior for a rendered thumbnail.
public enum ThumbnailContentMode: String, Codable, Equatable, Sendable
{
    case aspectFill = "aspect-fill"
    case aspectFit = "aspect-fit"
}

/// Encodings supported for rendered thumbnails.
public enum ThumbnailFormat: String, Codable, Equatable, Sendable
{
    case jpeg
    case png
}

/// Still-photo representation selected for export.
public enum PhotoExportVersion: String, Codable, Equatable, Sendable
{
    case current
    case original
}

/// Kind of image content written by an asset-content operation.
public enum AssetContentRepresentation: String, Codable, Equatable, Sendable
{
    case current
    case original
    case thumbnail
}

/// Indicates that asset-content parameters do not match the protocol contract.
public struct InvalidAssetContentParametersError: Error, Equatable, Sendable
{
    public let message: String

    public init(message: String)
    {
        self.message = message
    }
}

/// Validated parameters for one thumbnail request.
public struct GetThumbnailParameters: Equatable, Sendable
{
    public let allowNetworkAccess: Bool
    public let assetIdentifier: String
    public let contentMode: ThumbnailContentMode
    public let format: ThumbnailFormat
    public let maxHeight: Int
    public let maxWidth: Int
    public let outputPath: String
    public let overwrite: Bool

    public init(parameters: [String: JSONValue]) throws
    {
        try rejectUnsupportedKeys(
            parameters,
            supported: [
                "allowNetworkAccess",
                "assetIdentifier",
                "contentMode",
                "format",
                "maxHeight",
                "maxWidth",
                "outputPath",
                "overwrite",
            ],
            operation: ProtocolOperation.getThumbnail.rawValue
        )

        self.allowNetworkAccess = try decodeBoolean(
            parameters["allowNetworkAccess"],
            key: "allowNetworkAccess",
            defaultValue: false,
            operation: ProtocolOperation.getThumbnail.rawValue
        )
        self.assetIdentifier = try decodeAssetIdentifier(
            parameters["assetIdentifier"],
            operation: ProtocolOperation.getThumbnail.rawValue
        )
        self.contentMode = try decodeEnum(
            parameters["contentMode"],
            key: "contentMode",
            defaultValue: ThumbnailContentMode.aspectFit,
            allowedValues: ["aspect-fit", "aspect-fill"],
            operation: ProtocolOperation.getThumbnail.rawValue
        )
        self.format = try decodeEnum(
            parameters["format"],
            key: "format",
            defaultValue: ThumbnailFormat.jpeg,
            allowedValues: ["jpeg", "png"],
            operation: ProtocolOperation.getThumbnail.rawValue
        )
        self.maxHeight = try decodeThumbnailDimension(
            parameters["maxHeight"],
            key: "maxHeight"
        )
        self.maxWidth = try decodeThumbnailDimension(
            parameters["maxWidth"],
            key: "maxWidth"
        )
        self.outputPath = try decodeAbsolutePath(
            parameters["outputPath"],
            key: "outputPath",
            operation: ProtocolOperation.getThumbnail.rawValue
        )
        self.overwrite = try decodeBoolean(
            parameters["overwrite"],
            key: "overwrite",
            defaultValue: false,
            operation: ProtocolOperation.getThumbnail.rawValue
        )
    }
}

/// Validated parameters for one still-photo export request.
public struct ExportPhotoParameters: Equatable, Sendable
{
    public let allowNetworkAccess: Bool
    public let assetIdentifier: String
    public let destinationDirectory: String
    public let overwrite: Bool
    public let version: PhotoExportVersion

    public init(parameters: [String: JSONValue]) throws
    {
        try rejectUnsupportedKeys(
            parameters,
            supported: [
                "allowNetworkAccess",
                "assetIdentifier",
                "destinationDirectory",
                "overwrite",
                "version",
            ],
            operation: ProtocolOperation.exportPhoto.rawValue
        )

        self.allowNetworkAccess = try decodeBoolean(
            parameters["allowNetworkAccess"],
            key: "allowNetworkAccess",
            defaultValue: false,
            operation: ProtocolOperation.exportPhoto.rawValue
        )
        self.assetIdentifier = try decodeAssetIdentifier(
            parameters["assetIdentifier"],
            operation: ProtocolOperation.exportPhoto.rawValue
        )
        self.destinationDirectory = try decodeAbsolutePath(
            parameters["destinationDirectory"],
            key: "destinationDirectory",
            operation: ProtocolOperation.exportPhoto.rawValue
        )
        self.overwrite = try decodeBoolean(
            parameters["overwrite"],
            key: "overwrite",
            defaultValue: false,
            operation: ProtocolOperation.exportPhoto.rawValue
        )
        self.version = try decodeRequiredEnum(
            parameters["version"],
            key: "version",
            allowedValues: ["current", "original"],
            operation: ProtocolOperation.exportPhoto.rawValue
        )
    }
}

/// File produced out of band by an asset-content operation.
public struct AssetContentFileDescriptor: Codable, Equatable, Sendable
{
    public let byteLength: Int
    public let contentType: String
    public let fileName: String
    public let path: String
    public let pixelHeight: Int?
    public let pixelWidth: Int?
    public let representation: AssetContentRepresentation
    public let uniformTypeIdentifier: String

    public init(
        byteLength: Int,
        contentType: String,
        fileName: String,
        path: String,
        pixelHeight: Int?,
        pixelWidth: Int?,
        representation: AssetContentRepresentation,
        uniformTypeIdentifier: String
    )
    {
        self.byteLength = byteLength
        self.contentType = contentType
        self.fileName = fileName
        self.path = path
        self.pixelHeight = pixelHeight
        self.pixelWidth = pixelWidth
        self.representation = representation
        self.uniformTypeIdentifier = uniformTypeIdentifier
    }
}

/// Data returned by get-thumbnail and export-photo.
public struct AssetContentData: Codable, Equatable, Sendable
{
    public let assetIdentifier: String
    public let file: AssetContentFileDescriptor

    public init(assetIdentifier: String, file: AssetContentFileDescriptor)
    {
        self.assetIdentifier = assetIdentifier
        self.file = file
    }
}

private func invalidParameter(_ message: String) -> InvalidAssetContentParametersError
{
    InvalidAssetContentParametersError(message: message)
}

private func rejectUnsupportedKeys(
    _ parameters: [String: JSONValue],
    supported: Set<String>,
    operation: String
) throws
{
    if let unsupportedKey = parameters.keys.filter({ !supported.contains($0) }).sorted().first
    {
        throw invalidParameter("Unsupported \(operation) parameter \"\(unsupportedKey)\".")
    }
}

private func decodeAssetIdentifier(_ value: JSONValue?, operation: String) throws -> String
{
    guard case .string(let identifier) = value,
          !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else
    {
        throw invalidParameter("\(operation) assetIdentifier must be a non-empty string.")
    }

    return identifier
}

private func decodeAbsolutePath(_ value: JSONValue?, key: String, operation: String) throws -> String
{
    guard case .string(let path) = value,
          !path.isEmpty,
          (path as NSString).isAbsolutePath else
    {
        throw invalidParameter("\(operation) \(key) must be an absolute path.")
    }

    return path
}

private func decodeBoolean(
    _ value: JSONValue?,
    key: String,
    defaultValue: Bool,
    operation: String
) throws -> Bool
{
    guard let value else
    {
        return defaultValue
    }

    guard case .boolean(let boolean) = value else
    {
        throw invalidParameter("\(operation) \(key) must be a boolean.")
    }

    return boolean
}

private func decodeThumbnailDimension(_ value: JSONValue?, key: String) throws -> Int
{
    guard case .number(let number) = value,
          number.rounded(.towardZero) == number,
          number >= 1,
          number <= Double(maximumThumbnailDimension) else
    {
        throw invalidParameter(
            "get-thumbnail \(key) must be an integer from 1 through \(maximumThumbnailDimension)."
        )
    }

    return Int(number)
}

private func decodeEnum<Value: RawRepresentable>(
    _ value: JSONValue?,
    key: String,
    defaultValue: Value,
    allowedValues: [String],
    operation: String
) throws -> Value where Value.RawValue == String
{
    guard let value else
    {
        return defaultValue
    }

    return try decodeRequiredEnum(
        value,
        key: key,
        allowedValues: allowedValues,
        operation: operation
    )
}

private func decodeRequiredEnum<Value: RawRepresentable>(
    _ value: JSONValue?,
    key: String,
    allowedValues: [String],
    operation: String
) throws -> Value where Value.RawValue == String
{
    guard case .string(let rawValue) = value,
          let decoded = Value(rawValue: rawValue) else
    {
        let choices = allowedValues.map({ "\"\($0)\"" }).joined(separator: " or ")
        throw invalidParameter("\(operation) \(key) must be \(choices).")
    }

    return decoded
}
