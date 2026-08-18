import Testing
@testable import PhotoKitProtocol

@Test func versionResponseUsesCurrentProtocolVersion()
{
    #expect(HelperVersionResponse().protocolVersion == helperProtocolVersion)
}

@Test func authorizationResponseExplainsRequestableStatus()
{
    let response = AuthorizationStatusResponse(status: .notDetermined)

    #expect(response.canRequest)
    #expect(response.guidance == "Run authorization-request to ask for Photos access.")
}

@Test func authorizationResponseMakesDeniedStatusActionable()
{
    let response = AuthorizationStatusResponse(status: .denied)

    #expect(!response.canRequest)
    #expect(response.guidance.contains("System Settings"))
}

@Test func authorizationRequestDoesNotPromptForResolvedStatus() async
{
    var didRequest = false

    let status = await authorizationStatusAfterRequest(currentStatus: .restricted)
    {
        didRequest = true
        return .authorized
    }

    #expect(status == .restricted)
    #expect(!didRequest)
}

@Test func authorizationRequestPromptsForUndeterminedStatus() async
{
    var didRequest = false

    let status = await authorizationStatusAfterRequest(currentStatus: .notDetermined)
    {
        didRequest = true
        return .limited
    }

    #expect(status == .limited)
    #expect(didRequest)
}
