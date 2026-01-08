# AWS KVS WebRTC Viewer - React Native

A **viewer-only** React Native app for streaming video from AWS Kinesis Video Streams (KVS) WebRTC **without requesting microphone permissions**.

## Key Features

✅ **No Microphone Permission Prompt** - Uses `recvonly` transceivers instead of `getUserMedia()`
✅ **AWS KVS Integration** - Complete signaling channel implementation
✅ **H.264 Baseline Profile** - Automatic SDP manipulation for compatibility
✅ **STUN/TURN Support** - AWS-provided ICE servers
✅ **Real-time Video Streaming** - Low-latency WebRTC viewer

## How It Works

This app avoids the microphone permission prompt by using **WebRTC Transceivers** with `direction: 'recvonly'` instead of calling `getUserMedia()`.

```javascript
// Traditional approach (requests mic permission):
const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true });

// Our approach (NO permission prompt):
peerConnection.addTransceiver('audio', { direction: 'recvonly' });
peerConnection.addTransceiver('video', { direction: 'recvonly' });
```

## Prerequisites

- Node.js 16+
- React Native development environment set up ([guide](https://reactnative.dev/docs/environment-setup))
- AWS account with KVS signaling channel created
- Master device (camera) streaming to AWS KVS

## Installation

### 1. Install Dependencies

```bash
npm install
# or
yarn install
```

### 2. Configure AWS Credentials

Edit `src/screens/ViewerScreen.js` and update the configuration:

```javascript
const kvsConfig = {
  channelName: 'YOUR_CHANNEL_NAME',
  channelARN: 'arn:aws:kinesisvideo:us-west-2:ACCOUNT_ID:channel/CHANNEL_NAME/TIMESTAMP',
  region: 'us-west-2',
  accessKey: 'YOUR_AWS_ACCESS_KEY',
  secretKey: 'YOUR_AWS_SECRET_KEY',
};
```

### 3. iOS Setup

```bash
cd ios
pod install
cd ..
```

Verify that `ios/Info.plist` contains the microphone usage description (required even though we don't use it):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Audio is used for two-way communication (receive only in this app).</string>
```

### 4. Android Setup

No additional setup required. The `AndroidManifest.xml` is already configured.

## Running the App

### iOS

```bash
npm run ios
# or
npx react-native run-ios
```

### Android

```bash
npm run android
# or
npx react-native run-android
```

## Verification Checklist

To confirm the app does NOT request microphone permission:

1. **Uninstall the app** completely from your device
2. **Reinstall and run** the app
3. **Navigate to the viewer screen** and tap "Start Stream"
4. **Expected Result:**
   - ✅ Video stream connects and plays
   - ✅ NO system popup asking for microphone permission
   - ❌ On iOS, you might see the orange microphone indicator (this is a known iOS behavior with WebRTC libraries)

## Project Structure

```
src/
├── hooks/
│   └── useWebRTCViewer.js      # WebRTC viewer logic with recvonly transceivers
├── services/
│   └── KVSSignalingClient.js   # AWS KVS signaling channel client
└── screens/
    └── ViewerScreen.js         # Main viewer UI component
```

## Key Implementation Details

### 1. Receive-Only Transceivers

The core technique is in `useWebRTCViewer.js`:

```javascript
// Add transceivers with 'recvonly' direction
pc.current.addTransceiver('audio', { direction: 'recvonly' });
pc.current.addTransceiver('video', { direction: 'recvonly' });
```

This tells WebRTC: "I want to RECEIVE media, but I have nothing to send" - bypassing the need for local media streams.

### 2. H.264 Baseline Profile Forcing

AWS KVS master devices often use H.264 High Profile, but many mobile devices only support Baseline Profile. We automatically convert the SDP:

```javascript
const forceH264Baseline = (sdp) => {
  return sdp.replace(/profile-level-id=[0-9a-fA-F]+/g, 'profile-level-id=42e01f');
};
```

### 3. AWS KVS Signaling

The `KVSSignalingClient` handles:
- Getting signaling channel endpoints
- Fetching STUN/TURN servers
- WebSocket connection with SigV4 signing
- SDP offer/answer exchange
- ICE candidate trickle

## Troubleshooting

### Issue: Microphone Permission Still Requested

**Cause:** You might be using `getUserMedia()` somewhere in your code.

**Solution:** Ensure you're using transceivers:
```javascript
// ❌ DON'T DO THIS:
const stream = await navigator.mediaDevices.getUserMedia({ audio: true });

// ✅ DO THIS:
pc.addTransceiver('audio', { direction: 'recvonly' });
```

### Issue: Video Not Appearing

**Check:**
1. Master device is streaming to the correct KVS channel
2. AWS credentials are correct
3. Channel ARN matches the master device
4. Network connectivity (check console logs for ICE connection state)

### Issue: ICE Connection Failed

**Possible Causes:**
- Firewall blocking UDP traffic
- TURN servers not working
- Network incompatibility between viewer and master

**Solution:**
- Check console logs for ICE candidate types (host, srflx, relay)
- Verify TURN servers are accessible
- Test on real device (not simulator)

### Issue: iOS App Crashes on Launch

**Cause:** Missing `NSMicrophoneUsageDescription` in Info.plist

**Solution:** Add the required privacy key to `ios/Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Audio is used for two-way communication.</string>
```

## Known Limitations

1. **iOS Microphone Indicator:** Even though we don't request permission, iOS may show the orange microphone indicator when WebRTC is active. This is a platform behavior.

2. **WebRTC Library Linking:** The app binary still links against AVFoundation (iOS) and audio frameworks (Android), which is why privacy descriptions are required.

3. **No Audio Transmission:** This is a receive-only viewer. If you need two-way communication, you'll need to implement `sendrecv` transceivers with `getUserMedia()`.

## Testing Checklist

- [ ] App installs without errors
- [ ] No microphone permission dialog appears
- [ ] Video stream connects successfully
- [ ] Video plays smoothly without stuttering
- [ ] App works on both iOS and Android
- [ ] App works on real devices (not just simulator)
- [ ] ICE candidates are exchanged (check logs)
- [ ] Connection survives network interruptions

## Architecture

```
┌─────────────────┐
│  React Native   │
│   App (Viewer)  │
└────────┬────────┘
         │
         ├── useWebRTCViewer (recvonly transceivers)
         │
         ├── KVSSignalingClient (WebSocket)
         │
         └── RTCPeerConnection
              │
              ├── STUN/TURN (AWS ICE servers)
              │
              └── Media Stream (remote video)
                   │
                   └── RTCView (video player)
```

## AWS KVS Setup

### Create Signaling Channel

```bash
aws kinesisvideo create-signaling-channel \
  --channel-name YOUR_CHANNEL_NAME \
  --region us-west-2
```

### Get Channel ARN

```bash
aws kinesisvideo describe-signaling-channel \
  --channel-name YOUR_CHANNEL_NAME \
  --region us-west-2
```

## Contributing

Contributions are welcome! Please ensure:
1. The microphone permission prompt is NOT triggered
2. Code follows React Native best practices
3. All changes are tested on both iOS and Android

## License

MIT License - See LICENSE file for details

## Credits

Built with:
- [react-native-webrtc](https://github.com/react-native-webrtc/react-native-webrtc)
- [AWS SDK for JavaScript](https://aws.amazon.com/sdk-for-javascript/)
- AWS Kinesis Video Streams

## Support

For issues related to:
- **This app:** Open a GitHub issue
- **AWS KVS:** Check [AWS KVS Documentation](https://docs.aws.amazon.com/kinesisvideostreams/)
- **react-native-webrtc:** Check [library documentation](https://github.com/react-native-webrtc/react-native-webrtc)
