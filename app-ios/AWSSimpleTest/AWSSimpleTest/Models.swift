//
//  Models.swift
//  AWSSimpleTest
//
//  Data models for MQTT messages and configuration
//

import Foundation

struct MQTTMessage: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let topic: String
    let message: String
    let isSystem: Bool

    var timestampString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
}

struct MQTTConfiguration {
    var endpoint: String
    var region: String
    var accessKey: String
    var secretKey: String
    var subscribeTopics: [String]
    var publishTopic: String
    var filter1: String
    var filter2: String

    static let `default` = MQTTConfiguration(
        endpoint: "YOUR_IOT_ENDPOINT.iot.us-west-2.amazonaws.com",
        region: "us-west-2",
        accessKey: "YOUR_AWS_ACCESS_KEY",
        secretKey: "YOUR_AWS_SECRET_KEY",
        subscribeTopics: [
            "cmd/YOUR_DEVICE/#",
            "dt/iot/YOUR_DEVICE/#"
        ],
        publishTopic: "cmd/YOUR_DEVICE/req",
        filter1: "dt/iot/YOUR_DEVICE/res",
        filter2: "cmd/YOUR_DEVICE/req"
    )
}

struct KVSConfiguration {
    var channelName: String
    var channelARN: String
    var region: String
    var accessKey: String
    var secretKey: String

    static let `default` = KVSConfiguration(
        channelName: "YOUR_CHANNEL_NAME",
        channelARN: "arn:aws:kinesisvideo:us-west-2:YOUR_ACCOUNT_ID:channel/YOUR_CHANNEL_NAME/TIMESTAMP",
        region: "us-west-2",
        accessKey: "YOUR_AWS_ACCESS_KEY",
        secretKey: "YOUR_AWS_SECRET_KEY"
    )
}

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(String)

    var displayString: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .reconnecting:
            return "Reconnecting..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}
