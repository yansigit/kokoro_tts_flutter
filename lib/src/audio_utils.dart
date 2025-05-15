import 'dart:math' as math;
import 'dart:typed_data';

/// Audio processing utilities for Kokoro TTS
class AudioUtils {
  /// Trims silence from the beginning and end of an audio buffer
  /// 
  /// This is a Dart port of the trim function from Kokoro-ONNX
  /// Returns a tuple of the trimmed audio and the indices [start, end]
  static (Float32List, List<int>) trimSilence(
    Float32List audio, {
    double topDb = 60.0,
    int frameLength = 2048,
    int hopLength = 512,
  }) {
    // Calculate non-silent frames
    final nonSilent = _signalToFrameNonSilent(
      audio,
      frameLength: frameLength,
      hopLength: hopLength,
      topDb: topDb,
    );

    // Find indices of non-silent frames
    final nonZero = <int>[];
    for (int i = 0; i < nonSilent.length; i++) {
      if (nonSilent[i]) {
        nonZero.add(i);
      }
    }

    if (nonZero.isNotEmpty) {
      // Calculate start and end samples from frame indices
      final start = _framesToSamples(nonZero.first, hopLength: hopLength);
      final end = math.min(
        audio.length,
        _framesToSamples(nonZero.last + 1, hopLength: hopLength),
      );

      // Create trimmed audio buffer
      final trimmedAudio = Float32List(end - start);
      for (int i = 0; i < trimmedAudio.length; i++) {
        trimmedAudio[i] = audio[start + i];
      }

      return (trimmedAudio, [start, end]);
    } else {
      // The entire signal is silent
      return (Float32List(0), [0, 0]);
    }
  }

  /// Calculate RMS (Root Mean Square) of audio frames
  /// 
  /// Returns the RMS values for each frame in the audio
  static Float32List rms(
    Float32List audio, {
    required int frameLength,
    required int hopLength,
  }) {
    // Calculate number of frames
    final numFrames = 1 + (audio.length - frameLength) ~/ hopLength;
    if (numFrames <= 0) {
      return Float32List(0);
    }

    final result = Float32List(numFrames);

    for (int i = 0; i < numFrames; i++) {
      final start = i * hopLength;
      final end = start + frameLength;
      if (end <= audio.length) {
        double sumSquares = 0.0;
        for (int j = start; j < end; j++) {
          sumSquares += audio[j] * audio[j];
        }
        result[i] = math.sqrt(sumSquares / frameLength);
      }
    }

    return result;
  }

  /// Determines which frames in the audio are non-silent
  static List<bool> _signalToFrameNonSilent(
    Float32List audio, {
    required int frameLength,
    required int hopLength,
    required double topDb,
  }) {
    // Compute RMS for the signal
    final mse = rms(audio, frameLength: frameLength, hopLength: hopLength);

    // Convert to decibels
    final db = _amplitudeToDb(mse, topDb: topDb);

    // Determine which frames are above the threshold
    return db.map((value) => value > -topDb).toList();
  }

  /// Convert amplitude to decibels
  static Float32List _amplitudeToDb(
    Float32List amplitude, {
    double ref = 1.0,
    double min = 1e-5,
    double? topDb,
  }) {
    final Float32List db = Float32List(amplitude.length);

    // Find maximum amplitude as reference if ref is null
    double refValue = ref;
    if (ref == 0) {
      refValue = amplitude.reduce(math.max);
      if (refValue == 0) refValue = min;
    }

    // Convert to dB
    double maxDb = double.negativeInfinity;
    for (int i = 0; i < amplitude.length; i++) {
      final double value = math.max(min, amplitude[i]);
      db[i] = 20.0 * math.log(value / refValue) / math.ln10;
      if (db[i] > maxDb) maxDb = db[i];
    }

    // Apply top_db threshold if specified
    if (topDb != null) {
      final threshold = maxDb - topDb;
      for (int i = 0; i < db.length; i++) {
        db[i] = math.max(db[i], threshold);
      }
    }

    return db;
  }

  /// Convert frame indices to sample indices
  static int _framesToSamples(int frame, {required int hopLength}) {
    return frame * hopLength;
  }

  /// Concatenates multiple audio buffers
  static Float32List concatenateAudio(List<Float32List> audioBuffers) {
    int totalLength = 0;
    for (final buffer in audioBuffers) {
      totalLength += buffer.length;
    }

    final result = Float32List(totalLength);
    int offset = 0;
    for (final buffer in audioBuffers) {
      for (int i = 0; i < buffer.length; i++) {
        result[offset + i] = buffer[i];
      }
      offset += buffer.length;
    }

    return result;
  }
}
