# How to Add WebRTC to Your App

## Why WebRTC Isn't Working Yet

The WebRTC tab shows "not yet implemented" because we need to add external frameworks:
- **WebRTC** - For peer connections and video streaming
- **AWS SDK** - For Kinesis Video Streams signaling

CocoaPods doesn't work with Xcode 16, so we'll use **Swift Package Manager** instead.

## Step-by-Step Instructions

### Step 1: Add WebRTC Package

1. Open `AWSSimpleTest.xcodeproj` in Xcode
2. Select the project in the navigator (top item)
3. Select your app target
4. Go to the **"General"** tab
5. Scroll down to **"Frameworks, Libraries, and Embedded Content"**
6. Click the **"+"** button
7. Click **"Add Other..."** → **"Add Package Dependency..."**

8. In the search field, enter:
   ```
   https://github.com/stasel/WebRTC.git
   ```

9. Select the package and click **"Add Package"**
10. When asked which products to add, select **"WebRTC"**
11. Click **"Add Package"**

### Step 2: Add AWS SDK Package

1. Click **"+"** again in "Frameworks, Libraries, and Embedded Content"
2. Click **"Add Other..."** → **"Add Package Dependency..."**

3. In the search field, enter:
   ```
   https://github.com/aws-amplify/aws-sdk-ios-spm
   ```

4. Select the package and click **"Add Package"**
5. When asked which products to add, select:
   - ✅ **AWSCore**
   - ✅ **AWSKinesisVideo**
   - ✅ **AWSKinesisVideoSignaling**
6. Click **"Add Package"**

### Step 3: Wait for Package Resolution

Xcode will download and integrate the packages. This may take 2-5 minutes.

### Step 4: Verify Packages Are Added

1. In the project navigator, you should see a new **"Package Dependencies"** section
2. It should show:
   - WebRTC
   - aws-sdk-ios-spm

## What Happens Next?

Once you've added these packages, I can update the code to use them. The current code is ready - it just needs the frameworks to be available.

## Quick Check

After adding the packages:
1. Build the project (Cmd+B)
2. If it builds successfully, the frameworks are properly added
3. Let me know, and I'll enable the WebRTC functionality

## Troubleshooting

### "Failed to resolve package"
- Check your internet connection
- Try again - sometimes GitHub has temporary issues
- Make sure you entered the URLs correctly

### "Package already added"
- That's fine! It means the package is there
- Try building (Cmd+B) to verify

### Build errors after adding
- Clean build folder (Cmd+Shift+K)
- Restart Xcode
- Try building again

---

**Once you've completed Steps 1-2, let me know and I'll activate the WebRTC code!**
