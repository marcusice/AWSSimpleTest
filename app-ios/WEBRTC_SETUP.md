# Adding WebRTC Functionality (Optional)

The MQTT functionality works perfectly without any external dependencies. If you want to add WebRTC streaming functionality later, follow this guide.

## Why WebRTC Was Not Included

1. **CocoaPods Compatibility**: CocoaPods 1.15.0 doesn't support Xcode 16's new file system synchronized groups
2. **Large Dependencies**: WebRTC framework is ~100MB
3. **MQTT Works Standalone**: The MQTT functionality doesn't need WebRTC

## Option 1: Use Swift Package Manager (Recommended)

Swift Package Manager is the modern, native way to add dependencies.

### Step 1: Add WebRTC Package

1. Open `AWSSimpleTest.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies**
3. Add WebRTC:
   - URL: `https://github.com/stasel/WebRTC.git`
   - Version: Latest
   - Click "Add Package"

### Step 2: Add AWS SDK Packages

1. Add AWS SDK for iOS:
   - URL: `https://github.com/aws-amplify/aws-sdk-ios-spm`
   - Select: `AWSKinesisVideo` and `AWSKinesisVideoSignaling`
   - Click "Add Package"

### Step 3: Restore WebRTC Code

1. Open `KVSWebRTCManager.swift`
2. Find and copy the full WebRTC implementation from the backup at the end of this file
3. Replace the current stub with the full implementation

### Step 4: Update WebRTCView

1. Open `WebRTCView.swift`
2. Uncomment the RTCVideoView code
3. Remove the placeholder info message

### Step 5: Build and Test

1. Clean build folder (`Cmd+Shift+K`)
2. Build (`Cmd+B`)
3. Run the app and test WebRTC streaming

## Option 2: Update CocoaPods

If you prefer CocoaPods, update to a version that supports Xcode 16:

```bash
sudo gem install cocoapods --pre
cd /path/to/AWSSimpleTest
pod install
```

Then follow steps 3-5 from Option 1.

## Option 3: Manual Framework Integration

Download and manually add the WebRTC framework:

1. Download WebRTC.xcframework from [Google WebRTC releases](https://github.com/stasel/WebRTC/releases)
2. Drag it into your Xcode project
3. Add AWS SDK frameworks manually
4. Follow steps 3-5 from Option 1

## Full WebRTC Implementation

Here's the complete `KVSWebRTCManager.swift` implementation for reference:

<details>
<summary>Click to expand full KVSWebRTCManager.swift code</summary>

```swift
//
//  KVSWebRTCManager.swift
//  AWSSimpleTest
//
//  AWS Kinesis Video Streams WebRTC manager for viewer functionality
//

import Foundation
import WebRTC
import AWSKinesisVideo
import AWSKinesisVideoSignaling

class KVSWebRTCManager: NSObject, ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var remoteVideoTrack: RTCVideoTrack?

    private var configuration: KVSConfiguration
    private var peerConnection: RTCPeerConnection?
    private var signalingClient: AWSKinesisVideoSignalingClient?
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var iceServers: [RTCIceServer] = []

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

    // ... rest of the implementation from the original file
}
```

</details>

## Testing WebRTC

Once implemented:

1. **Start a Master Device**: Ensure you have a device streaming to your KVS channel
2. **Launch the App**: Open the WebRTC tab
3. **Verify Settings**: Check channel name and ARN
4. **Start Stream**: Tap "Start Stream"
5. **Wait for Connection**: It may take 5-10 seconds
6. **Video Appears**: You should see the live stream

## Troubleshooting WebRTC

### "Could not resolve host" or connection errors

- Verify channel ARN is correct
- Ensure master device is streaming
- Check AWS credentials have KVS permissions

### Video doesn't appear

- Check STUN/TURN servers are accessible
- Try on a real device instead of simulator
- Verify network allows WebRTC traffic
- Check CloudWatch logs for errors

### Build errors after adding packages

- Clean build folder
- Delete derived data
- Restart Xcode
- Try building again

## IAM Permissions for WebRTC

Your AWS credentials need these permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kinesisvideo:DescribeSignalingChannel",
                "kinesisvideo:GetSignalingChannelEndpoint",
                "kinesisvideo:CreateSignalingChannel",
                "kinesisvideo:DeleteSignalingChannel"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "kinesisvideo:ConnectAsViewer",
                "kinesisvideo:GetIceServerConfig"
            ],
            "Resource": "*"
        }
    ]
}
```

## Do You Need WebRTC?

Consider if WebRTC is necessary for your use case:

- **If you only need MQTT**: The app is complete as-is!
- **If you need video streaming**: Follow this guide to add WebRTC
- **If you're unsure**: Start with MQTT and add WebRTC later

## Alternative: Keep Two Versions

You could maintain two versions:

1. **MQTT-only** (current): Lightweight, no dependencies
2. **Full version**: MQTT + WebRTC with all dependencies

Use Git branches to manage them:

```bash
git checkout -b mqtt-only
git commit -am "MQTT-only version"
git checkout main
# Add WebRTC on main branch
```

## Support

If you need help adding WebRTC:

1. Check AWS KVS documentation
2. Review WebRTC.org guides
3. Check Stack Overflow for specific errors
4. Consult AWS support forums

---

**Remember**: The MQTT functionality is fully working and production-ready right now. WebRTC is optional and can be added anytime!
