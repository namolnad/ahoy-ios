import Foundation

/// The interceptor provides an opportunity for your application to peform pre-flight modifications to the Ahoy
/// requests, such as adding custom headers. NOTE: If you set the following headers they will be overwritten by Ahoy
/// prior to performing the request: `Content-Type`, `Ahoy-Visitor`, `Ahoy-Visit`.
public struct RequestInterceptor {
    var interceptRequest: (inout URLRequest) -> Void

    public init(interceptRequest: @escaping (inout URLRequest) -> Void) {
        self.interceptRequest = interceptRequest
    }
}
