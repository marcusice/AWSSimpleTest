# iOS App Setup Guide

This guide will walk you through setting up the AWS IoT MQTT & KVS WebRTC iOS app.

## Prerequisites

1. **macOS** with Xcode 16.0 or later
2. **iOS device or simulator** running iOS 15.0+
3. **CocoaPods** installed (run: `sudo gem install cocoapods`)
4. **AWS Account** with:
   - IoT Core endpoint configured
   - KVS WebRTC signaling channel created
   - IAM credentials with appropriate permissions

## Step-by-Step Setup

### Step 1: Install Dependencies

Open Terminal and navigate to the project directory:

```bash
cd app-ios/AWSSimpleTest
```

Install CocoaPods dependencies:

```bash
pod install
```

This will:
- Download AWS SDK for iOS
- Download WebRTC framework
- Create an `.xcworkspace` file

**Important**: After running `pod install`, you must use `AWSSimpleTest.xcworkspace` to open the project, NOT `AWSSimpleTest.xcodeproj`.

### Step 2: Open the Workspace

```bash
open AWSSimpleTest.xcworkspace
```

### Step 3: Verify Files Are Added

In Xcode, verify that all the following files are present in the project navigator:

**Core Files:**
- ✅ Models.swift
- ✅ AWSSigV4Signer.swift
- ✅ MQTTManager.swift
- ✅ KVSWebRTCManager.swift

**View Files:**
- ✅ MainView.swift
- ✅ MQTTView.swift
- ✅ WebRTCView.swift
- ✅ ContentView.swift
- ✅ AWSSimpleTestApp.swift

If any files are missing:
1. Right-click on the `AWSSimpleTest` folder in Xcode
2. Select "Add Files to AWSSimpleTest..."
3. Navigate to the file location
4. Select the file and click "Add"

### Step 4: Configure App Permissions

The app needs network access. Add the following to your Info.plist if needed:

1. Right-click on `Info.plist` → Open As → Source Code
2. Add before the closing `</dict>`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
<key>NSCameraUsageDescription</key>
<string>This app requires camera access for WebRTC functionality.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app requires microphone access for WebRTC functionality.</string>
```

**Note**: For production, use specific domain exceptions instead of allowing arbitrary loads.

### Step 5: Configure AWS Credentials

Edit `Models.swift` to update your AWS credentials:

```swift
static let `default` = MQTTConfiguration(
    endpoint: "YOUR_IOT_ENDPOINT.iot.us-west-2.amazonaws.com",
    region: "us-west-2",
    accessKey: "YOUR_ACCESS_KEY",
    secretKey: "YOUR_SECRET_KEY",
    subscribeTopics: ["your/topic/#"],
    publishTopic: "your/publish/topic",
    filter1: "your/filter1",
    filter2: "your/filter2"
)
```

And for KVS:

```swift
static let `default` = KVSConfiguration(
    channelName: "YOUR_CHANNEL_NAME",
    channelARN: "YOUR_CHANNEL_ARN",
    region: "us-west-2",
    accessKey: "YOUR_ACCESS_KEY",
    secretKey: "YOUR_SECRET_KEY"
)
```

### Step 6: Set Development Team

1. Select the project in the navigator
2. Select the `AWSSimpleTest` target
3. Go to "Signing & Capabilities"
4. Select your development team from the dropdown

### Step 7: Build and Run

1. Select a simulator or connected device from the scheme selector
2. Press Cmd+R or click the Play button to build and run

## Verifying the Installation

### MQTT Functionality

1. Launch the app
2. You should see "Connected" status in the MQTT tab
3. Type a message and tap "Publish"
4. If you have a device publishing to subscribed topics, you should see messages appear in the logs

### WebRTC Functionality

1. Switch to the WebRTC tab
2. Ensure a master device is streaming to the channel
3. Tap "Start Stream"
4. After a few seconds, you should see the video stream appear

## Common Issues and Solutions

### Issue: "No such module 'WebRTC'" or "No such module 'AWSKinesisVideo'"

**Solution**:
1. Close Xcode
2. Run `pod deintegrate` then `pod install`
3. Open the `.xcworkspace` file (not `.xcodeproj`)
4. Clean build folder (Cmd+Shift+K)
5. Build again (Cmd+B)

### Issue: Compiler errors in Swift files

**Solution**:
1. Make sure you're opening `.xcworkspace` not `.xcodeproj`
2. Clean build folder
3. Delete derived data:
   - Xcode → Settings → Locations
   - Click arrow next to DerivedData path
   - Delete the folder for AWSSimpleTest

### Issue: "Cannot find 'MainView' in scope"

**Solution**:
Make sure all Swift files are added to the target:
1. Select the file in project navigator
2. Open File Inspector (Cmd+Option+1)
3. Under "Target Membership", ensure "AWSSimpleTest" is checked

### Issue: MQTT connection fails

**Solution**:
1. Verify AWS IoT endpoint is correct
2. Check AWS credentials have IoT permissions
3. Verify IoT policy allows connect/subscribe/publish
4. Check network connectivity
5. Review CloudWatch logs for errors

### Issue: WebRTC stream doesn't appear

**Solution**:
1. Verify master device is streaming
2. Check channel ARN is correct
3. Ensure AWS credentials have KVS permissions
4. Check that TURN servers are accessible
5. Try on a real device instead of simulator

### Issue: App crashes on launch

**Solution**:
1. Check Xcode console for error messages
2. Verify all dependencies are installed correctly
3. Ensure deployment target matches iOS version
4. Check that all required files are included in the target

## Testing Without Real AWS Resources

If you don't have AWS resources set up yet:

1. **MQTT Testing**: The app will show connection errors but won't crash. You can still test the UI.

2. **WebRTC Testing**: Similarly, the stream won't connect but the UI is functional.

3. **Mock Mode**: Consider adding a mock mode by creating test configurations with dummy values.

## Next Steps

Once the app is running successfully:

1. **Customize the UI**: Modify the SwiftUI views to match your design requirements
2. **Add Features**: Implement additional MQTT QoS levels, message persistence, etc.
3. **Improve Security**: Implement AWS Cognito for authentication
4. **Add Error Handling**: Enhance error messages and user feedback
5. **Testing**: Write unit tests for managers and integration tests for views

## AWS IAM Permissions Required

### For MQTT (IoT Core):
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iot:Connect",
                "iot:Subscribe",
                "iot:Receive",
                "iot:Publish"
            ],
            "Resource": "*"
        }
    ]
}
```

### For KVS WebRTC:
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

## Support and Resources

- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [AWS KVS WebRTC Documentation](https://docs.aws.amazon.com/kinesisvideostreams-webrtc-dg/)
- [AWS SDK for iOS](https://github.com/aws-amplify/aws-sdk-ios)
- [WebRTC Documentation](https://webrtc.org/getting-started/overview)

## Additional Notes

### Xcode 16 File System Synchronized Groups

This project uses Xcode 16's new file system synchronized groups feature. This means:
- Files are automatically discovered in the directory
- No need to manually add files to project
- Just ensure files are in the correct directory

If you experience issues with file discovery:
1. Clean the project
2. Close and reopen Xcode
3. The files should be automatically picked up

### iOS 18.5 Deployment Target

The project is configured for iOS 18.5. To support older iOS versions:
1. Select the project in navigator
2. Select the target
3. Change "iOS Deployment Target" to your desired minimum version (minimum iOS 15.0 for this app)

---

**Good luck with your iOS app development!** If you encounter any issues not covered here, please check the main README.md or consult the AWS documentation.
