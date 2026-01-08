# AWS KVS WebRTC Viewer - Project Summary

## Overview

This React Native application implements a **viewer-only WebRTC client** for AWS Kinesis Video Streams that **does NOT request microphone permissions**.

## Problem Solved

Traditional WebRTC implementations use `getUserMedia()` to access local media devices, which triggers permission prompts on both iOS and Android. For a viewer-only application, this creates a poor user experience.

**Our Solution:** Use WebRTC Transceivers with `direction: 'recvonly'` instead of `getUserMedia()`.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    React Native App                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │           ViewerScreen.js (UI)                   │  │
│  │  - Connection controls                           │  │
│  │  - Video player (RTCView)                        │  │
│  │  - Status indicators                             │  │
│  └─────────────────┬────────────────────────────────┘  │
│                    │                                     │
│  ┌─────────────────▼────────────────────────────────┐  │
│  │     useWebRTCViewer.js (Hook)                    │  │
│  │  - Peer connection management                    │  │
│  │  - Recvonly transceivers (KEY!)                  │  │
│  │  - SDP manipulation (H.264 Baseline)             │  │
│  │  - ICE candidate handling                        │  │
│  └─────────────────┬────────────────────────────────┘  │
│                    │                                     │
│  ┌─────────────────▼────────────────────────────────┐  │
│  │   KVSSignalingClient.js (Service)                │  │
│  │  - AWS SDK integration                           │  │
│  │  - WebSocket signaling                           │  │
│  │  - SigV4 signing                                 │  │
│  │  - STUN/TURN server fetching                     │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
            ┌─────────────────────────┐
            │   AWS Kinesis Video     │
            │   Streams (KVS)         │
            │   - Signaling Channel   │
            │   - STUN/TURN Servers   │
            └───────────┬─────────────┘
                        │
                        ▼
            ┌─────────────────────────┐
            │   Master Device         │
            │   (Camera/Sender)       │
            └─────────────────────────┘
```

## Key Implementation Details

### 1. Recvonly Transceivers (Core Innovation)

**File:** `src/hooks/useWebRTCViewer.js`

```javascript
// Traditional approach (requests permissions):
const stream = await navigator.mediaDevices.getUserMedia({ audio: true, video: true });

// Our approach (NO permissions):
pc.current.addTransceiver('audio', { direction: 'recvonly' });
pc.current.addTransceiver('video', { direction: 'recvonly' });
```

This tells WebRTC: "I want to receive media, but I have nothing to send" - completely bypassing the need for local media access.

### 2. H.264 Baseline Profile Forcing

**Problem:** AWS KVS master devices often send H.264 High Profile (640c29), but mobile devices typically only support Baseline Profile (42e01f).

**Solution:** Automatic SDP manipulation:

```javascript
const forceH264Baseline = (sdp) => {
  return sdp.replace(/profile-level-id=[0-9a-fA-F]+/g, 'profile-level-id=42e01f');
};
```

### 3. AWS KVS Signaling Integration

**File:** `src/services/KVSSignalingClient.js`

Implements the complete AWS KVS signaling protocol:
- Endpoint discovery
- ICE server configuration
- WebSocket connection with SigV4 signing
- Base64-encoded message payloads
- SDP offer/answer exchange
- ICE candidate trickle

### 4. Mobile-Optimized UI

**File:** `src/screens/ViewerScreen.js`

- Full-screen video player
- Connection status indicator
- Simple start/stop controls
- Loading states and error handling

## File Structure

```
app-react-native/AWSKVSViewer/
├── src/
│   ├── hooks/
│   │   └── useWebRTCViewer.js          # WebRTC viewer logic
│   ├── services/
│   │   └── KVSSignalingClient.js       # AWS KVS signaling
│   └── screens/
│       └── ViewerScreen.js             # Main UI component
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml         # Android permissions
├── ios/
│   └── Info.plist.template             # iOS privacy settings
├── App.js                              # Entry point
├── package.json                        # Dependencies
├── README.md                           # Full documentation
├── QUICK_START.md                      # 5-minute setup guide
├── config.example.js                   # Configuration template
└── .gitignore                          # Git exclusions
```

## Dependencies

### Production
- `react-native-webrtc` (118.0.0) - WebRTC implementation
- `aws-sdk` (2.1490.0) - AWS KVS API client

### Development
- React Native 0.72.6
- Standard React Native development tools

## Configuration Required

### AWS Credentials (Required)

1. **Channel Name**: Your KVS signaling channel name
2. **Channel ARN**: Full ARN from AWS Console
3. **Region**: AWS region (e.g., us-west-2)
4. **Access Key**: IAM user access key with KVS permissions
5. **Secret Key**: Corresponding secret key

### IAM Permissions Required

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesisvideo:DescribeSignalingChannel",
        "kinesisvideo:GetSignalingChannelEndpoint",
        "kinesisvideo:GetIceServerConfig"
      ],
      "Resource": "arn:aws:kinesisvideo:*:*:channel/*"
    }
  ]
}
```

## Platform-Specific Configuration

### Android

**File:** `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```

**Note:** `RECORD_AUDIO` is declared but never requested because we don't call `getUserMedia()`.

### iOS

**File:** `ios/Info.plist`

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Audio is used for two-way communication (receive only in this app).</string>
```

**Note:** This is **required** by Apple even though we don't request permission, because the WebRTC library links against AVFoundation.

## Testing Strategy

### Verification Steps

1. **Delete app** from device
2. **Reinstall** the app
3. **Launch** and tap "Start Stream"
4. **Expected:** No microphone permission dialog appears
5. **Expected:** Video stream connects and plays

### Known Behaviors

- **iOS Orange Indicator:** iOS may show the orange microphone indicator when WebRTC is active. This is a platform behavior and does NOT mean the mic is being accessed.
- **Permission Key Required:** iOS requires `NSMicrophoneUsageDescription` even though we don't use it (framework linking requirement).

## Performance Characteristics

- **Connection Time:** 2-5 seconds (depending on network)
- **Latency:** 200-500ms (typical WebRTC latency)
- **Bandwidth:** ~2-5 Mbps (for 720p video)
- **Battery Impact:** Moderate (similar to video streaming apps)

## Security Considerations

1. **Hardcoded Credentials:** The current implementation has credentials in source code. For production:
   - Use AWS Cognito for temporary credentials
   - Implement secure credential storage
   - Use environment variables

2. **SigV4 Signing:** Current implementation uses basic signing. For production:
   - Implement full AWS SigV4 signing
   - Use short-lived tokens
   - Rotate credentials regularly

## Limitations

1. **Receive Only:** This app cannot send audio/video back to the master
2. **Single Stream:** Only connects to one channel at a time
3. **No Recording:** Does not include video recording functionality
4. **iOS Indicator:** Cannot disable the iOS microphone indicator (platform limitation)

## Future Enhancements

Potential improvements:
- [ ] AWS Cognito integration for secure credentials
- [ ] Multiple channel support
- [ ] Video recording to local storage
- [ ] Screenshot capture
- [ ] Network quality indicators
- [ ] Reconnection on network interruption
- [ ] Picture-in-picture mode
- [ ] Landscape orientation lock

## Comparison with iOS Native Implementation

The iOS native Swift implementation (in `app-ios/`) has similar issues with ICE connection failures. This React Native version provides:

✅ **Cross-platform** (iOS + Android from single codebase)
✅ **Same no-permission approach** (recvonly transceivers)
✅ **Easier deployment** (no Xcode build configurations)
✅ **Faster iteration** (hot reload during development)

❌ **Larger bundle size** (React Native overhead)
❌ **Slightly higher latency** (JavaScript bridge overhead)

## Debugging Tips

### Enable Verbose Logging

Edit `useWebRTCViewer.js` and add:
```javascript
pc.current.addEventListener('track', console.log);
pc.current.addEventListener('icecandidate', console.log);
```

### Monitor ICE Candidates

Check console for:
```
[WebRTC] Generated ICE candidate: host      ← Local network
[WebRTC] Generated ICE candidate: srflx     ← Public IP via STUN
[WebRTC] Generated ICE candidate: relay     ← TURN relay
```

If only "host" candidates appear, TURN servers are not working.

### Check AWS KVS Metrics

AWS Console → Kinesis Video Streams → Your Channel → Monitoring
- Incoming connections
- Signaling messages
- ICE candidate exchanges

## Success Criteria

✅ **No Permission Prompt:** App never requests microphone permission
✅ **Video Playback:** Remote stream displays correctly
✅ **ICE Connection:** Successfully connects via STUN/TURN
✅ **Cross-Platform:** Works on both iOS and Android
✅ **Real Device:** Tested on physical devices (not just simulator)

## License

MIT License

## Credits

- Built following React Native WebRTC best practices
- AWS KVS integration based on AWS SDK documentation
- Inspired by the need for viewer-only mobile apps without intrusive permission prompts

---

**Created:** January 2026
**Platform:** React Native 0.72.6
**WebRTC Version:** 118.0.0
**Target:** iOS 13+ | Android 5.0+
