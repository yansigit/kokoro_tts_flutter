import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'Generate TTS audio file following kokoro-onnx/examples/english.py pattern',
      () async {
    // 1. Example user input
    const String userInput =
        'Malsami is a G2P engine designed for Kokoro models.';

    // 2. Initialize Kokoro with the model and voices paths
    const config = KokoroConfig(
      modelPath: 'assets/kokoro-v1.0.onnx',
      voicesPath: 'assets/voices-v1.0.bin',
    );
    final kokoro = Kokoro(config);
    await kokoro.initialize();

    // 3. Use built-in tokenizer to phonemize input (like malsami G2P in the Python example)
    final tokenizer = Tokenizer();
    await tokenizer.ensureInitialized();
    final phonemes = await tokenizer.phonemize(userInput, lang: 'en-us');
    print('Phonemized text: $phonemes');

    // 4. Create TTS audio using the phonemes and a voice
    final ttsResult = await kokoro.createTTS(
      text: phonemes,
      voice: 'af_heart', // Same voice as in the Python example
      isPhonemes: true,
    );

    // 5. Convert to WAV format
    final pcm = ttsResult.toInt16PCM();
    final wavBytes = _writeWavFile(pcm, ttsResult.sampleRate);

    // 6. Save the audio to a file
    const outputPath = 'audio.wav'; // Same filename as in the Python example
    final file = File(outputPath);
    await file.writeAsBytes(wavBytes);

    // 7. Verify the file was created and has content
    expect(await file.exists(), true, reason: 'Audio file should be created');
    expect(await file.length(), greaterThan(1000),
        reason: 'Audio file should have content');
    print('Created audio.wav'); // Same output as in the Python example

    // 8. Clean up
    await file.delete();
  });
}

/// Helper to write a minimal WAV file from PCM data
List<int> _writeWavFile(Int16List pcm, int sampleRate) {
  final int byteRate = sampleRate * 2;
  const int blockAlign = 2;
  final int dataLength = pcm.length * 2;
  final int fileLength = 44 + dataLength;
  final bytes = BytesBuilder();
  bytes.add([0x52, 0x49, 0x46, 0x46]); // 'RIFF'
  bytes.add(_intToBytes(fileLength - 8, 4));
  bytes.add([0x57, 0x41, 0x56, 0x45]); // 'WAVE'
  bytes.add([0x66, 0x6d, 0x74, 0x20]); // 'fmt '
  bytes.add(_intToBytes(16, 4)); // PCM chunk size
  bytes.add(_intToBytes(1, 2)); // Audio format (1 = PCM)
  bytes.add(_intToBytes(1, 2)); // Num channels
  bytes.add(_intToBytes(sampleRate, 4));
  bytes.add(_intToBytes(byteRate, 4));
  bytes.add(_intToBytes(blockAlign, 2));
  bytes.add(_intToBytes(16, 2)); // Bits per sample
  bytes.add([0x64, 0x61, 0x74, 0x61]); // 'data'
  bytes.add(_intToBytes(dataLength, 4));
  bytes.add(pcm.buffer.asUint8List());
  return bytes.takeBytes();
}

List<int> _intToBytes(int value, int bytes) {
  final result = <int>[];
  for (var i = 0; i < bytes; i++) {
    result.add((value >> (8 * i)) & 0xFF);
  }
  return result;
}
