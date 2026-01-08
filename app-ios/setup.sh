#!/bin/bash

# Setup script for AWS IoT MQTT iOS App
# NOTE: The MQTT app works WITHOUT any dependencies!

set -e  # Exit on error

clear
echo "========================================="
echo "AWS IoT MQTT iOS App"
echo "========================================="
echo ""

# Check if we're in the correct directory
if [ ! -d "AWSSimpleTest.xcodeproj" ]; then
    echo "❌ Error: Cannot find AWSSimpleTest.xcodeproj"
    echo "   Please run this script from: app-ios/AWSSimpleTest/"
    echo "   Current directory: $(pwd)"
    exit 1
fi

echo "✅ Found Xcode project"
echo ""

# Check Xcode version
if command -v xcodebuild &> /dev/null; then
    XCODE_VERSION=$(xcodebuild -version | head -n 1)
    echo "✅ $XCODE_VERSION installed"
else
    echo "⚠️  Warning: Xcode command line tools not found"
    echo "   Install from: xcode-select --install"
fi

echo ""
echo "========================================="
echo "✅ Setup Complete!"
echo "========================================="
echo ""
echo "🎉 Good news: The MQTT app needs NO dependencies!"
echo ""
echo "The app is ready to run right now:"
echo ""
echo "  1. Open the project:"
echo "     open AWSSimpleTest.xcodeproj"
echo ""
echo "  2. In Xcode, press Cmd+R to run"
echo ""
echo "  3. Start using MQTT immediately!"
echo ""
echo "========================================="
echo "📖 Documentation"
echo "========================================="
echo ""
echo "Quick Start:"
echo "  → START_HERE.md    - Overview and quick start"
echo "  → QUICK_START.md   - Usage guide"
echo ""
echo "Full Documentation:"
echo "  → README.md        - Complete features and setup"
echo "  → SETUP_GUIDE.md   - Troubleshooting"
echo ""
echo "Optional:"
echo "  → WEBRTC_SETUP.md  - Add video streaming (optional)"
echo ""
echo "========================================="
echo "⚠️  Important Notes"
echo "========================================="
echo ""
echo "• MQTT functionality works WITHOUT dependencies"
echo "• NO need to run 'pod install'"
echo "• Open .xcodeproj (NOT .xcworkspace)"
echo "• WebRTC is optional - MQTT works standalone"
echo ""
echo "========================================="
echo ""
echo "Ready to start? Run:"
echo "  open AWSSimpleTest.xcodeproj"
echo ""
echo "Then press Cmd+R in Xcode!"
echo ""

# Optional: Ask if user wants to open Xcode now
read -p "Open Xcode now? (y/n) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Opening Xcode..."
    open AWSSimpleTest.xcodeproj
    echo ""
    echo "✅ Xcode opened! Press Cmd+R to run the app."
else
    echo ""
    echo "👍 Run 'open AWSSimpleTest.xcodeproj' when ready!"
fi

echo ""
echo "🚀 Happy coding!"
echo ""
