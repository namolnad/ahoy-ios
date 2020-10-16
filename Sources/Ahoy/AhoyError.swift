import Foundation

public enum AhoyError: Error {
    /// The server replied with a session that does not match the one provided by the client
    case mismatchingSession
    /// The client has not yet had a session successfully confirmed with the server
    case noSession
    /// The server did not respond with an acceptable status code
    case unacceptableResponse(code: Int, data: Data)
}
