/**
 * AWS KVS WebRTC Viewer App
 * Viewer-Only Mode - No Microphone Permission Required
 */

import React from 'react';
import { SafeAreaView, StyleSheet } from 'react-native';
import ViewerScreen from './src/screens/ViewerScreen';

const App = () => {
  return (
    <SafeAreaView style={styles.container}>
      <ViewerScreen />
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
});

export default App;
