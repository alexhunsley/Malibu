import Foundation

public protocol Requestable {
  var method: Method { get }
  var message: Message { get set }
  var contentType: ContentType { get }
  var etagPolicy: EtagPolicy { get }
  var storePolicy: StorePolicy { get }
  var cachePolicy: NSURLRequest.CachePolicy { get }

  func toUrlRequest(baseUrl: URLStringConvertible?,
                    additionalHeaders: [String: String]) throws -> NSMutableURLRequest
}

public extension Requestable {

  // MARK: - Default implementations

  var storePolicy: StorePolicy {
    return .unspecified
  }

  var cachePolicy: NSURLRequest.CachePolicy {
    return .useProtocolCachePolicy
  }

  func toUrlRequest(baseUrl: URLStringConvertible? = nil,
                    additionalHeaders: [String: String] = [:]) throws -> NSMutableURLRequest {
    let prefix = baseUrl?.urlString ?? ""
    let resourceString = "\(prefix)\(message.resource.urlString)"
    let url = try buildUrl(from: resourceString)
    let request = NSMutableURLRequest(url: url)

    request.httpMethod = method.rawValue
    request.cachePolicy = cachePolicy

    if let contentTypeHeader = contentType.header {
      request.setValue(contentTypeHeader, forHTTPHeaderField: "Content-Type")
    }

    var data: Data?

    if let encoder = parameterEncoders[contentType] {
      data = try encoder.encode(parameters: message.parameters)
    } else if let encoder = contentType.encoder {
      data = try encoder.encode(parameters: message.parameters)
    }

    request.httpBody = data

    if let body = data, contentType == .multipartFormData {
      request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
    }

    [additionalHeaders, message.headers].forEach {
      $0.forEach { key, value in
        request.setValue(value, forHTTPHeaderField: key)
      }
    }

    if etagPolicy == .enabled {
      if let etag = EtagStorage().get(etagKey(prefix: prefix)) {
        request.setValue(etag, forHTTPHeaderField: "If-None-Match")
      }
    }

    return request
  }

  // MARK: - Helpers

  func buildUrl(from string: String) throws -> URL {
    guard let url = URL(string: string) else {
      throw NetworkError.invalidRequestURL
    }

    guard contentType == .query && !message.parameters.isEmpty else {
      return url
    }

    guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url
    }

    let percentEncodedQuery = (urlComponents.percentEncodedQuery.map { $0 + "&" } ?? "")
      + QueryBuilder().buildQuery(from: message.parameters)

    urlComponents.percentEncodedQuery = percentEncodedQuery

    guard let queryURL = urlComponents.url else {
      throw NetworkError.invalidRequestURL
    }

    return queryURL
  }

  func etagKey(prefix: String = "") -> String {
    return "\(method.rawValue)\(prefix)\(message.resource.urlString)\(message.parameters.description)"
  }

  var key: String {
    return "\(method.rawValue) \(message.resource.urlString)"
  }
}
