/** Protocol version shared by the Node wrapper and native helper. */
export const helperProtocolVersion = 1;

/** Photo library authorization states returned by the native helper. */
export type PhotoLibraryAuthorizationStatus = "authorized" | "denied" | "limited" | "not-determined" | "restricted";

/** Response returned by the native helper's version command. */
export interface HelperVersionResponse
{
    protocolVersion: number;
}

/** Response returned by the native helper's authorization-status command. */
export interface AuthorizationStatusResponse
{
    status: PhotoLibraryAuthorizationStatus;
}
