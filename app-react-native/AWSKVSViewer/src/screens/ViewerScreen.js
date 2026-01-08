import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  Button,
  StyleSheet,
  ActivityIndicator,
  StatusBar,
  Alert,
} from 'react-native';
import { RTCView } from 'react-native-webrtc';
import { useWebRTCViewer } from '../hooks/useWebRTCViewer';
import { KVSSignalingClient } from '../services/KVSSignalingClient';

/**
 * ViewerScreen Component
 *
 * This is the main screen for viewing the AWS KVS WebRTC stream.
 * It connects to the signaling channel and displays the remote video stream.
 *
 * IMPORTANT: This implementation uses 'recvonly' transceivers, which means
 * it will NOT request microphone permissions.
 */
const ViewerScreen = () => {
  const [signalingClient, setSignalingClient] = useState(null);
  const [isConnecting, setIsConnecting] = useState(false);

  const {
    remoteStream,
    connectionState,
    startViewer,
    handleRemoteAnswer,
    handleRemoteCandidate,
  } = useWebRTCViewer(signalingClient);

  // AWS KVS Configuration
  // TODO: Replace with your actual AWS credentials
  const kvsConfig = {
    channelName: 'YOUR_CHANNEL_NAME',
    channelARN: 'arn:aws:kinesisvideo:us-west-2:YOUR_ACCOUNT_ID:channel/YOUR_CHANNEL_NAME/TIMESTAMP',
    region: 'us-west-2',
    accessKey: 'YOUR_AWS_ACCESS_KEY',
    secretKey: 'YOUR_AWS_SECRET_KEY',
  };

  useEffect(() => {
    // Initialize signaling client
    const client = new KVSSignalingClient(kvsConfig);
    setSignalingClient(client);

    return () => {
      if (client) {
        client.disconnect();
      }
    };
  }, []);

  useEffect(() => {
    if (!signalingClient) return;

    // Listen for signaling events
    signalingClient.on('answer', handleRemoteAnswer);
    signalingClient.on('candidate', handleRemoteCandidate);
    signalingClient.on('disconnected', () => {
      console.log('[App] Signaling disconnected');
      Alert.alert('Disconnected', 'Signaling connection lost');
    });

    return () => {
      signalingClient.off('answer');
      signalingClient.off('candidate');
      signalingClient.off('disconnected');
    };
  }, [signalingClient, handleRemoteAnswer, handleRemoteCandidate]);

  const handleConnect = async () => {
    try {
      setIsConnecting(true);
      console.log('[App] Connecting to AWS KVS...');

      // Step 1: Connect to signaling channel
      await signalingClient.connect();

      // Step 2: Start WebRTC viewer (this will NOT request mic permission)
      await startViewer();

      console.log('[App] Connection initiated');
    } catch (error) {
      console.error('[App] Connection error:', error);
      Alert.alert(
        'Connection Error',
        error.message || 'Failed to connect to the stream'
      );
      setIsConnecting(false);
    }
  };

  const handleDisconnect = () => {
    if (signalingClient) {
      signalingClient.disconnect();
    }
    setIsConnecting(false);
  };

  const renderConnectionButton = () => {
    if (connectionState === 'connected') {
      return (
        <Button
          title="Disconnect"
          onPress={handleDisconnect}
          color="#dc3545"
        />
      );
    }

    return (
      <Button
        title={isConnecting ? 'Connecting...' : 'Start Stream'}
        onPress={handleConnect}
        disabled={isConnecting || !signalingClient}
      />
    );
  };

  const renderContent = () => {
    // If we have a remote stream, show the video
    if (remoteStream) {
      return (
        <RTCView
          streamURL={remoteStream.toURL()}
          style={styles.video}
          objectFit="cover"
          mirror={false}
        />
      );
    }

    // If connecting, show loading indicator
    if (isConnecting || connectionState === 'connecting') {
      return (
        <View style={styles.loading}>
          <ActivityIndicator size="large" color="#007bff" />
          <Text style={styles.loadingText}>Connecting to stream...</Text>
          <Text style={styles.statusText}>State: {connectionState}</Text>
        </View>
      );
    }

    // If failed, show error
    if (connectionState === 'failed') {
      return (
        <View style={styles.loading}>
          <Text style={styles.errorText}>Connection Failed</Text>
          <Text style={styles.statusText}>
            Unable to establish connection. Please check:
          </Text>
          <Text style={styles.statusText}>• AWS credentials</Text>
          <Text style={styles.statusText}>• Channel ARN</Text>
          <Text style={styles.statusText}>• Network connectivity</Text>
          <Text style={styles.statusText}>• Master device is running</Text>
        </View>
      );
    }

    // Default: show instructions
    return (
      <View style={styles.loading}>
        <Text style={styles.title}>AWS KVS WebRTC Viewer</Text>
        <Text style={styles.subtitle}>Receive-Only Mode</Text>
        <Text style={styles.infoText}>
          Tap "Start Stream" to connect to the video stream.
        </Text>
        <Text style={styles.infoText}>
          This app will NOT request microphone permissions.
        </Text>
      </View>
    );
  };

  return (
    <View style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#000" />

      {/* Video/Loading Area */}
      <View style={styles.videoContainer}>
        {renderContent()}
      </View>

      {/* Connection Status Bar */}
      <View style={styles.statusBar}>
        <View style={styles.statusIndicator}>
          <View
            style={[
              styles.statusDot,
              connectionState === 'connected' && styles.statusDotConnected,
              connectionState === 'connecting' && styles.statusDotConnecting,
              connectionState === 'failed' && styles.statusDotFailed,
            ]}
          />
          <Text style={styles.statusLabel}>
            {connectionState === 'connected' ? 'Connected' :
             connectionState === 'connecting' ? 'Connecting...' :
             connectionState === 'failed' ? 'Failed' : 'Disconnected'}
          </Text>
        </View>

        {renderConnectionButton()}
      </View>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  videoContainer: {
    flex: 1,
    backgroundColor: '#000',
  },
  video: {
    flex: 1,
    width: '100%',
    height: '100%',
  },
  loading: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#fff',
    marginBottom: 10,
  },
  subtitle: {
    fontSize: 16,
    color: '#aaa',
    marginBottom: 30,
  },
  loadingText: {
    fontSize: 16,
    color: '#fff',
    marginTop: 20,
  },
  infoText: {
    fontSize: 14,
    color: '#999',
    marginTop: 10,
    textAlign: 'center',
  },
  statusText: {
    fontSize: 12,
    color: '#666',
    marginTop: 8,
    textAlign: 'center',
  },
  errorText: {
    fontSize: 18,
    color: '#dc3545',
    fontWeight: 'bold',
    marginBottom: 20,
  },
  statusBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#1a1a1a',
    padding: 16,
    borderTopWidth: 1,
    borderTopColor: '#333',
  },
  statusIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: '#666',
    marginRight: 8,
  },
  statusDotConnected: {
    backgroundColor: '#28a745',
  },
  statusDotConnecting: {
    backgroundColor: '#ffc107',
  },
  statusDotFailed: {
    backgroundColor: '#dc3545',
  },
  statusLabel: {
    fontSize: 14,
    color: '#fff',
    fontWeight: '500',
  },
});

export default ViewerScreen;
