/**
 * AWS KVS Configuration Example
 *
 * Copy this file to config.js and fill in your AWS credentials.
 * DO NOT commit config.js to version control!
 */

export const KVS_CONFIG = {
  // Your KVS signaling channel name
  channelName: 'YOUR_CHANNEL_NAME',

  // Your KVS signaling channel ARN (get from AWS console)
  // Format: arn:aws:kinesisvideo:REGION:ACCOUNT_ID:channel/CHANNEL_NAME/TIMESTAMP
  channelARN: 'arn:aws:kinesisvideo:us-west-2:YOUR_ACCOUNT_ID:channel/YOUR_CHANNEL_NAME/TIMESTAMP',

  // AWS region where your KVS channel is located
  region: 'us-west-2',

  // AWS IAM credentials with KVS permissions
  // SECURITY WARNING: In production, use AWS Cognito or temporary credentials
  accessKey: 'YOUR_AWS_ACCESS_KEY',
  secretKey: 'YOUR_AWS_SECRET_KEY',
};

/**
 * Required IAM Permissions:
 *
 * {
 *   "Version": "2012-10-17",
 *   "Statement": [
 *     {
 *       "Effect": "Allow",
 *       "Action": [
 *         "kinesisvideo:DescribeSignalingChannel",
 *         "kinesisvideo:GetSignalingChannelEndpoint"
 *       ],
 *       "Resource": "arn:aws:kinesisvideo:*:*:channel/*"
 *     },
 *     {
 *       "Effect": "Allow",
 *       "Action": [
 *         "kinesisvideo:GetIceServerConfig"
 *       ],
 *       "Resource": "arn:aws:kinesisvideo:*:*:channel/*"
 *     }
 *   ]
 * }
 */
