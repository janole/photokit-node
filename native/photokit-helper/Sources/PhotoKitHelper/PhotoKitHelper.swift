import Foundation
import PhotoKitProtocol

enum HelperError: Error
{
    case unknownCommand(String?)
}

func writeJSON<T: Encodable>(_ value: T) throws
{
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

@main
struct PhotoKitHelper
{
    static func main() async
    {
        do
        {
            let command = CommandLine.arguments.dropFirst().first

            switch command
            {
            case "version":
                try writeJSON(HelperVersionResponse())
            case "authorization-status":
                try writeJSON(AuthorizationStatusResponse(status: currentAuthorizationStatus()))
            case "authorization-request":
                let status = await requestPhotoLibraryAuthorization()
                try writeJSON(AuthorizationStatusResponse(status: status))
            default:
                throw HelperError.unknownCommand(command)
            }
        }
        catch
        {
            FileHandle.standardError.write(Data("photokit-helper: \(error)\n".utf8))
            exit(64)
        }
    }
}
