import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'audio_utils.dart';
import 'tokenizer.dart';
import 'models/voice.dart';
import 'models/tts_result.dart';
import 'onnx_model_runner.dart';

/// Core Kokoro TTS engine for Flutter
class Kokoro {
  /// The configuration for this Kokoro instance
  final KokoroConfig config;

  /// The tokenizer used for text-to-phoneme conversion
  late final Tokenizer _tokenizer;

  /// The loaded voices
  late final Map<String, Voice> _voices;

  /// The ONNX model runner (will handle inference)
  late final OnnxModelRunner _modelRunner;

  bool _isInitialized = false;

  /// Creates a new Kokoro TTS engine
  ///
  /// The [config] specifies the paths to the model and voice files
  Kokoro(this.config) {
    _tokenizer = Tokenizer();
  }

  /// Initialize the Kokoro TTS engine
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Validate configuration
    config.validate();

    // Initialize tokenizer
    await _tokenizer.ensureInitialized();

    // Load voices
    await _loadVoices();

    // Initialize model
    // Load model from assets and pass to model runner
    _modelRunner = OnnxModelRunner(modelPath: config.modelPath);
    await _modelRunner.initialize();

    _isInitialized = true;
  }

  /// Ensures the Kokoro engine is initialized
  Future<void> ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// Gets the map of available voices
  Map<String, Voice> get availableVoices {
    if (!_isInitialized) {
      throw StateError('Kokoro is not initialized. Call initialize() first.');
    }
    return Map.unmodifiable(_voices);
  }

  /// Loads the voices from the voices.json file
  Future<void> _loadVoices() async {
    try {
      // Load voices from the JSON asset (converted from voices-v1.0.bin)
      final String jsonString =
          await rootBundle.loadString('assets/voices.json');
      final Map<String, dynamic> voicesData = jsonDecode(jsonString);

      // Create a map of voice objects
      final Map<String, Voice> voiceMap = {};

      // Process each voice in the JSON
      for (final voiceName in voicesData.keys) {
        try {
          // Each voice has an array of style vectors in the JSON
          final List<dynamic> styleVectors = voicesData[voiceName];

          // Process style vectors with better error handling
          final List<Float32List> processedVectors = [];

          for (final vector in styleVectors) {
            if (vector is List) {
              try {
                final List<double> doubleList = [];
                List<dynamic> listToProcess;

                // Check for the wrapped list case, e.g., [[0.1, 0.2, ...]]
                if (vector.isNotEmpty && vector.first is List) {
                  if (vector.length == 1) {
                    // Ensure it's a single wrapped list
                    listToProcess = vector.first as List<dynamic>;
                    // debugPrint('Info: Handling wrapped style vector for $voiceName.');
                  } else {
                    debugPrint(
                        'Warning: Unexpected multi-list structure for a style vector in $voiceName: $vector. Using empty vector for this entry.');
                    processedVectors.add(Float32List(0));
                    continue; // Skip to the next style vector in styleVectors
                  }
                } else {
                  // Standard case: vector is already [0.1, 0.2, ...]
                  listToProcess = vector;
                }

                for (final value in listToProcess) {
                  if (value is num) {
                    doubleList.add(value.toDouble());
                  } else if (value is String) {
                    // Try to parse strings as doubles
                    try {
                      doubleList.add(double.parse(value));
                    } catch (e) {
                      debugPrint(
                          'Warning: Could not parse "$value" as double in voice $voiceName. Using 0.0.');
                      doubleList.add(0.0);
                    }
                  } else if (value is bool) {
                    // Convert booleans to 1.0 (true) or 0.0 (false)
                    doubleList.add(value ? 1.0 : 0.0);
                  } else if (value == null) {
                    // Handle null values as 0.0
                    doubleList.add(0.0);
                  } else {
                    debugPrint(
                        'Warning: Unexpected type ${value.runtimeType} in style vector data for $voiceName. Value: "$value". Using 0.0.');
                    doubleList.add(0.0);
                  }
                }
                processedVectors.add(Float32List.fromList(doubleList));
              } catch (e) {
                debugPrint(
                    'Error processing vector in voice $voiceName: $e. Raw vector: $vector');
                // Add an empty vector as fallback
                processedVectors.add(Float32List(0));
              }
            } else {
              debugPrint(
                  'Warning: Expected List for style vector entry in $voiceName, got ${vector.runtimeType}. Content: $vector');
              // Add an empty vector as fallback
              processedVectors.add(Float32List(0));
            }
          }

          // Ensure we have at least one style vector
          if (processedVectors.isEmpty) {
            debugPrint(
                'Warning: No valid style vectors for voice $voiceName, adding dummy vector');
            final dummyVector = Float32List(1);
            dummyVector[0] = 0.0;
            processedVectors.add(dummyVector);
          }

          // Create a voice object with the processed style vectors
          voiceMap[voiceName] = Voice(
            id: voiceName,
            name: _formatVoiceName(voiceName),
            styleVectors: processedVectors,
            languageCode: _getLanguageCodeFromVoiceName(voiceName),
            gender: _getGenderFromVoiceName(voiceName),
          );

          debugPrint(
              'Successfully loaded voice $voiceName with ${processedVectors.length} style vectors');
        } catch (e) {
          debugPrint('Error processing voice $voiceName: $e');
          // Skip this voice and continue with others
        }
      }

      // Ensure we have at least one voice
      if (voiceMap.isEmpty) {
        throw Exception('No valid voices could be loaded from voices.json');
      }

      _voices = voiceMap;
      debugPrint(
          'Successfully loaded ${_voices.length} voices from voices.json');
    } catch (e) {
      throw Exception(
          'Failed to load voices from asset assets/voices.json: $e');
    }
  }

  /// Format a voice name for display (e.g., 'af_heart' -> 'African Heart')
  String _formatVoiceName(String voiceId) {
    // Split by underscore
    final parts = voiceId.split('_');
    if (parts.length < 2) return voiceId;

    // Format each part with capitalization
    final formattedParts = parts.map((part) {
      if (part.isEmpty) return '';
      return part[0].toUpperCase() + part.substring(1);
    });

    return formattedParts.join(' ');
  }

  /// Get language code from voice name (simple heuristic)
  String _getLanguageCodeFromVoiceName(String voiceId) {
    // This is a simple heuristic - in a real app, you'd have a mapping table
    if (voiceId.startsWith('fr_')) return 'fr-fr';
    if (voiceId.startsWith('es_')) return 'es-es';
    if (voiceId.startsWith('de_')) return 'de-de';
    if (voiceId.startsWith('it_')) return 'it-it';
    if (voiceId.startsWith('zh_')) return 'zh-cn';
    if (voiceId.startsWith('ja_')) return 'ja-jp';
    // Default to English
    return 'en-us';
  }

  /// Get gender from voice name (simple heuristic)
  String _getGenderFromVoiceName(String voiceId) {
    // This is a simple heuristic - in a real app, you'd have a mapping table
    if (voiceId.contains('female')) return 'female';
    if (voiceId.contains('male')) return 'male';
    // Default to neutral
    return 'neutral';
  }

  /// Splits phonemes into batches to process in chunks
  List<String> _splitPhonemes(String phonemes) {
    // For testing purposes, and to simplify the current debugging path,
    // always return the phoneme string as a single batch.
    // This ensures that the tokenization step receives the exact phoneme string
    // with punctuation intact, as provided to createTTS.
    // TODO: Revisit proper batching logic for very long phoneme strings if necessary.
    return [phonemes];
  }

  /// Creates audio from the provided text using the specified voice and settings
  Future<TtsResult> createTTS({
    required String text,
    required dynamic voice, // Can be String (voice ID) or Voice object
    double speed = 1.0,
    String lang = 'en-us',
    bool isPhonemes = false,
    bool trim = true,
  }) async {
    await ensureInitialized();
    debugPrint('Dart createTTS: Input text: "$text"');
    debugPrint(
        'Dart createTTS: Voice (raw): $voice, Language: $lang, Speed: $speed, IsPhonemes: $isPhonemes');

    assert(speed >= 0.5 && speed <= 2.0, 'Speed should be between 0.5 and 2.0');

    // Resolve voice
    late Voice voiceObj;
    if (voice is String) {
      if (!_voices.containsKey(voice)) {
        throw ArgumentError('Voice $voice not found in available voices');
      }
      voiceObj = _voices[voice]!;
    } else if (voice is Voice) {
      voiceObj = voice;
    } else {
      throw ArgumentError('Voice must be a String ID or Voice object');
    }
    debugPrint('Dart createTTS: Resolved Voice ID: ${voiceObj.id}');

    // Get phonemes
    String phonemes;
    if (isPhonemes) {
      phonemes = text;
    } else {
      phonemes = await _tokenizer.phonemize(text, lang: lang);
    }
    debugPrint('Dart createTTS: Generated/Provided Phonemes: "$phonemes"');

    // Split into batches for processing
    final batches = _splitPhonemes(phonemes);

    // Process each batch
    final audioBuffers = <Float32List>[];
    for (final batch in batches) {
      debugPrint('Dart createTTS Batch: Processing phoneme batch: "$batch"');
      // Convert phonemes to token IDs
      final List<int> tokens = _tokenizer.tokenize(batch);
      debugPrint('Dart: Unpadded Tokens for batch: $tokens');

      // Get the appropriate style vector for this token length
      // This is the key alignment with kokoro-onnx: selecting style vector based on token count
      final Float32List styleVector =
          voiceObj.getStyleVectorForTokens(tokens.length);
      String styleVecStr;
      if (styleVector.length <= 20) {
        styleVecStr = styleVector.map((e) => e.toStringAsFixed(4)).join(', ');
      } else {
        styleVecStr =
            '${styleVector.sublist(0, 10).map((e) => e.toStringAsFixed(4)).join(', ')}...${styleVector.sublist(styleVector.length - 10).map((e) => e.toStringAsFixed(4)).join(', ')}';
      }
      debugPrint(
          'Dart Batch: Style Vector (length ${styleVector.length}): [$styleVecStr]');
      debugPrint('Using style vector for token length ${tokens.length}');

      // Run inference
      final audio = await _modelRunner.runInference(
        tokens: tokens,
        voice: styleVector,
        speed: speed,
      );

      debugPrint('Dart Batch: Raw audio from model (length: ${audio.length})');
      if (audio.isNotEmpty) {
        String audioStartStr = audio
            .sublist(0, (audio.length > 10 ? 10 : audio.length))
            .map((e) => e.toStringAsFixed(4))
            .join(', ');
        String audioEndStr = audio.length > 10
            ? audio
                .sublist(audio.length - (audio.length > 10 ? 10 : 0))
                .map((e) => e.toStringAsFixed(4))
                .join(', ')
            : '';
        double minVal = audio.reduce((a, b) => a < b ? a : b);
        double maxVal = audio.reduce((a, b) => a > b ? a : b);
        debugPrint('Dart Batch: Raw audio Start: [$audioStartStr]');
        if (audioEndStr.isNotEmpty && audio.length > 10) {
          // ensure audioEndStr is meaningful
          debugPrint('Dart Batch: Raw audio End: [$audioEndStr]');
        }
        debugPrint(
            'Dart Batch: Raw audio Min/Max: ${minVal.toStringAsFixed(4)} / ${maxVal.toStringAsFixed(4)}');
      } else {
        debugPrint('Dart Batch: Raw audio is empty.');
      }

      // Apply trimming if requested
      Float32List processedAudio = audio;
      if (trim) {
        // Trim leading and trailing silence
        final (trimmedAudio, _) = AudioUtils.trimSilence(audio);
        processedAudio = trimmedAudio;
      }

      audioBuffers.add(processedAudio);
    }

    // Concatenate audio buffers
    final combinedAudio = AudioUtils.concatenateAudio(audioBuffers);

    // Calculate duration
    final duration = combinedAudio.length / sampleRate;

    return TtsResult(
      audio: combinedAudio,
      sampleRate: sampleRate,
      duration: duration,
      phonemes: phonemes,
    );
  }

  /// Stream audio generation for longer texts
  Stream<TtsResult> createTTSStream({
    required String text,
    required dynamic voice,
    double speed = 1.0,
    String lang = 'en-us',
    bool isPhonemes = false,
    bool trim = true,
  }) async* {
    await ensureInitialized();

    assert(speed >= 0.5 && speed <= 2.0, 'Speed should be between 0.5 and 2.0');

    // Resolve voice
    late Voice voiceObj;
    if (voice is String) {
      if (!_voices.containsKey(voice)) {
        throw ArgumentError('Voice $voice not found in available voices');
      }
      voiceObj = _voices[voice]!;
    } else if (voice is Voice) {
      voiceObj = voice;
    } else {
      throw ArgumentError('Voice must be a String ID or Voice object');
    }

    // Get phonemes
    String phonemes;
    if (isPhonemes) {
      phonemes = text;
    } else {
      phonemes = await _tokenizer.phonemize(text, lang: lang);
    }

    // Split into batches for processing
    final batches = _splitPhonemes(phonemes);

    // Stream each batch
    for (final batch in batches) {
      final tokens = _tokenizer.tokenize(batch);

      // Run inference
      final audio = await _modelRunner.runInference(
        tokens: tokens,
        voice: voiceObj.getStyleVectorForTokens(tokens.length),
        speed: speed,
      );

      // Apply trimming if requested
      Float32List processedAudio = audio;
      if (trim) {
        // Trim leading and trailing silence
        final (trimmedAudio, _) = AudioUtils.trimSilence(audio);
        processedAudio = trimmedAudio;
      }

      // Calculate duration
      final duration = processedAudio.length / sampleRate;

      yield TtsResult(
        audio: processedAudio,
        sampleRate: sampleRate,
        duration: duration,
        phonemes: batch,
      );
    }
  }

  /// Get a list of available voice IDs
  List<String> getVoices() {
    return _voices.keys.toList()..sort();
  }

  /// Get a specific voice by ID
  Voice? getVoice(String id) {
    return _voices[id];
  }

  /// Close resources used by the TTS engine
  Future<void> dispose() async {
    if (_isInitialized) {
      await _modelRunner.dispose();
      _isInitialized = false;
    }
  }
}
