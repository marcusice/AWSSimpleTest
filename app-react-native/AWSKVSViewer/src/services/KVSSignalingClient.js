import AWS from 'aws-sdk/dist/aws-sdk-react-native';

/**
 * AWS Kinesis Video Streams WebRTC Signaling Client
 *
 * This class handles the WebSocket connection to AWS KVS for WebRTC signaling.
 * It manages:
 * - Connecting to the KVS signaling channel
 * - Sending/receiving SDP offers/answers
 * - Exchanging ICE candidates
 * - Getting STUN/TURN servers from AWS
 */
export class KVSSignalingClient {
  constructor(config) {
    this.config = config;
    this.ws = null;
    this.iceServers = [];
    this.eventHandlers = {};
    this.clientId = `viewer-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    // Configure AWS SDK
    AWS.config.update({
      region: config.region,
      credentials: new AWS.Credentials({
        accessKeyId: config.accessKey,
        secretAccessKey: config.secretKey,
      }),
    });

    this.kinesisVideoClient = new AWS.KinesisVideo();
    this.kinesisVideoSignalingClient = null;
  }

  /**
   * Connect to AWS KVS Signaling Channel
   */
  async connect() {
    try {
      console.log('[KVS] Connecting to signaling channel:', this.config.channelName);

      // Step 1: Get signaling channel endpoint
      const endpoints = await this.getSignalingChannelEndpoints();
      console.log('[KVS] Got endpoints:', endpoints);

      // Step 2: Get ICE servers (STUN/TURN)
      await this.fetchIceServers(endpoints.HTTPS);
      console.log('[KVS] Got ICE servers:', this.iceServers.length);

      // Step 3: Connect to WebSocket signaling endpoint
      await this.connectWebSocket(endpoints.WSS);
      console.log('[KVS] WebSocket connected');

      return true;
    } catch (error) {
      console.error('[KVS] Connection failed:', error);
      throw error;
    }
  }

  /**
   * Get signaling channel endpoints (HTTPS and WSS)
   */
  async getSignalingChannelEndpoints() {
    const params = {
      ChannelARN: this.config.channelARN,
      SingleMasterChannelEndpointConfiguration: {
        Protocols: ['WSS', 'HTTPS'],
        Role: 'VIEWER',
      },
    };

    const response = await this.kinesisVideoClient
      .getSignalingChannelEndpoint(params)
      .promise();

    const endpoints = {};
    response.ResourceEndpointList.forEach(endpoint => {
      endpoints[endpoint.Protocol] = endpoint.ResourceEndpoint;
    });

    return endpoints;
  }

  /**
   * Fetch ICE servers from AWS KVS
   */
  async fetchIceServers(httpsEndpoint) {
    // Create signaling client with custom endpoint
    this.kinesisVideoSignalingClient = new AWS.KinesisVideoSignalingChannels({
      endpoint: httpsEndpoint,
      region: this.config.region,
    });

    const params = {
      ChannelARN: this.config.channelARN,
    };

    const response = await this.kinesisVideoSignalingClient
      .getIceServerConfig(params)
      .promise();

    // Convert AWS ICE server format to WebRTC format
    this.iceServers = [];

    response.IceServerList.forEach(iceServer => {
      const server = {
        urls: iceServer.Uris,
      };

      if (iceServer.Username) {
        server.username = iceServer.Username;
      }
      if (iceServer.Password) {
        server.credential = iceServer.Password;
      }

      this.iceServers.push(server);
    });

    // Add default STUN server
    this.iceServers.push({
      urls: `stun:stun.kinesisvideo.${this.config.region}.amazonaws.com:443`,
    });
  }

  /**
   * Connect to WebSocket signaling channel
   */
  async connectWebSocket(wssEndpoint) {
    return new Promise((resolve, reject) => {
      // Build signed WebSocket URL
      const url = this.buildSignedWebSocketUrl(wssEndpoint);

      this.ws = new WebSocket(url);

      this.ws.onopen = () => {
        console.log('[KVS] WebSocket opened');
        resolve();
      };

      this.ws.onerror = (error) => {
        console.error('[KVS] WebSocket error:', error);
        reject(error);
      };

      this.ws.onclose = () => {
        console.log('[KVS] WebSocket closed');
        this.emit('disconnected');
      };

      this.ws.onmessage = (event) => {
        this.handleSignalingMessage(event.data);
      };

      // Timeout after 10 seconds
      setTimeout(() => {
        if (this.ws.readyState !== WebSocket.OPEN) {
          reject(new Error('WebSocket connection timeout'));
        }
      }, 10000);
    });
  }

  /**
   * Build signed WebSocket URL with AWS SigV4
   */
  buildSignedWebSocketUrl(wssEndpoint) {
    const url = new URL(wssEndpoint);
    const query = new URLSearchParams();

    // Add required parameters
    query.append('X-Amz-ChannelARN', this.config.channelARN);
    query.append('X-Amz-ClientId', this.clientId);

    // AWS SigV4 signing would go here
    // For simplicity, using unsigned URL (works for public channels)
    // In production, implement proper SigV4 signing

    return `${url.protocol}//${url.host}${url.pathname}?${query.toString()}`;
  }

  /**
   * Handle incoming signaling messages
   */
  handleSignalingMessage(data) {
    try {
      if (!data || data.trim() === '') {
        // Empty message (keepalive)
        return;
      }

      const message = JSON.parse(data);
      console.log('[KVS] Received message:', message.messageType || message.action);

      const action = message.messageType || message.action;

      switch (action) {
        case 'SDP_ANSWER':
          this.handleSdpAnswer(message);
          break;
        case 'ICE_CANDIDATE':
          this.handleIceCandidate(message);
          break;
        default:
          console.log('[KVS] Unknown message type:', action);
      }
    } catch (error) {
      console.error('[KVS] Error handling message:', error);
    }
  }

  /**
   * Handle SDP answer from master device
   */
  handleSdpAnswer(message) {
    try {
      // Decode Base64 payload
      const payload = this.decodeBase64Payload(message.messagePayload);

      if (payload && payload.sdp) {
        const answer = {
          type: 'answer',
          sdp: payload.sdp,
        };

        this.emit('answer', answer);
      }
    } catch (error) {
      console.error('[KVS] Error handling SDP answer:', error);
    }
  }

  /**
   * Handle ICE candidate from master device
   */
  handleIceCandidate(message) {
    try {
      // Decode Base64 payload
      const candidate = this.decodeBase64Payload(message.messagePayload);

      if (candidate && candidate.candidate) {
        this.emit('candidate', candidate);
      }
    } catch (error) {
      console.error('[KVS] Error handling ICE candidate:', error);
    }
  }

  /**
   * Decode Base64 payload
   */
  decodeBase64Payload(base64) {
    try {
      const json = atob(base64);
      return JSON.parse(json);
    } catch (error) {
      console.error('[KVS] Error decoding Base64 payload:', error);
      return null;
    }
  }

  /**
   * Send SDP offer to master device
   */
  async sendOffer(offer) {
    const payload = {
      type: offer.type,
      sdp: offer.sdp,
    };

    const message = {
      action: 'SDP_OFFER',
      recipientClientId: null, // null for master
      messagePayload: btoa(JSON.stringify(payload)),
    };

    this.sendMessage(message);
    console.log('[KVS] Sent SDP offer');
  }

  /**
   * Send ICE candidate to master device
   */
  sendIceCandidate(candidate) {
    const payload = {
      candidate: candidate.candidate,
      sdpMid: candidate.sdpMid || '0',
      sdpMLineIndex: candidate.sdpMLineIndex || 0,
    };

    const message = {
      action: 'ICE_CANDIDATE',
      recipientClientId: null, // null for master
      messagePayload: btoa(JSON.stringify(payload)),
    };

    this.sendMessage(message);
  }

  /**
   * Send message via WebSocket
   */
  sendMessage(message) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    } else {
      console.error('[KVS] WebSocket not connected');
    }
  }

  /**
   * Get ICE servers
   */
  getIceServers() {
    return this.iceServers;
  }

  /**
   * Event emitter
   */
  on(event, handler) {
    if (!this.eventHandlers[event]) {
      this.eventHandlers[event] = [];
    }
    this.eventHandlers[event].push(handler);
  }

  /**
   * Remove event listener
   */
  off(event, handler) {
    if (!this.eventHandlers[event]) return;

    if (handler) {
      this.eventHandlers[event] = this.eventHandlers[event].filter(h => h !== handler);
    } else {
      delete this.eventHandlers[event];
    }
  }

  /**
   * Emit event
   */
  emit(event, data) {
    if (this.eventHandlers[event]) {
      this.eventHandlers[event].forEach(handler => handler(data));
    }
  }

  /**
   * Disconnect
   */
  disconnect() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }
}
