import Foundation
@testable import OpenFlow

enum TestSupportError: Error {
    case invalidHTTPResponse
}

func makePreferences() -> Preferences {
    Preferences(defaults: makeDefaults())
}

func makeDefaults() -> UserDefaults {
    let suiteName = "OpenFlowTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func makeHTTPResponse(for request: URLRequest, statusCode: Int) throws -> HTTPURLResponse {
    let url = request.url ?? URL(fileURLWithPath: "/")
    guard let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    ) else { throw TestSupportError.invalidHTTPResponse }
    return response
}
