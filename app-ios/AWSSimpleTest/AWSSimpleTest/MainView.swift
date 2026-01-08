//
//  MainView.swift
//  AWSSimpleTest
//
//  Main view with tabs for MQTT and WebRTC functionality
//

import SwiftUI

struct MainView: View {
    @StateObject private var mqttManager = MQTTManager(configuration: .default)
    @StateObject private var kvsManager = KVSWebRTCManager(configuration: .default)

    var body: some View {
        TabView {
            MQTTView(manager: mqttManager)
                .tabItem {
                    Label("MQTT", systemImage: "antenna.radiowaves.left.and.right")
                }

            WebRTCView(manager: kvsManager)
                .tabItem {
                    Label("WebRTC", systemImage: "video")
                }
        }
    }
}

#Preview {
    MainView()
}
