import Foundation
import Testing
@testable import PhotoKitProtocol

private func fixtureData(_ name: String) throws -> Data
{
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

@Test func decodesVersionRequestContractFixture() throws
{
    let request = try JSONDecoder().decode(
        ProtocolRequestEnvelope.self,
        from: fixtureData("request-version")
    )

    #expect(request == ProtocolRequestEnvelope(operation: ProtocolOperation.version.rawValue))
}

@Test func decodesAuthorizationStatusRequestContractFixture() throws
{
    let request = try JSONDecoder().decode(
        ProtocolRequestEnvelope.self,
        from: fixtureData("request-authorization-status")
    )

    #expect(request.operation == ProtocolOperation.authorizationStatus.rawValue)
    #expect(request.parameters.isEmpty)
}

@Test func versionSuccessMatchesContractFixture() throws
{
    let fixture = try JSONDecoder().decode(
        ProtocolSuccessEnvelope<HelperVersionData>.self,
        from: fixtureData("response-version-success")
    )
    let response = ProtocolSuccessEnvelope(operation: .version, data: HelperVersionData())

    #expect(response == fixture)
}

@Test func authorizationSuccessMatchesContractFixture() throws
{
    let fixture = try JSONDecoder().decode(
        ProtocolSuccessEnvelope<AuthorizationStatusData>.self,
        from: fixtureData("response-authorization-status-success")
    )
    let response = ProtocolSuccessEnvelope(
        operation: .authorizationStatus,
        data: AuthorizationStatusData(status: .notDetermined)
    )

    #expect(response == fixture)
}

@Test(arguments: [
    ("response-invalid-request", ProtocolErrorCode.invalidRequest),
    ("response-unknown-operation", ProtocolErrorCode.unknownOperation),
    ("response-incompatible-version", ProtocolErrorCode.incompatibleProtocolVersion),
    ("response-photo-library-access-unavailable", ProtocolErrorCode.photoLibraryAccessUnavailable),
])
func failureResponsesMatchContractFixtures(name: String, code: ProtocolErrorCode) throws
{
    let response = try JSONDecoder().decode(
        ProtocolFailureEnvelope.self,
        from: fixtureData(name)
    )

    #expect(!response.success)
    #expect(response.error.code == code)
}

@Test func rejectsIncompatibleProtocolVersions() throws
{
    let response = try JSONDecoder().decode(
        ProtocolSuccessEnvelope<HelperVersionData>.self,
        from: fixtureData("response-future-version")
    )

    #expect(throws: IncompatibleProtocolVersionError.self)
    {
        try assertCompatibleProtocolVersion(response.protocolVersion)
    }
}

@Test func authorizationResponseExplainsRequestableStatus()
{
    let response = AuthorizationStatusData(status: .notDetermined)

    #expect(response.canRequest)
    #expect(response.guidance == "Send an authorization-request operation to ask for Photos access.")
}

@Test func authorizationResponseMakesDeniedStatusActionable()
{
    let response = AuthorizationStatusData(status: .denied)

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
