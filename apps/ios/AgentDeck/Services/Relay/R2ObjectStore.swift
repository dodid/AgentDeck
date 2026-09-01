import CryptoKit
import Foundation

protocol R2ObjectStore: Sendable {
    func getData(key: String) async throws -> (data: Data, etag: String?)?
    func putData(key: String, data: Data, contentType: String?, ifMatch: String?, ifNoneMatch: String?) async throws
    func listKeys(prefix: String) async throws -> [String]
}

enum R2ObjectStoreError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case preconditionFailed
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "The R2 endpoint is invalid."
        case .invalidResponse: return "The R2 service returned an invalid response."
        case .preconditionFailed: return "The R2 object changed before it could be updated."
        case let .httpStatus(status, message): return "R2 request failed (HTTP \(status)): \(message)"
        }
    }
}

final class R2S3ObjectStore: R2ObjectStore, @unchecked Sendable {
    private let endpoint: URL?
    private let bucket: String
    private let region: String
    private let accessKeyID: String
    private let secretAccessKey: String
    private let forcePathStyle: Bool

    nonisolated init(endpoint: String, bucket: String, region: String, accessKeyID: String, secretAccessKey: String, forcePathStyle: Bool) {
        self.endpoint = URL(string: endpoint)
        self.bucket = bucket
        self.region = region
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.forcePathStyle = forcePathStyle
    }

    func getData(key: String) async throws -> (data: Data, etag: String?)? {
        let (data, response) = try await send(method: "GET", key: key)
        if response.statusCode == 404 { return nil }
        try requireSuccess(response, body: data)
        return (data, response.value(forHTTPHeaderField: "ETag"))
    }

    func putData(key: String, data: Data, contentType: String?, ifMatch: String?, ifNoneMatch: String?) async throws {
        var headers: [String: String] = [:]
        if let contentType { headers["Content-Type"] = contentType }
        if let ifMatch { headers["If-Match"] = ifMatch }
        if let ifNoneMatch { headers["If-None-Match"] = ifNoneMatch }
        let (responseData, response) = try await send(method: "PUT", key: key, body: data, headers: headers)
        try requireSuccess(response, body: responseData)
    }

    func listKeys(prefix: String) async throws -> [String] {
        var keys: [String] = []
        var continuationToken: String?
        repeat {
            var query = [("list-type", "2"), ("prefix", prefix)]
            if let continuationToken { query.append(("continuation-token", continuationToken)) }
            let (data, response) = try await send(method: "GET", key: nil, query: query)
            try requireSuccess(response, body: data)
            let page = try S3ListObjectsPage(data: data)
            keys.append(contentsOf: page.keys)
            continuationToken = page.isTruncated ? page.nextContinuationToken : nil
        } while continuationToken?.isEmpty == false
        return keys
    }

    private func send(method: String, key: String?, body: Data? = nil, headers: [String: String] = [:], query: [(String, String)] = []) async throws -> (Data, HTTPURLResponse) {
        let request = try signedRequest(method: method, key: key, body: body, headers: headers, query: query)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw R2ObjectStoreError.invalidResponse }
        return (data, response)
    }

    private func signedRequest(method: String, key: String?, body: Data?, headers: [String: String], query: [(String, String)]) throws -> URLRequest {
        guard let endpoint else { throw R2ObjectStoreError.invalidEndpoint }
        let now = Date()
        let timestamp = Self.timestamp(now)
        let dateStamp = Self.dateStamp(now)
        let payload = body ?? Data()
        let payloadHash = Self.sha256Hex(payload)
        let url = try makeURL(endpoint: endpoint, key: key, query: query)

        var signedHeaders = headers
        signedHeaders["Host"] = url.host ?? ""
        signedHeaders["X-Amz-Content-Sha256"] = payloadHash
        signedHeaders["X-Amz-Date"] = timestamp
        let canonicalHeaders = signedHeaders
            .map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .sorted { $0.0 < $1.0 }
        let signedHeaderNames = canonicalHeaders.map(\.0).joined(separator: ";")
        let canonicalHeaderString = canonicalHeaders.map { "\($0.0):\($0.1)\n" }.joined()
        let canonicalPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
        let canonicalRequest = [method, canonicalPath, Self.canonicalQuery(query), canonicalHeaderString, signedHeaderNames, payloadHash].joined(separator: "\n")
        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", timestamp, scope, Self.sha256Hex(Data(canonicalRequest.utf8))].joined(separator: "\n")
        let signature = Self.hmacHex(stringToSign, key: Self.signingKey(secret: secretAccessKey, dateStamp: dateStamp, region: region))

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in signedHeaders { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), SignedHeaders=\(signedHeaderNames), Signature=\(signature)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func makeURL(endpoint: URL, key: String?, query: [(String, String)]) throws -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false), let host = components.host else {
            throw R2ObjectStoreError.invalidEndpoint
        }
        let encodedKey: String
        if let key {
            encodedKey = Self.encodePath(key)
        } else {
            encodedKey = ""
        }
        if forcePathStyle {
            let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.percentEncodedPath = "/" + [basePath, Self.encodePath(bucket), encodedKey].filter { !$0.isEmpty }.joined(separator: "/")
        } else {
            components.host = "\(Self.encodePath(bucket)).\(host)"
            components.percentEncodedPath = "/" + encodedKey
        }
        let canonicalQuery = Self.canonicalQuery(query)
        components.percentEncodedQuery = canonicalQuery.isEmpty ? nil : canonicalQuery
        guard let url = components.url else { throw R2ObjectStoreError.invalidEndpoint }
        return url
    }

    private func requireSuccess(_ response: HTTPURLResponse, body: Data) throws {
        if response.statusCode == 409 || response.statusCode == 412 {
            throw R2ObjectStoreError.preconditionFailed
        }
        guard (200..<300).contains(response.statusCode) else {
            throw R2ObjectStoreError.httpStatus(response.statusCode, String(data: body, encoding: .utf8) ?? "No response body")
        }
    }

    private static func canonicalQuery(_ query: [(String, String)]) -> String {
        let encoded = query.map { (key: encode($0.0), value: encode($0.1)) }
        let sorted = encoded.sorted { $0.key == $1.key ? $0.value < $1.value : $0.key < $1.key }
        return sorted.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }

    private static func encodePath(_ value: String) -> String {
        value.split(separator: "/", omittingEmptySubsequences: false).map { encode(String($0)) }.joined(separator: "/")
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? value
    }

    private static func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func hmacHex(_ value: String, key: Data) -> String { hmac(Data(value.utf8), key: key).map { String(format: "%02x", $0) }.joined() }
    private static func hmac(_ data: Data, key: Data) -> Data { Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key))) }

    private static func signingKey(secret: String, dateStamp: String, region: String) -> Data {
        let dateKey = hmac(Data(dateStamp.utf8), key: Data("AWS4\(secret)".utf8))
        let regionKey = hmac(Data(region.utf8), key: dateKey)
        let serviceKey = hmac(Data("s3".utf8), key: regionKey)
        return hmac(Data("aws4_request".utf8), key: serviceKey)
    }

    private static func timestamp(_ date: Date) -> String { format(date, format: "yyyyMMdd'T'HHmmss'Z'") }
    private static func dateStamp(_ date: Date) -> String { format(date, format: "yyyyMMdd") }
    private static func format(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

private final class S3ListObjectsPage: NSObject, XMLParserDelegate {
    private(set) var keys: [String] = []
    private(set) var nextContinuationToken: String?
    private(set) var isTruncated = false
    private var currentValue = ""

    init(data: Data) throws {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw R2ObjectStoreError.invalidResponse }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) { currentValue = "" }
    func parser(_ parser: XMLParser, foundCharacters string: String) { currentValue += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "Key": keys.append(currentValue)
        case "NextContinuationToken": nextContinuationToken = currentValue
        case "IsTruncated": isTruncated = currentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        default: break
        }
    }
}
