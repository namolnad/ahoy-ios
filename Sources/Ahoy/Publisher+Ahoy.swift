import Combine
import Foundation

enum AhoyError: Error {
    case unacceptableResponse(code: Int, data: Data)
}

extension Publisher where Output == (data: Data, response: URLResponse) {
    func validateResponse(acceptableCodes: ClosedRange<Int> = 200...399) -> AnyPublisher<Output, Error> {
        tryMap { data, response in
            guard let status = (response as? HTTPURLResponse)?.statusCode else {
                return (data, response)
            }
            guard acceptableCodes.contains(status) else {
                throw AhoyError.unacceptableResponse(code: status, data: data)
            }
            return (data, response)
        }
        .eraseToAnyPublisher()
    }
}

