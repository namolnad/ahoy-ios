import Foundation

public struct RequestInterceptor {
    var interceptRequest: (inout URLRequest) -> Void

    public init(interceptRequest: @escaping (inout URLRequest) -> Void) {
        self.interceptRequest = interceptRequest
    }
}
