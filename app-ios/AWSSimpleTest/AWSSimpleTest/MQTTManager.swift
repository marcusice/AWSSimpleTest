//
//  MQTTManager.swift
//  AWSSimpleTest
//
//  MQTT WebSocket manager with auto-reconnect functionality
//

import Foundation
import Combine

class MQTTManager: NSObject, ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var messages: [MQTTMessage] = []

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var configuration: MQTTConfiguration
    private var signer: AWSSigV4Signer?
    private var reconnectTimer: Timer?
    private var manualDisconnect = false
    private let reconnectDelay: TimeInterval = 5.0

    // MQTT protocol state
    private var clientId: String
    private var subscribeTopics: [String]
    private var keepAliveTimer: Timer?

    init(configuration: MQTTConfiguration) {
        self.configuration = configuration
        self.clientId = "mqtt-client-\(UUID().uuidString.prefix(8))"
        self.subscribeTopics = configuration.subscribeTopics
        super.init()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func connect() {
        manualDisconnect = false
        connectionStatus = .connecting
        addSystemMessage("Connecting to AWS IoT...")

        // Create SigV4 signer
        signer = AWSSigV4Signer(
            accessKey: configuration.accessKey,
            secretKey: configuration.secretKey,
            region: configuration.region
        )

        guard let signedURL = signer?.signWebSocketURL(endpoint: configuration.endpoint) else {
            connectionStatus = .error("Failed to sign URL")
            addSystemMessage("Failed to create signed URL")
            return
        }

        // Create WebSocket connection with proper headers
        var request = URLRequest(url: signedURL)
        request.addValue("mqtt", forHTTPHeaderField: "Sec-WebSocket-Protocol")

        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()

        // Start receiving messages
        receiveMessage()

        // Send MQTT CONNECT packet
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sendConnectPacket()
        }
    }

    func disconnect() {
        manualDisconnect = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil

        sendDisconnectPacket()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        connectionStatus = .disconnected
        addSystemMessage("Manually disconnected")
    }

    func publish(topic: String, message: String) {
        guard connectionStatus.isConnected else {
            addSystemMessage("Cannot publish: Not connected")
            return
        }

        let publishPacket = createPublishPacket(topic: topic, message: message)
        sendData(publishPacket)
        addMessage(topic: topic, message: "[SENT] \(message)", isSystem: false)
    }

    private func sendConnectPacket() {
        var packet = Data()

        // Fixed header: CONNECT (0x10)
        packet.append(0x10)

        // Variable header
        var variableHeader = Data()

        // Protocol name: "MQTT"
        variableHeader.append(contentsOf: [0x00, 0x04]) // Length
        variableHeader.append(contentsOf: "MQTT".utf8)

        // Protocol level: 4 (MQTT 3.1.1)
        variableHeader.append(0x04)

        // Connect flags: Clean session
        variableHeader.append(0x02)

        // Keep alive: 60 seconds
        variableHeader.append(contentsOf: [0x00, 0x3C])

        // Payload: Client ID
        var payload = Data()
        let clientIdData = clientId.utf8
        payload.append(UInt8((clientIdData.count >> 8) & 0xFF))
        payload.append(UInt8(clientIdData.count & 0xFF))
        payload.append(contentsOf: clientIdData)

        // Remaining length
        let remainingLength = variableHeader.count + payload.count
        packet.append(UInt8(remainingLength))

        packet.append(variableHeader)
        packet.append(payload)

        sendData(packet)
        addSystemMessage("Sent CONNECT packet")
    }

    private func sendSubscribePacket() {
        for topic in subscribeTopics {
            var packet = Data()

            // Fixed header: SUBSCRIBE (0x82)
            packet.append(0x82)

            // Variable header
            var variableHeader = Data()

            // Packet identifier
            variableHeader.append(contentsOf: [0x00, 0x01])

            // Payload
            var payload = Data()
            let topicData = topic.utf8
            payload.append(UInt8((topicData.count >> 8) & 0xFF))
            payload.append(UInt8(topicData.count & 0xFF))
            payload.append(contentsOf: topicData)
            payload.append(0x00) // QoS 0

            // Remaining length
            let remainingLength = variableHeader.count + payload.count
            packet.append(UInt8(remainingLength))

            packet.append(variableHeader)
            packet.append(payload)

            sendData(packet)
            addSystemMessage("Subscribed to \(topic)")
        }
    }

    private func sendDisconnectPacket() {
        var packet = Data()
        packet.append(0xE0) // DISCONNECT
        packet.append(0x00) // Remaining length
        sendData(packet)
    }

    private func createPublishPacket(topic: String, message: String) -> Data {
        var packet = Data()

        // Fixed header: PUBLISH QoS 0 (0x30)
        packet.append(0x30)

        // Variable header
        var variableHeader = Data()
        let topicData = topic.utf8
        variableHeader.append(UInt8((topicData.count >> 8) & 0xFF))
        variableHeader.append(UInt8(topicData.count & 0xFF))
        variableHeader.append(contentsOf: topicData)

        // Payload
        let payload = Data(message.utf8)

        // Remaining length
        let remainingLength = variableHeader.count + payload.count
        packet.append(UInt8(remainingLength))

        packet.append(variableHeader)
        packet.append(payload)

        return packet
    }

    private func sendData(_ data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocket?.send(message) { [weak self] error in
            if let error = error {
                print("WebSocket send error: \(error)")
                self?.addSystemMessage("Send error: \(error.localizedDescription)")
            }
        }
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleWebSocketMessage(message)
                self?.receiveMessage() // Continue receiving
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                self?.handleConnectionLoss()
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            parseMQTTPacket(data)
        case .string(let text):
            print("Received text message: \(text)")
        @unknown default:
            break
        }
    }

    private func parseMQTTPacket(_ data: Data) {
        guard !data.isEmpty else { return }

        let packetType = (data[0] >> 4) & 0x0F

        switch packetType {
        case 0x02: // CONNACK
            handleConnack(data)
        case 0x03: // PUBLISH
            handlePublish(data)
        case 0x09: // SUBACK
            addSystemMessage("Subscription confirmed")
        case 0x0D: // PINGRESP
            break // Keep-alive response
        default:
            print("Received packet type: 0x\(String(format: "%02X", packetType))")
        }
    }

    private func handleConnack(_ data: Data) {
        guard data.count >= 4 else { return }

        let returnCode = data[3]
        if returnCode == 0x00 {
            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = .connected
                self?.addSystemMessage("Connected to AWS IoT")
                self?.sendSubscribePacket()
                self?.startKeepAlive()
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = .error("Connection refused: \(returnCode)")
                self?.addSystemMessage("Connection refused: code \(returnCode)")
            }
        }
    }

    private func handlePublish(_ data: Data) {
        guard data.count > 2 else { return }

        var index = 1

        // Read remaining length
        var remainingLength = 0
        var multiplier = 1
        var byte: UInt8 = 0
        repeat {
            byte = data[index]
            remainingLength += Int(byte & 0x7F) * multiplier
            multiplier *= 128
            index += 1
        } while (byte & 0x80) != 0

        // Read topic length
        guard index + 1 < data.count else { return }
        let topicLength = Int(data[index]) << 8 | Int(data[index + 1])
        index += 2

        // Read topic
        guard index + topicLength <= data.count else { return }
        let topicData = data[index..<(index + topicLength)]
        guard let topic = String(data: topicData, encoding: .utf8) else { return }
        index += topicLength

        // Read message
        let messageData = data[index...]
        guard let message = String(data: messageData, encoding: .utf8) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.addMessage(topic: topic, message: message, isSystem: false)
        }
    }

    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.sendPingReq()
        }
    }

    private func sendPingReq() {
        var packet = Data()
        packet.append(0xC0) // PINGREQ
        packet.append(0x00) // Remaining length
        sendData(packet)
    }

    private func handleConnectionLoss() {
        guard !manualDisconnect else { return }

        DispatchQueue.main.async { [weak self] in
            self?.connectionStatus = .reconnecting
            self?.addSystemMessage("Connection lost - Reconnecting...")

            self?.reconnectTimer = Timer.scheduledTimer(withTimeInterval: self?.reconnectDelay ?? 5.0, repeats: false) { [weak self] _ in
                self?.connect()
            }
        }
    }

    private func addMessage(topic: String, message: String, isSystem: Bool) {
        let mqttMessage = MQTTMessage(
            timestamp: Date(),
            topic: topic,
            message: message,
            isSystem: isSystem
        )
        DispatchQueue.main.async { [weak self] in
            self?.messages.insert(mqttMessage, at: 0)
        }
    }

    private func addSystemMessage(_ message: String) {
        let mqttMessage = MQTTMessage(
            timestamp: Date(),
            topic: "",
            message: message,
            isSystem: true
        )
        DispatchQueue.main.async { [weak self] in
            self?.messages.insert(mqttMessage, at: 0)
        }
    }

    func clearMessages() {
        messages.removeAll()
    }
}

// MARK: - URLSessionWebSocketDelegate
extension MQTTManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("WebSocket connected")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("WebSocket disconnected: \(closeCode)")
        handleConnectionLoss()
    }
}
