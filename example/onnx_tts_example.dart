import 'dart:io';
import 'dart:typed_data';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';

/// Example demonstrating how to use Kokoro TTS with ONNX Runtime
///
/// This example follows the structure of the Python example in kokoro-onnx/examples/english.py
/// but uses the malsami library for phonemization instead of malsami
///
/// Equivalent Python code:
/// ```python
/// import soundfile as sf
/// from malsami import en, espeak
/// from kokoro_onnx import Kokoro
///
/// # Malsami G2P with espeak-ng fallback
/// fallback = espeak.EspeakFallback(british=False)
/// g2p = en.G2P(trf=False, british=False, fallback=fallback)
///
/// # Kokoro
/// kokoro = Kokoro("kokoro-v1.0.onnx", "voices-v1.0.bin")
///
/// # Phonemize
/// text = "[Malsami](/misˈɑki/) is a G2P engine designed for [Kokoro](/kˈOkəɹO/) models."
/// phonemes, _ = g2p(text)
///
/// # Create
/// samples, sample_rate = kokoro.create(phonemes, "af_heart", is_phonemes=True)
///
/// # Save
/// sf.write("audio.wav", samples, sample_rate)
/// ```
void main() async {
  // Initialize Kokoro with the ONNX model and voices paths
  // This is equivalent to: kokoro = Kokoro("kokoro-v1.0.onnx", "voices-v1.0.bin")
  const config = KokoroConfig(
    modelPath: 'assets/kokoro-v1.0.onnx',
    voicesPath: 'assets/voices-v1.0.bin',
  );

  final kokoro = Kokoro(config);
  await kokoro.initialize();

  // Input text to phonemize - using the same text as in the Python example
  const text =
      "[Malsami](/malsami/) is a G2P engine designed for [Kokoro](/kokoro/) models.";

  // Use the built-in tokenizer which is equivalent to malsami G2P in this context
  // This is equivalent to: phonemes, _ = g2p(text)
  final tokenizer = Tokenizer();
  await tokenizer.ensureInitialized();
  final phonemes = await tokenizer.phonemize(text, lang: 'en-us');
  print('Phonemized text: $phonemes');

  // Create TTS audio using the phonemes and a voice
  // This is equivalent to: samples, sample_rate = kokoro.create(phonemes, "af_heart", is_phonemes=True)
  final ttsResult = await kokoro.createTTS(
    text: phonemes,
    voice: 'af_heart', // Using the same voice as the Python example
    isPhonemes: true,
  );

  // Save the audio to a WAV file
  // This is equivalent to: sf.write("audio.wav", samples, sample_rate)
  final pcm = ttsResult.toInt16PCM();
  final wavFile = File('audio.wav'); // Same filename as Python example

  // Write WAV header and audio data
  final wavBytes = _writeWavFile(pcm, ttsResult.sampleRate);
  await wavFile.writeAsBytes(wavBytes);

  print('Created audio.wav'); // Same output message as Python example
}

/// Helper to write a WAV file from PCM data
List<int> _writeWavFile(List<int> pcm, int sampleRate) {
  final int byteRate = sampleRate * 2;
  const int blockAlign = 2;
  final int dataLength = pcm.length * 2;
  final int fileLength = 44 + dataLength;

  final builder = BytesBuilder();

  // WAV header
  builder.add([0x52, 0x49, 0x46, 0x46]); // 'RIFF'
  builder.add(_intToBytes(fileLength - 8, 4));
  builder.add([0x57, 0x41, 0x56, 0x45]); // 'WAVE'
  builder.add([0x66, 0x6d, 0x74, 0x20]); // 'fmt '
  builder.add(_intToBytes(16, 4)); // PCM chunk size
  builder.add(_intToBytes(1, 2)); // Audio format (1 = PCM)
  builder.add(_intToBytes(1, 2)); // Num channels
  builder.add(_intToBytes(sampleRate, 4));
  builder.add(_intToBytes(byteRate, 4));
  builder.add(_intToBytes(blockAlign, 2));
  builder.add(_intToBytes(16, 2)); // Bits per sample
  builder.add([0x64, 0x61, 0x74, 0x61]); // 'data'
  builder.add(_intToBytes(dataLength, 4));

  // Add PCM data
  if (pcm is Int16List) {
    builder.add(pcm.buffer.asUint8List());
  } else {
    final int16Data = Int16List(pcm.length);
    for (int i = 0; i < pcm.length; i++) {
      int16Data[i] = pcm[i];
    }
    builder.add(int16Data.buffer.asUint8List());
  }

  return builder.takeBytes();
}

/// Convert an integer to bytes in little-endian format
List<int> _intToBytes(int value, int byteCount) {
  final bytes = <int>[];
  for (int i = 0; i < byteCount; i++) {
    bytes.add((value >> (i * 8)) & 0xFF);
  }
  return bytes;
}
