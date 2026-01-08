# Quick Start Guide

Get up and running with the AWS KVS WebRTC Viewer in 5 minutes.

## Prerequisites Checklist

- [ ] Node.js 16+ installed
- [ ] React Native CLI installed (`npm install -g react-native-cli`)
- [ ] Xcode (for iOS) or Android Studio (for Android)
- [ ] AWS account with KVS signaling channel created
- [ ] Master device streaming to your KVS channel

## Step 1: Install Dependencies

```bash
cd app-react-native/AWSKVSViewer
npm install
```

For iOS:
```bash
cd ios
pod install
cd ..
```

## Step 2: Configure AWS Credentials

Open `src/screens/ViewerScreen.js` and update lines 30-36:

```javascript
const kvsConfig = {
  channelName: 'YOUR_CHANNEL_NAME',  // Your channel name
  channelARN: 'arn:aws:kinesisvideo:us-west-2:ACCOUNT_ID:channel/YOUR_CHANNEL_NAME/TIMESTAMP',  // Your full ARN
  region: 'us-west-2',  // Your AWS region
  accessKey: 'YOUR_AWS_ACCESS_KEY',  // Your access key
  secretKey: 'YOUR_AWS_SECRET_KEY',  // Your secret key
};
```

**Where to find these values:**

1. **Channel ARN**: AWS Console → Kinesis Video Streams → Signaling channels → Your channel → ARN
2. **Access Key/Secret**: AWS Console → IAM → Users → Security credentials → Create access key

## Step 3: Run the App

### iOS (Simulator or Device)

```bash
npm run ios
```

Or from Xcode:
1. Open `ios/AWSKVSViewer.xcworkspace`
2. Select your device/simulator
3. Press Run (⌘R)

### Android (Emulator or Device)

```bash
npm run android
```

Or from Android Studio:
1. Open `android/` folder
2. Wait for Gradle sync
3. Press Run

## Step 4: Test Connection

1. **Ensure master device is streaming** to your KVS channel
2. **Open the app** on your device
3. **Tap "Start Stream"**
4. **Expected behavior:**
   - ✅ No microphone permission dialog
   - ✅ Video stream appears within 5-10 seconds
   - ✅ Status indicator turns green

## Verification: No Mic Permission

To confirm the app does NOT request mic permission:

1. **Delete the app** from your device
2. **Reinstall** via `npm run ios` or `npm run android`
3. **Open the app** and tap "Start Stream"
4. **Observe:** No system popup for microphone access

## Troubleshooting

### Issue: "Cannot connect to Metro bundler"

```bash
npm start -- --reset-cache
```

### Issue: iOS build fails

```bash
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
npm run ios
```

### Issue: Android build fails

```bash
cd android
./gradlew clean
cd ..
npm run android
```

### Issue: Video not showing

**Check console logs:**
```bash
# iOS
npm run ios -- --verbose

# Android
npm run android -- --verbose
```

**Common causes:**
- Master device not streaming
- Wrong channel ARN
- Network firewall blocking WebRTC
- Invalid AWS credentials

### Issue: ICE connection failed

This means the viewer cannot establish a connection with the master.

**Debugging steps:**
1. Check if master is online: AWS Console → KVS → Your channel → Metrics
2. Verify both devices are on the internet (not local network only)
3. Check logs for ICE candidates:
   ```
   [WebRTC] Generated ICE candidate: host
   [WebRTC] Generated ICE candidate: srflx
   [WebRTC] Generated ICE candidate: relay
   ```
   If you only see "host", TURN servers might not be working.

## Testing on Real Device

### iOS (via Cable)

1. Connect iPhone via USB
2. Xcode → Product → Destination → Your iPhone
3. Run (⌘R)

### Android (via Cable)

1. Enable Developer Mode on Android device
2. Enable USB Debugging
3. Connect via USB
4. Run: `npm run android`

## Console Logs Explained

```
[App] Connecting to AWS KVS...
[KVS] Connecting to signaling channel: Marcus_0DB3E2_2
[KVS] Got endpoints: { HTTPS: '...', WSS: '...' }
[KVS] Got ICE servers: 3
[KVS] WebSocket connected
[WebRTC] Starting viewer connection...
[WebRTC] Added recvonly transceivers (audio + video)
[WebRTC] Local description set (offer)
[WebRTC] Offer sent to signaling server
[KVS] Received message: SDP_ANSWER
[WebRTC] Received answer from master device
[WebRTC] Remote description set (answer)
[WebRTC] Received remote track: video
[WebRTC] Setting remote stream
[WebRTC] ICE connection state: connected ✅
```

## Next Steps

1. **Test on real device** (simulator has network limitations)
2. **Check master device logs** to ensure it's connected
3. **Monitor AWS KVS metrics** in the AWS Console
4. **Add error handling** for production use
5. **Implement reconnection logic** for network interruptions

## Support

If you encounter issues:

1. **Check logs:** Enable verbose logging in `useWebRTCViewer.js`
2. **Test master device:** Verify it's streaming with AWS SDK test viewer
3. **Network test:** Try different WiFi or cellular connection
4. **GitHub Issues:** Open an issue with console logs

## Success Criteria

✅ App launches without crashes
✅ No microphone permission dialog appears
✅ Video stream connects and plays
✅ ICE connection state shows "connected"
✅ Works on both iOS and Android
✅ Works on real devices (not just simulator)

---

**Estimated Time:** 5-15 minutes (depending on your React Native environment setup)

**Stuck?** Check the full README.md for detailed troubleshooting steps.
