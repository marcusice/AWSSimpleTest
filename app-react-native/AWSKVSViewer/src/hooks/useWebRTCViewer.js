import { useState, useEffect, useRef } from 'react';
import {
  RTCPeerConnection,
  RTCSessionDescription,
  RTCIceCandidate,
} from 'react-native-webrtc';

/**
 * WebRTC Viewer Hook - Receive Only Mode
 *
 * This hook implements a viewer-only WebRTC connection that does NOT
 * request microphone permissions. It uses transceivers with 'recvonly'
 * direction instead of getUserMedia().
 *
 * @param {Object} signalingClient - AWS KVS Signaling client instance
 * @returns {Object} - { remoteStream, startViewer, handleRemoteAnswer, handleRemoteCandidate }
 */
export const useWebRTCViewer = (signalingClient) => {
  const [remoteStream, setRemoteStream] = useState(null);
  const [connectionState, setConnectionState] = useState('disconnected');
  const pc = useRef(null);

  const startViewer = async () => {
    try {
      console.log('[WebRTC] Starting viewer connection...');
      setConnectionState('connecting');

      // 1. Initialize Peer Connection with STUN/TURN servers from AWS KVS
      const configuration = {
        iceServers: [
          // Default Google STUN server
          { urls: 'stun:stun.l.google.com:19302' },
          // AWS KVS will provide TURN servers via signalingClient.getIceServers()
        ],
        bundlePolicy: 'max-bundle',
        rtcpMuxPolicy: 'require',
      };

      // Get ICE servers from AWS KVS if available
      if (signalingClient && signalingClient.getIceServers) {
        const kvsIceServers = await signalingClient.getIceServers();
        configuration.iceServers = [...configuration.iceServers, ...kvsIceServers];
        console.log('[WebRTC] Using ICE servers:', configuration.iceServers.length);
      }

      pc.current = new RTCPeerConnection(configuration);

      // 2. THE CRITICAL STEP: Add Transceivers with 'recvonly'
      // This tells WebRTC: "I want to RECEIVE media, but I have nothing to send"
      // This bypasses getUserMedia() and avoids microphone permission prompt
      pc.current.addTransceiver('audio', { direction: 'recvonly' });
      pc.current.addTransceiver('video', { direction: 'recvonly' });
      console.log('[WebRTC] Added recvonly transceivers (audio + video)');

      // 3. Handle Incoming Remote Stream
      // When the master device sends media, this event fires
      pc.current.ontrack = (event) => {
        console.log('[WebRTC] Received remote track:', event.track.kind);

        if (event.streams && event.streams[0]) {
          console.log('[WebRTC] Setting remote stream');
          setRemoteStream(event.streams[0]);
          setConnectionState('connected');
        }
      };

      // 4. Handle ICE Candidates (Network Paths)
      pc.current.onicecandidate = (event) => {
        if (event.candidate) {
          console.log('[WebRTC] Generated ICE candidate:', event.candidate.type);
          // Send this candidate to AWS KVS Signaling Server
          signalingClient.sendIceCandidate(event.candidate);
        } else {
          console.log('[WebRTC] ICE gathering complete');
        }
      };

      // 5. Monitor Connection State
      pc.current.oniceconnectionstatechange = () => {
        const state = pc.current?.iceConnectionState;
        console.log('[WebRTC] ICE connection state:', state);

        if (state === 'connected' || state === 'completed') {
          setConnectionState('connected');
        } else if (state === 'failed' || state === 'disconnected') {
          setConnectionState('failed');
        }
      };

      pc.current.onconnectionstatechange = () => {
        const state = pc.current?.connectionState;
        console.log('[WebRTC] Connection state:', state);
      };

      // 6. Create Offer & Set Local Description
      // Even though we are "viewing", we initiate the connection with an Offer
      // to tell the master device we are ready to receive
      const offer = await pc.current.createOffer({
        offerToReceiveAudio: true,
        offerToReceiveVideo: true,
      });

      // Force H.264 Baseline profile in the SDP (for compatibility with AWS KVS)
      const modifiedSdp = forceH264Baseline(offer.sdp);
      const modifiedOffer = {
        type: offer.type,
        sdp: modifiedSdp,
      };

      await pc.current.setLocalDescription(modifiedOffer);
      console.log('[WebRTC] Local description set (offer)');

      // 7. Send Offer to AWS KVS Signaling Server
      await signalingClient.sendOffer(modifiedOffer);
      console.log('[WebRTC] Offer sent to signaling server');

    } catch (error) {
      console.error('[WebRTC] Error starting viewer:', error);
      setConnectionState('failed');
      throw error;
    }
  };

  // Helper to force H.264 Baseline profile in SDP
  const forceH264Baseline = (sdp) => {
    // Replace all H.264 profile-level-id with Baseline (42e01f)
    const pattern = /profile-level-id=[0-9a-fA-F]+/g;
    const modified = sdp.replace(pattern, 'profile-level-id=42e01f');

    if (modified !== sdp) {
      console.log('[WebRTC] Forced H.264 Baseline profile in SDP');
    }

    return modified;
  };

  // Helper to handle SDP answer from master device
  const handleRemoteAnswer = async (answer) => {
    try {
      console.log('[WebRTC] Received answer from master device');

      // Normalize the answer SDP (add H.264 fmtp if missing)
      const normalizedSdp = normalizeH264AnswerSdp(answer.sdp);
      const normalizedAnswer = {
        type: answer.type,
        sdp: normalizedSdp,
      };

      await pc.current?.setRemoteDescription(new RTCSessionDescription(normalizedAnswer));
      console.log('[WebRTC] Remote description set (answer)');
    } catch (error) {
      console.error('[WebRTC] Error setting remote answer:', error);
      throw error;
    }
  };

  // Helper to normalize H.264 answer SDP
  const normalizeH264AnswerSdp = (sdp) => {
    const lines = sdp.split('\r\n');
    const h264PayloadTypes = [];

    // Find H.264 payload types
    lines.forEach(line => {
      if (line.startsWith('a=rtpmap:') && line.includes('H264/')) {
        const parts = line.split(' ');
        const pt = parts[0].replace('a=rtpmap:', '');
        h264PayloadTypes.push(pt);
      }
    });

    // Add fmtp for H.264 if missing
    h264PayloadTypes.forEach(pt => {
      const fmtpLine = `a=fmtp:${pt}`;
      const hasFmtp = lines.some(line => line.startsWith(fmtpLine));

      if (!hasFmtp) {
        // Find the rtpmap line and insert fmtp after it
        const rtpmapIndex = lines.findIndex(line => line.startsWith(`a=rtpmap:${pt} `));
        if (rtpmapIndex !== -1) {
          lines.splice(rtpmapIndex + 1, 0,
            `${fmtpLine} level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f`
          );
          console.log('[WebRTC] Added H.264 fmtp to answer SDP');
        }
      }
    });

    return lines.join('\r\n');
  };

  // Helper to handle ICE candidates from master device
  const handleRemoteCandidate = async (candidate) => {
    try {
      if (candidate && pc.current) {
        console.log('[WebRTC] Adding remote ICE candidate:', candidate.type || 'unknown');
        await pc.current.addIceCandidate(new RTCIceCandidate(candidate));
      }
    } catch (error) {
      console.error('[WebRTC] Error adding remote ICE candidate:', error);
      // Don't throw - ICE candidate errors are non-fatal
    }
  };

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      console.log('[WebRTC] Cleaning up peer connection');
      if (pc.current) {
        pc.current.close();
        pc.current = null;
      }
      setRemoteStream(null);
      setConnectionState('disconnected');
    };
  }, []);

  return {
    remoteStream,
    connectionState,
    startViewer,
    handleRemoteAnswer,
    handleRemoteCandidate,
  };
};
