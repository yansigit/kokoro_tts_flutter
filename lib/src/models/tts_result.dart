import 'dart:typed_data';

/// Represents the result of a text-to-speech operation
class TtsResult {
  /// The generated audio samples
  final Float32List audio;
  
  /// The sample rate of the audio
  final int sampleRate;
  
  /// Duration of the audio in seconds
  final double duration;
  
  /// The phonemes that were used to generate the audio
  final String phonemes;
  
  /// Creates a TTS result
  const TtsResult({
    required this.audio,
    required this.sampleRate,
    required this.duration,
    required this.phonemes,
  });
  
  /// Convert the audio samples to a PCM audio buffer
  Float64List toPcm() {
    final pcm = Float64List(audio.length);
    for (int i = 0; i < audio.length; i++) {
      // Convert to the range [-1.0, 1.0]
      pcm[i] = audio[i].toDouble();
    }
    return pcm;
  }
  
  /// Convert to Int16 audio for playback compatibility
  Int16List toInt16PCM() {
    final pcm = Int16List(audio.length);
    for (int i = 0; i < audio.length; i++) {
      // Convert float to int16 range
      final sample = (audio[i] * 32767).round().clamp(-32768, 32767);
      pcm[i] = sample;
    }
    return pcm;
  }
}
