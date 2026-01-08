#!/bin/bash

# Setup script for AWS IoT MQTT & KVS WebRTC iOS App
# This script helps you set up the iOS project with all required dependencies

set -e  # Exit on error

echo "========================================="
echo "AWS IoT MQTT & KVS WebRTC iOS App Setup"
echo "========================================="
echo ""

# Check if we're in the correct directory
if [ ! -f "AWSSimpleTest.xcodeproj/project.pbxproj" ]; then
    echo "❌ Error: Please run this script from the app-ios/AWSSimpleTest directory"
    echo "   Current directory: $(pwd)"
    exit 1
fi

echo "✅ Found Xcode project"
echo ""

# Check if CocoaPods is installed
if ! command -v pod &> /dev/null; then
    echo "⚠️  CocoaPods is not installed"
    echo "   Installing CocoaPods..."
    sudo gem install cocoapods
else
    echo "✅ CocoaPods is installed ($(pod --version))"
fi

echo ""

# Check if Podfile exists
if [ ! -f "Podfile" ]; then
    echo "❌ Error: Podfile not found"
    echo "   Please ensure Podfile is in the current directory"
    exit 1
fi

echo "✅ Found Podfile"
echo ""

# Install dependencies
echo "📦 Installing dependencies..."
echo "   This may take a few minutes..."
echo ""

pod install

echo ""
echo "========================================="
echo "✅ Setup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Open the workspace:"
echo "   open AWSSimpleTest.xcworkspace"
echo ""
echo "2. Configure your AWS credentials in Models.swift"
echo ""
echo "3. Select your development team in Xcode"
echo "   (Signing & Capabilities tab)"
echo ""
echo "4. Build and run the app (Cmd+R)"
echo ""
echo "For detailed instructions, see:"
echo "  - README.md for overview"
echo "  - SETUP_GUIDE.md for step-by-step guide"
echo ""
echo "⚠️  IMPORTANT: Always use .xcworkspace, not .xcodeproj!"
echo ""
