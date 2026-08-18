import Testing
@testable import PhotoKitProtocol

@Test func versionResponseUsesCurrentProtocolVersion()
{
    #expect(HelperVersionResponse().protocolVersion == helperProtocolVersion)
}
