import Foundation

enum HTTPError: LocalizedError {
    case status(Int)
    case missingKey

    var errorDescription: String? {
        switch self {
        case .status(401): "The TMDB key was rejected. Check it in Settings."
        case .status(404): "That title couldn't be found."
        case .status(429): "Too many requests. Try again in a moment."
        case .status(let code): "The server returned an error (\(code))."
        case .missingKey: "Add a TMDB API key in Settings to use this."
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "CouchPotato/1.0 (https://github.com/nearbycoder/couch-potato)"]
        return URLSession(configuration: config)
    }()

    static func get<T: Decodable>(_ url: URL, as type: T.Type = T.self, headers: [String: String] = [:],
                                  decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HTTPError.status(http.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    static func url(_ base: String, _ path: String, _ query: [String: String?] = [:]) -> URL {
        var components = URLComponents(string: base + path)!
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        return components.url!
    }
}

enum DateParsing {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = day.date(from: String(string.prefix(10))), string.count <= 10 { return d }
        return ISO8601DateFormatter().date(from: string) ?? day.date(from: String(string.prefix(10)))
    }

    static func year(_ string: String?) -> Int? {
        guard let string, string.count >= 4 else { return nil }
        return Int(string.prefix(4))
    }

    static func dayString(_ date: Date) -> String { day.string(from: date) }
}
