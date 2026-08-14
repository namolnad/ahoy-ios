import Foundation

func validate(
    data: Data,
    response: URLResponse,
    acceptableCodes: ClosedRange<Int> = 200...399
) throws {
    guard let status = (response as? HTTPURLResponse)?.statusCode else { return }

    guard acceptableCodes.contains(status) else {
        throw AhoyError.unacceptableResponse(code: status, data: data)
    }
}
