import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Generate TTS for Japanese sentences and alphabets written in English',
      () async {
    // 1. Example Japanese sentences written in English
    const String userInput =
        'Konnichiwa, watashi no namae wa Yuna desu. Hajimemashite. Nihongo wo benkyou shite imasu. Now let me say some alphabet letters like A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z. And now I say alphabet based brands, such as ABC, POP, VIP, MVP, and DDX.';

    developer.log('TEST INPUT: "$userInput"', name: 'kokoro_tts_flutter');

    // 2. Initialize Kokoro with the model and voices paths
    const config = KokoroConfig(
      modelPath: 'assets/kokoro-v1.0.onnx',
      voicesPath: 'assets/voices.json',
    );
    final kokoro = Kokoro(config);
    await kokoro.initialize();

    // 3. Use built-in tokenizer to phonemize input
    final tokenizer = Tokenizer();
    await tokenizer.ensureInitialized();
    var phonemes = await tokenizer.phonemize(userInput, lang: 'en-us');

    // Log the phonemes for debugging
    developer.log('Phonemized text: $phonemes', name: 'kokoro_tts_flutter');

    // 4. Create TTS audio using the phonemes and a voice
    final availableVoices = kokoro.availableVoices;
    developer.log('Available voices: ${availableVoices.keys.join(', ')}');

    // Use a Japanese voice if available, otherwise use the first available voice
    final String voiceId = availableVoices.containsKey('af_heart')
        ? 'af_heart'
        : availableVoices.keys.first;

    final ttsResult = await kokoro.createTTS(
      text: phonemes,
      voice: voiceId,
      isPhonemes: true,
    );

    // 5. Save the audio as a WAV file
    final pcm = ttsResult.toInt16PCM();
    final wavBytes = _writeWavFile(pcm, ttsResult.sampleRate);

    // Get temporary directory to save the file
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/japanese_sentences.wav';
    await File(filePath).writeAsBytes(wavBytes);

    // Play the audio file with just_audio
    final player = AudioPlayer();
    await player.setFilePath(filePath);
    await player.play();

    developer.log('Audio saved to $filePath', name: 'kokoro_tts_flutter');

    // 6. Verify the audio file exists and has content
    final file = File(filePath);
    expect(await file.exists(), true);
    expect((await file.readAsBytes()).isNotEmpty, true);
  });

  test('Generate TTS for medical terms and names', () async {
    // 1. Example user input with complex medical terms
    const String userInput =
        'Speak medicines like aspirin and paracetamol. Speak devices like stethoscope. Speak conditions like diabetes and asthma.';

    developer.log('TEST INPUT: "$userInput"', name: 'kokoro_tts_flutter');

    // 2. Initialize Kokoro with the model and voices paths
    const config = KokoroConfig(
      modelPath: 'assets/kokoro-v1.0.onnx',
      voicesPath: 'assets/voices.json',
    );
    final kokoro = Kokoro(config);
    await kokoro.initialize();

    // 3. Use built-in tokenizer to phonemize input
    final tokenizer = Tokenizer();
    await tokenizer.ensureInitialized();
    var phonemes = await tokenizer.phonemize(userInput, lang: 'en-us');

    // Log the phonemes for debugging
    developer.log('Phonemized text: $phonemes', name: 'kokoro_tts_flutter');

    // 4. Create TTS audio using the phonemes and a voice
    final availableVoices = kokoro.availableVoices;
    developer.log('Available voices: ${availableVoices.keys.join(', ')}');

    // Use 'af_heart' voice if available, otherwise use the first available voice
    final String voiceId = availableVoices.containsKey('af_heart')
        ? 'af_heart'
        : availableVoices.keys.first;

    final ttsResult = await kokoro.createTTS(
      text: phonemes,
      voice: voiceId,
      isPhonemes: true,
    );

    // 5. Save the audio as a WAV file
    final pcm = ttsResult.toInt16PCM();
    final wavBytes = _writeWavFile(pcm, ttsResult.sampleRate);

    // Get temporary directory to save the file
    final tempDir = await getTemporaryDirectory();
    final filePath = '${tempDir.path}/medical_terms.wav';
    await File(filePath).writeAsBytes(wavBytes);

    // Play the audio file with just_audio
    final player = AudioPlayer();
    await player.setFilePath(filePath);
    await player.play();

    developer.log('Audio saved to $filePath', name: 'kokoro_tts_flutter');

    // 6. Verify the audio file exists and has content
    final file = File(filePath);
    expect(await file.exists(), true);
    expect((await file.readAsBytes()).isNotEmpty, true);
  });

  test('Generate TTS for foreign names.', () async {
    // 1. Example user input
    const String userInput =
        'Speak some chinese names like Wang, Li, Zhang, and Zhao. Also speak some japanese names like Tanaka, Yamada, and Nakamura. Also speak some korean names like Kim, Lee, Yoon, Jung, and Park.';

    developer.log('TEST INPUT: "$userInput"', name: 'kokoro_tts_flutter');

    // 2. Initialize Kokoro with the model and voices paths
    const config = KokoroConfig(
      modelPath: 'assets/kokoro-v1.0.onnx',
      voicesPath: 'assets/voices.json',
    );
    final kokoro = Kokoro(config);
    await kokoro.initialize();

    // 3. Use built-in tokenizer to phonemize input (like malsami G2P in the Python example)
    final tokenizer = Tokenizer();
    await tokenizer.ensureInitialized();
    var phonemes = await tokenizer.phonemize(userInput, lang: 'en-us');

    // *** Add this line to see raw G2P output clearly ***
    developer.log('DEBUG: Raw Flutter G2P Output: $phonemes');

    // 4. Create TTS audio using the phonemes and a voice
    // First, get available voices
    final availableVoices = kokoro.availableVoices;
    developer.log('Available voices: ${availableVoices.keys.join(', ')}');

    // Try to use 'af_heart' voice if available, otherwise use the first available voice
    final String voiceId = availableVoices.containsKey('af_heart')
        ? 'af_heart'
        : availableVoices.keys.first;
    developer.log('Using voice: $voiceId');

    final ttsResult = await kokoro.createTTS(
      text: phonemes,
      voice: voiceId,
      isPhonemes: true,
    );

    // 5. Convert to WAV format
    final pcm = ttsResult.toInt16PCM();
    final wavBytes = _writeWavFile(pcm, ttsResult.sampleRate);

    // 6. Save the audio to a file in a writable directory
    final dir = await getApplicationDocumentsDirectory();
    final outputPath = '${dir.path}/audio.wav';
    final file = File(outputPath);
    await file.writeAsBytes(wavBytes);

    // 7. Play the audio file with just_audio
    final player = AudioPlayer();
    await player.setFilePath(outputPath);
    await player.play();

    // Wait for the audio to finish playing
    await Future.delayed(
        Duration(milliseconds: (ttsResult.duration * 1000).round()));
    await player.dispose();

    // 8. Log the size and duration of the generated audio
    developer.log('Audio size (bytes): ${wavBytes.length}');
    developer.log('Audio duration (seconds): ${ttsResult.duration}');

    // 9. Verify the file was created and has content
    expect(await file.exists(), true, reason: 'Audio file should be created');
    expect(await file.length(), greaterThan(1000),
        reason: 'Audio file should have content');
    developer.log('Created audio.wav'); // Same output as in the Python example

    // 8. Clean up
    await file.delete();
  }, timeout: const Timeout(Duration(minutes: 2)));
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
