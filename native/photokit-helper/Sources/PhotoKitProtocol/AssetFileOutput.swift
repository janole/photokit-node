import Foundation

enum AssetFileOutputError: Error, Equatable
{
    case fileExists(path: String)
    case writeFailed(path: String)
}

func writeAssetContentData(
    _ data: Data,
    outputURL: URL,
    overwrite: Bool,
    fileManager: FileManager = .default,
    writePartial: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }
) throws -> Int
{
    var isDirectory: ObjCBool = false
    let directoryURL = outputURL.deletingLastPathComponent()

    guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue else
    {
        throw AssetFileOutputError.writeFailed(path: outputURL.path)
    }

    if fileManager.fileExists(atPath: outputURL.path), !overwrite
    {
        throw AssetFileOutputError.fileExists(path: outputURL.path)
    }

    let partialURL = directoryURL
        .appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).partial")

    defer
    {
        try? fileManager.removeItem(at: partialURL)
    }

    do
    {
        try writePartial(data, partialURL)

        if fileManager.fileExists(atPath: outputURL.path)
        {
            guard overwrite else
            {
                throw AssetFileOutputError.fileExists(path: outputURL.path)
            }

            _ = try fileManager.replaceItemAt(outputURL, withItemAt: partialURL)
        }
        else
        {
            try fileManager.moveItem(at: partialURL, to: outputURL)
        }

        let attributes = try fileManager.attributesOfItem(atPath: outputURL.path)
        guard let byteLength = attributes[.size] as? NSNumber else
        {
            throw AssetFileOutputError.writeFailed(path: outputURL.path)
        }

        return byteLength.intValue
    }
    catch let error as AssetFileOutputError
    {
        throw error
    }
    catch
    {
        throw AssetFileOutputError.writeFailed(path: outputURL.path)
    }
}
