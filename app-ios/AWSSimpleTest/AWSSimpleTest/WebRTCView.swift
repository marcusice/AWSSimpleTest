//
//  WebRTCView.swift
//  AWSSimpleTest
//
//  WebRTC streaming view with video player
//

import SwiftUI
import WebRTC

struct WebRTCView: View {
    @ObservedObject var manager: KVSWebRTCManager
    @State private var channelName = "Marcus_0DB3E2_2"
    @State private var channelARN = "arn:aws:kinesisvideo:us-west-2:663530036664:channel/Marcus_0DB3E2_2/1756483251274"
    @State private var region = "us-west-2"

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status
                    connectionStatusView

                    // Configuration Section
                    configurationSectionView

                    // Video Player
                    videoPlayerView

                    // Controls
                    controlButtonsView
                }
                .padding()
            }
            .navigationTitle("AWS KVS WebRTC")
        }
    }

    private var connectionStatusView: some View {
        HStack {
            Circle()
                .fill(manager.connectionStatus.isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            Text(manager.connectionStatus.displayString)
                .font(.headline)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(manager.connectionStatus.isConnected ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        )
    }

    private var configurationSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KVS Configuration")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Channel Name:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Channel Name", text: $channelName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(manager.connectionStatus.isConnected)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Channel ARN:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Channel ARN", text: $channelARN)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(manager.connectionStatus.isConnected)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Region:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Region", text: $region)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .disabled(manager.connectionStatus.isConnected)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemGray6))
        )
    }

    private var videoPlayerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Video Stream")
                .font(.headline)

            if let videoTrack = manager.remoteVideoTrack {
                RTCVideoPlayerView(videoTrack: videoTrack)
                    .frame(height: 300)
                    .background(Color.black)
                    .cornerRadius(12)
            } else {
                ZStack {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 300)
                        .cornerRadius(12)

                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)

                        if case .connecting = manager.connectionStatus {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text("Connecting to stream...")
                                .foregroundColor(.gray)
                                .font(.subheadline)
                        } else if case .error(let message) = manager.connectionStatus {
                            Text("Error: \(message)")
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding()
                        } else {
                            Text("No Video Stream")
                                .foregroundColor(.gray)
                                .font(.headline)
                            Text("Tap 'Start Stream' to begin")
                                .foregroundColor(.gray.opacity(0.7))
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var controlButtonsView: some View {
        HStack(spacing: 12) {
            Button("Start Stream") {
                manager.startStream()
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.connectionStatus.isConnected ||
                     manager.connectionStatus == .connecting)

            Button("Stop Stream") {
                manager.stopStream()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(!manager.connectionStatus.isConnected)
        }
    }
}

// MARK: - RTCVideoPlayerView (Metal Version - Fixed)
struct RTCVideoPlayerView: UIViewRepresentable {
    let videoTrack: RTCVideoTrack

    func makeCoordinator() -> Coordinator {
        Coordinator(videoTrack: videoTrack)
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        // 1. Init with a non-zero frame to ensure Metal context is created
        let videoView = RTCMTLVideoView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        // 2. Critical Configuration for KVS
        videoView.videoContentMode = .scaleAspectFit
        videoView.backgroundColor = .black // Black means "view loaded"

        // 3. Set Delegate BEFORE adding track
        videoView.delegate = context.coordinator

        // 4. Add Track
        videoTrack.add(videoView)

        return videoView
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        // Only update if the track has actually changed
        if context.coordinator.videoTrack != videoTrack {
            print("[UI] Video track changed, updating view")
            context.coordinator.videoTrack.remove(uiView)
            context.coordinator.videoTrack = videoTrack
            videoTrack.add(uiView)
        }
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.videoTrack.remove(uiView)
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, RTCVideoViewDelegate {
        var videoTrack: RTCVideoTrack

        init(videoTrack: RTCVideoTrack) {
            self.videoTrack = videoTrack
        }

        // This is the "Heartbeat" of the video. If this doesn't fire, no video is decoding.
        func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
            print("[KVS] 🎞️ FIRST FRAME RECEIVED! Size: \(size.width)x\(size.height)")

            DispatchQueue.main.async {
                guard let metalView = videoView as? RTCMTLVideoView else { return }

                // FORCE LAYOUT UPDATE
                // Sometimes Metal views get stuck at 0x0 size internally.
                // This forces SwiftUI/AutoLayout to recalculate bounds.
                metalView.setNeedsLayout()
                metalView.layoutIfNeeded()

                // Optional: Flash background to visually indicate frame arrival during debug
                // metalView.backgroundColor = .darkGray
            }
        }
    }
}

#Preview {
    WebRTCView(manager: KVSWebRTCManager(configuration: .default))
}
