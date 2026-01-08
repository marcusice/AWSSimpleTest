//
//  KVSWebRTCManager.swift
//  AWSSimpleTest
//
//  AWS Kinesis Video Streams WebRTC manager for viewer functionality
//

import Foundation
import WebRTC
import AWSCore
import AWSKinesisVideo
import AWSKinesisVideoSignaling
import AVFoundation

class KVSWebRTCManager: NSObject, ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var remoteVideoTrack: RTCVideoTrack?

    private var configuration: KVSConfiguration
    private var peerConnection: RTCPeerConnection?
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var iceServers: [RTCIceServer] = []
    private var masterResponseTimer: Task<Void, Never>?
    private var receivedAnswer = false
    private var pendingIceCandidates: [[String: Any]] = []
    private var remoteDescriptionSet = false

    // WebRTC Factory
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
    }()

    init(configuration: KVSConfiguration) {
        self.configuration = configuration
        super.init()

        // CRITICAL AUDIO FIX - Configure audio session for viewer-only mode
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.useManualAudio = true
        audioSession.isAudioEnabled = false

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            audioSession.isAudioEnabled = true
            print("[KVS] Audio Session set to .playback (Viewer Mode)")
        } catch {
            print("[KVS] Audio config failed: \(error)")
        }

        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func startStream() {
        connectionStatus = .connecting
        Task {
            await connectToKVS()
        }
    }

    func stopStream() {
        cleanup()
        connectionStatus = .disconnected
    }

    private func connectToKVS() async {
        do {
            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = .connecting
            }

            // Configure AWS credentials
            let credentialsProvider = AWSStaticCredentialsProvider(
                accessKey: configuration.accessKey,
                secretKey: configuration.secretKey
            )

            let awsConfiguration = AWSServiceConfiguration(
                region: regionType(from: configuration.region),
                credentialsProvider: credentialsProvider
            )

            AWSServiceManager.default().defaultServiceConfiguration = awsConfiguration

            let kinesisVideoClient = AWSKinesisVideo.default()

            // Get signaling channel endpoints
            let endpointRequest = AWSKinesisVideoGetSignalingChannelEndpointInput()!
            endpointRequest.channelARN = configuration.channelARN

            let singleMasterConfig = AWSKinesisVideoSingleMasterChannelEndpointConfiguration()!
            singleMasterConfig.protocols = ["WSS", "HTTPS"]
            singleMasterConfig.role = .viewer
            endpointRequest.singleMasterChannelEndpointConfiguration = singleMasterConfig

            let endpointResponse = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AWSKinesisVideoGetSignalingChannelEndpointOutput, Error>) in
                kinesisVideoClient.getSignalingChannelEndpoint(endpointRequest).continueWith { task in
                    if let error = task.error {
                        continuation.resume(throwing: error)
                    } else if let result = task.result {
                        continuation.resume(returning: result)
                    }
                    return nil
                }
            }

            var httpsEndpoint: String?
            var wssEndpoint: String?

            for endpoint in endpointResponse.resourceEndpointList as? [AWSKinesisVideoResourceEndpointListItem] ?? [] {
                if endpoint.protocols == .https {
                    httpsEndpoint = endpoint.resourceEndpoint
                } else if endpoint.protocols == .wss {
                    wssEndpoint = endpoint.resourceEndpoint
                }
            }

            guard let httpsEndpoint = httpsEndpoint, let wssEndpoint = wssEndpoint else {
                throw NSError(domain: "KVS", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get endpoints"])
            }

            // Create signaling client configuration with custom endpoint
            let endpoint = AWSEndpoint(region: regionType(from: configuration.region), service: .KinesisVideoSignaling, url: URL(string: httpsEndpoint))
            let signalingConfig = AWSServiceConfiguration(
                region: regionType(from: configuration.region),
                endpoint: endpoint,
                credentialsProvider: credentialsProvider
            )

            AWSKinesisVideoSignaling.register(with: signalingConfig!, forKey: "SignalingClient")

            let signalingClient = AWSKinesisVideoSignaling(forKey: "SignalingClient")

            // Get ICE server configuration
            let iceRequest = AWSKinesisVideoSignalingGetIceServerConfigRequest()!
            iceRequest.channelARN = configuration.channelARN

            let iceResponse = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AWSKinesisVideoSignalingGetIceServerConfigResponse, Error>) in
                signalingClient.getIceServerConfig(iceRequest).continueWith { task in
                    if let error = task.error {
                        continuation.resume(throwing: error)
                    } else if let result = task.result {
                        continuation.resume(returning: result)
                    }
                    return nil
                }
            }

            // Build ICE servers list
            var iceServers: [RTCIceServer] = []

            // Add STUN server
            let stunServer = RTCIceServer(
                urlStrings: ["stun:stun.kinesisvideo.\(configuration.region).amazonaws.com:443"]
            )
            iceServers.append(stunServer)

            // Add TURN servers
            for iceServer in iceResponse.iceServerList as? [AWSKinesisVideoSignalingIceServer] ?? [] {
                if let uris = iceServer.uris as? [String], let username = iceServer.username, let password = iceServer.password {
                    let turnServer = RTCIceServer(
                        urlStrings: uris,
                        username: username,
                        credential: password
                    )
                    iceServers.append(turnServer)
                }
            }

            self.iceServers = iceServers

            // Create peer connection
            await createPeerConnection()

            // Connect to signaling channel via WebSocket
            await connectToSignalingWebSocket(endpoint: wssEndpoint)

        } catch {
            print("[KVS] Error: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = .error(error.localizedDescription)
            }
        }
    }

    private func createPeerConnection() async {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.iceTransportPolicy = .all
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )

        peerConnection = Self.factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )

        // --- 1. Add Video Transceiver (First) ---
        let videoInit = RTCRtpTransceiverInit()
        videoInit.direction = .recvOnly
        peerConnection?.addTransceiver(of: .video, init: videoInit)

        // --- 2. Add Audio Transceiver (Second) ---
        let audioInit = RTCRtpTransceiverInit()
        audioInit.direction = .recvOnly
        peerConnection?.addTransceiver(of: .audio, init: audioInit)

        print("[KVS] Peer connection created (Video:0, Audio:1)")
    }

    // Helper: Force H.264 Constrained Baseline Profile (42e01f) in SDP
    // Note: WebRTC v125 doesn't support the setCodecPreferences API properly, so we use SDP manipulation
    private func forceH264BaselineProfile(_ sdp: String) -> String {
        var newSdp = sdp
        // Simple regex: find "profile-level-id=" followed by any hex digits
        // This matches regardless of position in the SDP line
        let pattern = "profile-level-id=[0-9a-fA-F]+"

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: newSdp.utf16.count)

            // Find all matches to log what we're replacing
            let matches = regex.matches(in: newSdp, options: [], range: range)
            for match in matches {
                if let matchRange = Range(match.range, in: newSdp) {
                    let oldValue = String(newSdp[matchRange])
                    print("[KVS] Found H.264 profile in SDP: \(oldValue)")
                }
            }

            // Replace all profile-level-id values with 42e01f (Constrained Baseline Profile, Level 3.1)
            newSdp = regex.stringByReplacingMatches(in: newSdp, options: [], range: range, withTemplate: "profile-level-id=42e01f")

            if matches.count > 0 {
                print("[KVS] 🔧 Forced \(matches.count) H.264 profile(s) to Constrained Baseline (42e01f)")
            } else {
                print("[KVS] ⚠️ No H.264 profile-level-id found in SDP")
            }
        } catch {
            print("[KVS] ❌ Regex error: \(error)")
        }

        return newSdp
    }

    private var clientId: String = ""

    private func connectToSignalingWebSocket(endpoint: String) async {
        // Build signed WebSocket URL for KVS signaling
        clientId = "viewer-\(UUID().uuidString.prefix(8).uppercased())"
        print("[KVS] Connecting with client ID: \(clientId)")

        // For KVS WebRTC, we need to use AWS SigV4 signing for the WebSocket connection
        guard let wsURL = buildKVSWebSocketURL(endpoint: endpoint, clientId: clientId) else {
            print("[KVS] Failed to build signed WebSocket URL")
            DispatchQueue.main.async { [weak self] in
                self?.connectionStatus = .error("Failed to create WebSocket URL")
            }
            return
        }

        print("[KVS] Connecting to signed WebSocket URL: \(wsURL.absoluteString)")

        let request = URLRequest(url: wsURL)
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()

        print("[KVS] WebSocket task created and resumed")

        // Start receiving signaling messages
        receiveSignalingMessage()

        // Wait for connection to establish
        print("[KVS] Waiting 1 second for connection...")
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Create and send SDP offer
        print("[KVS] Creating and sending SDP offer...")
        await sendOffer()
    }

    private func buildKVSWebSocketURL(endpoint: String, clientId: String) -> URL? {
        // Parse the endpoint URL to extract host and path
        guard let url = URL(string: endpoint) else {
            print("[KVS] Failed to parse endpoint URL: \(endpoint)")
            return nil
        }

        let host = url.host ?? ""
        let path = url.path.isEmpty ? "/" : url.path

        print("[KVS] Endpoint host: \(host), path: \(path)")

        // Create SigV4 signer for Kinesis Video service
        let signer = AWSSigV4Signer(
            accessKey: configuration.accessKey,
            secretKey: configuration.secretKey,
            region: configuration.region,
            service: "kinesisvideo"
        )

        // Sign the WebSocket URL with channel ARN and client ID
        let additionalParams: [String: String] = [
            "X-Amz-ChannelARN": configuration.channelARN,
            "X-Amz-ClientId": clientId
        ]

        return signer.signWebSocketURL(endpoint: host, uri: path, additionalParams: additionalParams)
    }

    private func sendOffer() async {
        guard let peerConnection = peerConnection else { return }

        do {
            // No legacy constraints needed for Offer, transceivers handle it
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: nil
            )

            let offer = try await peerConnection.offer(for: constraints)

            // Force H.264 Baseline Profile in SDP (WebRTC v125 compatible approach)
            let forcedSdp = forceH264BaselineProfile(offer.sdp)
            let fixedOffer = RTCSessionDescription(type: .offer, sdp: forcedSdp)

            // Set the modified offer as local description
            try await peerConnection.setLocalDescription(fixedOffer)

            // Prepare JSON payload
            let sdpJson: [String: Any] = [
                "type": "offer",
                "sdp": fixedOffer.sdp
            ]

            guard let sdpJsonData = try? JSONSerialization.data(withJSONObject: sdpJson, options: []),
                  let base64Payload = sdpJsonData.base64EncodedString() as String? else {
                print("[KVS] ❌ Failed to encode SDP JSON to Base64")
                return
            }

            let offerMessage: [String: Any] = [
                "action": "SDP_OFFER",
                "recipientClientId": NSNull(),
                "messagePayload": base64Payload
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: offerMessage),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                sendSignalingMessage(jsonString)
                print("[KVS] Sent SDP offer (Native Baseline)")
                startMasterResponseTimer()
            }

        } catch {
            print("[KVS] Error creating offer: \(error)")
        }
    }

    private func startMasterResponseTimer() {
        masterResponseTimer?.cancel()
        masterResponseTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds

            guard let self = self, !self.receivedAnswer else { return }

            print("[KVS] ⏰ No response from master device after 10 seconds")
            DispatchQueue.main.async {
                self.connectionStatus = .error("Waiting for master device to connect...")
            }
        }
    }

    private func sendSignalingMessage(_ message: String) {
        // Log first 200 chars and last 50 chars to see structure without flooding logs
        let preview = message.count > 250
            ? "\(message.prefix(200))...\(message.suffix(50))"
            : message
        print("[KVS] 📤 Sending message (\(message.count) bytes): \(preview)")

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocket?.send(wsMessage) { error in
            if let error = error {
                print("[KVS] ❌ WebSocket send error: \(error)")
            } else {
                print("[KVS] ✅ Message sent successfully")
            }
        }
    }

    private func receiveSignalingMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                print("[KVS] Received WebSocket message")
                self?.handleSignalingMessage(message)
                self?.receiveSignalingMessage() // Continue receiving
            case .failure(let error):
                print("[KVS] WebSocket receive error: \(error)")
            }
        }
    }

    private func handleSignalingMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            // Handle empty messages (keepalives/acknowledgments from server)
            if text.isEmpty || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("[KVS] Received empty message (keepalive)")
                return
            }

            print("[KVS] Received text message: \(text)")
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[KVS] Failed to parse JSON from message")
                return
            }

            print("[KVS] Parsed JSON: \(json)")

            // Handle AWS KVS Signaling format with Base64 decoding
            if let action = json["action"] as? String {
                print("[KVS] Received action: \(action)")
                switch action {
                case "SDP_ANSWER":
                    print("[KVS] 🎉 Received SDP_ANSWER from master!")
                    // Decode Base64 payload
                    if let base64Payload = json["messagePayload"] as? String,
                       let payloadData = Data(base64Encoded: base64Payload),
                       let sdpString = String(data: payloadData, encoding: .utf8) {
                        handleSdpAnswer(sdpString)
                    } else {
                        print("[KVS] ❌ Failed to decode Base64 SDP answer")
                    }
                case "ICE_CANDIDATE":
                    print("[KVS] Received ICE_CANDIDATE from master")
                    // Decode Base64 payload
                    if let base64Payload = json["messagePayload"] as? String,
                       let payloadData = Data(base64Encoded: base64Payload),
                       let candidateJson = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                        handleIceCandidate(candidateJson)
                    } else {
                        print("[KVS] ❌ Failed to decode Base64 ICE candidate")
                    }
                default:
                    print("[KVS] Unknown action: \(action)")
                }
            } else if let messageType = json["messageType"] as? String {
                // Master uses "messageType" with Base64-encoded payloads
                print("[KVS] Received messageType: \(messageType)")
                switch messageType {
                case "SDP_ANSWER":
                    print("[KVS] 🎉 Received SDP_ANSWER from master!")
                    // Decode Base64 payload to get JSON with {"type":"answer","sdp":"..."}
                    if let base64Payload = json["messagePayload"] as? String,
                       let payloadData = Data(base64Encoded: base64Payload),
                       let answerJson = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                       let sdpString = answerJson["sdp"] as? String {
                        handleSdpAnswer(sdpString)
                    } else {
                        print("[KVS] ❌ Failed to decode Base64 SDP answer from messageType")
                    }
                case "ICE_CANDIDATE":
                    print("[KVS] Received ICE_CANDIDATE from master")
                    // Decode Base64 payload to get candidate JSON
                    if let base64Payload = json["messagePayload"] as? String,
                       let payloadData = Data(base64Encoded: base64Payload),
                       let candidateJson = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] {
                        handleIceCandidate(candidateJson)
                    } else {
                        print("[KVS] ❌ Failed to decode Base64 ICE candidate from messageType")
                    }
                default:
                    print("[KVS] Unknown messageType: \(messageType)")
                }
            } else if let type = json["type"] as? String {
                // Direct WebRTC format (fallback)
                print("[KVS] Received WebRTC type: \(type)")
                if type == "answer", let sdp = json["sdp"] as? String {
                    handleSdpAnswer(sdp)
                }
            } else if json["candidate"] != nil {
                // Direct ICE candidate (fallback)
                handleIceCandidate(json)
            } else {
                print("[KVS] ❌ Unrecognized message format in JSON")
            }
        case .data(let data):
            print("[KVS] Received binary data: \(data.count) bytes")
        @unknown default:
            print("[KVS] Received unknown message type")
        }
    }

    private func handleSdpAnswer(_ sdp: String) {
        print("[KVS] 🎉 Received SDP answer from master device!")
        receivedAnswer = true
        masterResponseTimer?.cancel()

        let answer = RTCSessionDescription(type: .answer, sdp: sdp)
        peerConnection?.setRemoteDescription(answer) { [weak self] error in
            if let error = error {
                print("[KVS] Error setting remote description: \(error)")
            } else {
                print("[KVS] ✅ Remote description set successfully - negotiation complete")
                self?.remoteDescriptionSet = true

                // Add any pending ICE candidates that arrived before the answer
                if let pending = self?.pendingIceCandidates, !pending.isEmpty {
                    print("[KVS] Adding \(pending.count) buffered ICE candidates")
                    for candidateDict in pending {
                        self?.addIceCandidate(candidateDict)
                    }
                    self?.pendingIceCandidates.removeAll()
                }
            }
        }
    }

    private func handleIceCandidate(_ candidateDict: [String: Any]) {
        // Buffer candidates if remote description not yet set
        if !remoteDescriptionSet {
            print("[KVS] Buffering ICE candidate (remote description not set yet)")
            pendingIceCandidates.append(candidateDict)
            return
        }

        // Remote description is set, add candidate immediately
        addIceCandidate(candidateDict)
    }

    private func addIceCandidate(_ candidateDict: [String: Any]) {
        guard let candidate = candidateDict["candidate"] as? String,
              let sdpMid = candidateDict["sdpMid"] as? String else {
            print("[KVS] Invalid ICE candidate format: missing candidate or sdpMid")
            return
        }

        // Parse sdpMLineIndex - it comes from JSON as Int, convert to Int32 for RTCIceCandidate
        guard let sdpMLineIndexInt = candidateDict["sdpMLineIndex"] as? Int else {
            print("[KVS] Invalid ICE candidate format: sdpMLineIndex not an Int")
            return
        }
        let sdpMLineIndex = Int32(sdpMLineIndexInt)

        // Log candidate type for debugging
        let candidateType = candidate.contains("typ host") ? "host" :
                           candidate.contains("typ srflx") ? "srflx" :
                           candidate.contains("typ relay") ? "relay" : "unknown"
        print("[KVS] Adding master ICE candidate (\(candidateType)): \(candidate.prefix(80))...")

        let iceCandidate = RTCIceCandidate(
            sdp: candidate,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )

        peerConnection?.add(iceCandidate) { error in
            if let error = error {
                print("[KVS] Error adding ICE candidate: \(error)")
            } else {
                print("[KVS] ✅ Master ICE candidate added successfully")
            }
        }
    }

    private func cleanup() {
        masterResponseTimer?.cancel()
        masterResponseTimer = nil
        receivedAnswer = false
        remoteDescriptionSet = false
        pendingIceCandidates.removeAll()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        peerConnection?.close()
        peerConnection = nil
        remoteVideoTrack = nil
    }

    private func regionType(from regionString: String) -> AWSRegionType {
        switch regionString {
        case "us-east-1": return .USEast1
        case "us-west-2": return .USWest2
        case "us-west-1": return .USWest1
        case "eu-west-1": return .EUWest1
        case "ap-southeast-1": return .APSoutheast1
        default: return .USWest2
        }
    }
}

// MARK: - RTCPeerConnectionDelegate
extension KVSWebRTCManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("[KVS] Signaling state: \(stateChanged.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("[KVS] Added stream with \(stream.videoTracks.count) video tracks and \(stream.audioTracks.count) audio tracks")
        if let videoTrack = stream.videoTracks.first {
            print("[KVS] Video track details - trackId: \(videoTrack.trackId), enabled: \(videoTrack.isEnabled), readyState: \(videoTrack.readyState.rawValue)")

            // Enable the video track explicitly
            videoTrack.isEnabled = true

            DispatchQueue.main.async { [weak self] in
                self?.remoteVideoTrack = videoTrack
                self?.connectionStatus = .connected
                print("[KVS] Video track assigned to UI, enabled: \(videoTrack.isEnabled)")
            }
        } else {
            print("[KVS] ⚠️ No video track found in stream!")
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("[KVS] Removed stream")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("[KVS] Should negotiate")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let stateDescription: String
        switch newState {
        case .new:
            stateDescription = "new (gathering candidates)"
        case .checking:
            stateDescription = "checking (trying to connect)"
        case .connected:
            stateDescription = "connected ✅"
        case .completed:
            stateDescription = "completed ✅"
        case .failed:
            stateDescription = "failed ❌"
        case .disconnected:
            stateDescription = "disconnected"
        case .closed:
            stateDescription = "closed"
        case .count:
            stateDescription = "count"
        @unknown default:
            stateDescription = "unknown"
        }
        print("[KVS] ICE connection state changed: \(stateDescription)")

        DispatchQueue.main.async { [weak self] in
            switch newState {
            case .connected, .completed:
                print("[KVS] 🎉 ICE connection established!")
                self?.connectionStatus = .connected
            case .disconnected, .failed, .closed:
                print("[KVS] ICE connection lost or failed")
                if self?.connectionStatus.isConnected == true {
                    self?.connectionStatus = .disconnected
                }
            case .checking:
                print("[KVS] ICE checking - attempting to establish connection")
            default:
                break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("[KVS] ICE gathering state: \(newState.rawValue)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // Extract candidate type and IP for debugging
        let candidateStr = candidate.sdp
        let candidateType = candidateStr.contains("typ host") ? "host" :
                           candidateStr.contains("typ srflx") ? "srflx" :
                           candidateStr.contains("typ relay") ? "relay" : "unknown"
        print("[KVS] Generated ICE candidate (\(candidateType)): \(candidateStr.prefix(80))...")

        // Send ICE candidate through signaling (AWS KVS Signaling format with Base64 encoding)
        // CRITICAL: The candidate JSON must be Base64 encoded!

        // Build the candidate JSON
        // CRITICAL: Ensure sdpMLineIndex is sent as Int, not Int32
        // CRITICAL: sdpMid should default to "0" if nil
        let candidateJson: [String: Any] = [
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "0",
            "sdpMLineIndex": Int(candidate.sdpMLineIndex)
        ]

        // Serialize to JSON -> Data -> Base64
        guard let jsonData = try? JSONSerialization.data(withJSONObject: candidateJson, options: []) else {
            print("[KVS] ❌ Failed to serialize ICE candidate JSON")
            return
        }

        let base64Candidate = jsonData.base64EncodedString()

        // Construct KVS Signaling message
        let candidateMessage: [String: Any] = [
            "action": "ICE_CANDIDATE",
            "recipientClientId": NSNull(), // null for viewer -> master
            "messagePayload": base64Candidate
        ]

        if let messageData = try? JSONSerialization.data(withJSONObject: candidateMessage),
           let messageString = String(data: messageData, encoding: .utf8) {
            sendSignalingMessage(messageString)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("[KVS] Removed ICE candidates")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("[KVS] Opened data channel")
    }
}

// MARK: - URLSessionWebSocketDelegate
extension KVSWebRTCManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol `protocol`: String?) {
        print("[KVS] ✅ WebSocket connected successfully with protocol: \(`protocol` ?? "none")")
        print("[KVS] WebSocket state: \(webSocketTask.state.rawValue)")
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        print("[KVS] ❌ WebSocket disconnected: code=\(closeCode.rawValue), reason=\(reasonString)")
        DispatchQueue.main.async { [weak self] in
            if self?.connectionStatus.isConnected == true {
                self?.connectionStatus = .disconnected
            }
        }
    }
}
