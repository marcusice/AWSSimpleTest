//
//  MQTTView.swift
//  AWSSimpleTest
//
//  MQTT view with publish/subscribe controls and filtered message logs
//

import SwiftUI

struct MQTTView: View {
    @ObservedObject var manager: MQTTManager
    @State private var publishTopic = "cmd/E96TJE8/QDS_BBM/Marcus_0DB3E2_2_THING/req"
    @State private var publishMessage = """
{
   "data_type":"data.issued.control",
   "data_id":"1111",
   "timestamp":"0123456789123",
   "data":{
      "jobs":"ota",
      "action":"start",
      "md5":"df3f457ea171be0de83e38cdd99a5367",
      "url":"https://lhkmarcus.com/public/E96TJE8/T3.3.103.9650.ota.bin",
      "size":"14742923",
      "version":"T3.3.103.9650"
   }
}
"""
    @State private var filter1 = "dt/iot/E96TJE8/QDS_BBM/Marcus_0DB3E2_2_THING/res"
    @State private var filter2 = "cmd/E96TJE8/QDS_BBM/Marcus_0DB3E2_2_THING/req"
    @State private var publishStatus: String?
    @State private var showingPublishSuccess = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Connection Status
                    connectionStatusView

                    // Publish Section
                    publishSectionView

                    // Filtered Logs
                    filteredLogsView

                    // Controls
                    controlButtonsView
                }
                .padding()
            }
            .navigationTitle("AWS IoT MQTT")
            .onAppear {
                manager.connect()
            }
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

    private var publishSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Publish Message")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Topic:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Topic", text: $publishTopic)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Message:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $publishMessage)
                    .frame(height: 150)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .cornerRadius(4)
            }

            Button(action: publishMessageAction) {
                Text("Publish")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(manager.connectionStatus.isConnected ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(!manager.connectionStatus.isConnected)

            if let status = publishStatus {
                Text(status)
                    .font(.caption)
                    .foregroundColor(showingPublishSuccess ? .green : .red)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemGray6))
        )
    }

    private var filteredLogsView: some View {
        VStack(spacing: 20) {
            // Filter 1
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Filter Log 1:")
                        .font(.headline)
                    Spacer()
                }
                TextField("Filter", text: $filter1)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                MessageLogView(messages: filteredMessages(filter: filter1))
            }

            // Filter 2
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Filter Log 2:")
                        .font(.headline)
                    Spacer()
                }
                TextField("Filter", text: $filter2)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                MessageLogView(messages: filteredMessages(filter: filter2))
            }
        }
    }

    private var controlButtonsView: some View {
        HStack(spacing: 12) {
            if manager.connectionStatus.isConnected {
                Button("Disconnect") {
                    manager.disconnect()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Connect") {
                    manager.connect()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Clear Logs") {
                manager.clearMessages()
            }
            .buttonStyle(.bordered)

            Button("Save Logs") {
                saveLogs()
            }
            .buttonStyle(.bordered)
        }
    }

    private func filteredMessages(filter: String) -> [MQTTMessage] {
        guard !filter.isEmpty else { return manager.messages }
        return manager.messages.filter { message in
            message.isSystem || message.topic.contains(filter)
        }
    }

    private func publishMessageAction() {
        guard !publishTopic.isEmpty, !publishMessage.isEmpty else {
            publishStatus = "Please enter topic and message"
            showingPublishSuccess = false
            return
        }

        manager.publish(topic: publishTopic, message: publishMessage)
        publishStatus = "Message published to \(publishTopic)"
        showingPublishSuccess = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            publishStatus = nil
        }
    }

    private func saveLogs() {
        // Save logs to file
        let logs = manager.messages.map { message in
            "\(message.timestampString) - \(message.isSystem ? "System: " : "Topic: \(message.topic) - ")\(message.message)"
        }.joined(separator: "\n")

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = documentsDirectory.appendingPathComponent("mqtt_log_\(dateString).txt")
            do {
                try logs.write(to: fileURL, atomically: true, encoding: .utf8)
                publishStatus = "Logs saved to \(fileURL.lastPathComponent)"
                showingPublishSuccess = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    publishStatus = nil
                }
            } catch {
                publishStatus = "Failed to save logs: \(error.localizedDescription)"
                showingPublishSuccess = false
            }
        }
    }
}

struct MessageLogView: View {
    let messages: [MQTTMessage]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(message.timestampString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        if message.isSystem {
                            Text("System: \(message.message)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else {
                            Text("Topic: \(message.topic)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(message.message)
                                .font(.caption)
                                .lineLimit(nil)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(UIColor.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                }
            }
        }
        .frame(height: 300)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
}

#Preview {
    MQTTView(manager: MQTTManager(configuration: .default))
}
