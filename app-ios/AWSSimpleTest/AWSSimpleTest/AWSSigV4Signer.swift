//
//  AWSSigV4Signer.swift
//  AWSSimpleTest
//
//  AWS Signature Version 4 signing utility for WebSocket authentication
//

import Foundation
import CryptoKit

class AWSSigV4Signer {
    private let accessKey: String
    private let secretKey: String
    private let region: String
    private let service: String

    init(accessKey: String, secretKey: String, region: String, service: String = "iotdevicegateway") {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        self.service = service
    }

    func signWebSocketURL(endpoint: String, uri: String = "/mqtt", additionalParams: [String: String] = [:]) -> URL? {
        let now = Date()

        // Create datetime in format: 20260108T114251Z
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let datetime = dateFormatter.string(from: now)

        // Create date in format: 20260108
        dateFormatter.dateFormat = "yyyyMMdd"
        let date = dateFormatter.string(from: now)

        let method = "GET"
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(date)/\(region)/\(service)/aws4_request"

        var queryParams: [String: String] = [
            "X-Amz-Algorithm": algorithm,
            "X-Amz-Credential": "\(accessKey)/\(credentialScope)",
            "X-Amz-Date": datetime,
            "X-Amz-SignedHeaders": "host"
        ]

        // Add any additional parameters (like channel ARN, client ID)
        for (key, value) in additionalParams {
            queryParams[key] = value
        }

        // Create canonical query string
        let canonicalQuerystring = queryParams.keys.sorted().map { key in
            "\(key)=\(percentEncode(queryParams[key]!))"
        }.joined(separator: "&")

        // Create canonical headers
        let canonicalHeaders = "host:\(endpoint)\n"

        // Create payload hash (empty for WebSocket)
        let payloadHash = sha256("")

        // Create canonical request
        let canonicalRequest = "\(method)\n\(uri)\n\(canonicalQuerystring)\n\(canonicalHeaders)\nhost\n\(payloadHash)"

        // Create string to sign
        let stringToSign = "\(algorithm)\n\(datetime)\n\(credentialScope)\n\(sha256(canonicalRequest))"

        // Calculate signature
        let signingKey = getSignatureKey(key: secretKey, dateStamp: date, regionName: region, serviceName: service)
        let signature = hmacSHA256(stringToSign: stringToSign, key: signingKey)

        // Add signature to query params
        queryParams["X-Amz-Signature"] = signature

        // Create final query string
        let finalQuerystring = queryParams.keys.sorted().map { key in
            "\(key)=\(percentEncode(queryParams[key]!))"
        }.joined(separator: "&")

        return URL(string: "wss://\(endpoint)\(uri)?\(finalQuerystring)")
    }

    private func getSignatureKey(key: String, dateStamp: String, regionName: String, serviceName: String) -> Data {
        let kDate = hmacSHA256Data(stringToSign: dateStamp, key: ("AWS4" + key).data(using: .utf8)!)
        let kRegion = hmacSHA256Data(stringToSign: regionName, key: kDate)
        let kService = hmacSHA256Data(stringToSign: serviceName, key: kRegion)
        let kSigning = hmacSHA256Data(stringToSign: "aws4_request", key: kService)
        return kSigning
    }

    private func hmacSHA256(stringToSign: String, key: Data) -> String {
        let signature = hmacSHA256Data(stringToSign: stringToSign, key: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacSHA256Data(stringToSign: String, key: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: symmetricKey)
        return Data(signature)
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func percentEncode(_ string: String) -> String {
        var allowedCharacters = CharacterSet.alphanumerics
        allowedCharacters.insert(charactersIn: "-_.~")
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
    }
}
