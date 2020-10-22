import Foundation

public enum AhoyError: Error {
    /// The server replied with a visit that does not match the one provided by the client
    case mismatchingVisit
    /// The client has not yet had a visit successfully confirmed with the server
    case noVisit
    /// The server did not respond with an acceptable status code
    case unacceptableResponse(code: Int, data: Data)
}
