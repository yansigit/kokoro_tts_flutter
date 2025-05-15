import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// A class that handles TTS model inference for Kokoro TTS using ONNX Runtime
///
/// This implementation is based on the kokoro-onnx Python library
class OnnxModelRunner {
  /// Path to the ONNX model file
  final String modelPath;

  /// Whether the model has been initialized
  bool _isInitialized = false;

  /// The ONNX Runtime session for inference
  OrtSession? _session;

  /// The ONNX Runtime instance
  late final OnnxRuntime _ort;

  /// Creates a new ONNX model runner with the given model path
  OnnxModelRunner({required this.modelPath}) {
    _ort = OnnxRuntime();
  }

  /// Initializes the ONNX model
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get preferred providers - follow similar logic to kokoro-onnx
      final providers = _getPreferredProviders();
      print('Using ONNX providers: $providers');

      // Load the model based on path
      if (modelPath.startsWith('assets/')) {
        // Load from Flutter assets
        _session = await _ort.createSessionFromAsset(modelPath);
      } else {
        // Load from file path
        _session = await _ort.createSession(modelPath);
      }

      _isInitialized = true;
    } catch (e) {
      throw Exception('Failed to initialize ONNX model: $e');
    }
  }

  /// Get preferred ONNX Runtime providers based on platform
  List<String> _getPreferredProviders() {
    // By default use CPU provider
    final providers = ['CPUExecutionProvider'];

    // TODO: Check for GPU providers when supported by flutter_onnxruntime
    // Currently flutter_onnxruntime doesn't expose provider selection

    return providers;
  }

  /// Run inference to generate audio from tokens and voice
  ///
  /// [tokens] is the list of token IDs to generate audio for
  /// [voice] is the voice style vector to use
  /// [speed] is the speed factor for the generated audio
  Future<Float32List> runInference({
    required List<int> tokens,
    required Float32List voice,
    required double speed,
  }) async {
    if (_session == null || !_isInitialized) {
      throw Exception('Model not initialized. Call initialize() first.');
    }

    try {
      // Padding tokens with start/end tokens (0) as in kokoro-onnx
      // This is crucial for matching the Python implementation
      final paddedTokens = [0, ...tokens, 0];
      print('Padded tokens: $paddedTokens (length: ${paddedTokens.length})');

      // Get input names from session
      final inputNames = _session!.inputNames;
      if (inputNames.length < 3) {
        throw Exception(
            'Model requires at least 3 inputs: tokens/input_ids, style, and speed');
      }

      // Prepare input map for inference
      final Map<String, OrtValue> inputs = {};

      try {
        // Create OrtValue tensors for each input
        // Support both older and newer model formats as in kokoro-onnx
        if (inputNames.contains('input_ids')) {
          print('Using newer model format with input_ids');
          // Newer model format
          // CRITICAL: Use Int64List for token IDs to match Python int64 type
          inputs['input_ids'] = await OrtValue.fromList(
            Int64List.fromList(paddedTokens),
            [1, paddedTokens.length], // Shape: [batch_size, sequence_length]
          );
          inputs['style'] = await OrtValue.fromList(
            voice.toList(),
            [
              1,
              voice.length
            ], // Shape: [1, embedding_size] - Model expects rank 2
          );
          inputs['speed'] = await OrtValue.fromList(
            [speed],
            [1], // Shape: [1]
          );
        } else {
          print('Using older model format with tokens');
          // Older model format
          // CRITICAL: Use Int64List for token IDs to match Python int64 type
          inputs[inputNames[0]] = await OrtValue.fromList(
            Int64List.fromList(paddedTokens),
            [1, paddedTokens.length], // Shape: [batch_size, sequence_length]
          );
          inputs[inputNames[1]] = await OrtValue.fromList(
            voice.toList(),
            [
              1,
              voice.length
            ], // Shape: [1, embedding_size] - Model expects rank 2
          );
          inputs[inputNames[2]] = await OrtValue.fromList(
            [speed],
            [1], // Shape: [1]
          );
        }
      } catch (e) {
        // In flutter_onnxruntime, tensors are automatically managed
        // No need to explicitly release them
        throw Exception('Failed to create input tensors: $e');
      }

      // Run inference
      final outputs = await _session!.run(inputs);

      // Get the output audio data
      final outputNames = _session!.outputNames;
      if (outputNames.isEmpty || outputs.isEmpty) {
        throw Exception('Model has no outputs');
      }

      // Extract audio data from the first output
      // According to flutter_onnxruntime API, we need to convert it to a list
      final outputValue = outputs[outputNames[0]];
      if (outputValue == null) {
        throw Exception('Output tensor is null');
      }

      // Get the data as a list and convert to doubles
      final List<dynamic> rawList = await outputValue.asList();
      final List<double> outputList =
          rawList.map((value) => value as double).toList();

      // Convert the list to Float32List for audio processing
      final outputData = Float32List.fromList(outputList);

      // No need to manually release tensors in flutter_onnxruntime implementation
      // as it handles resource management automatically

      debugPrint(
          'Dart: Raw ONNX Output (first 10): ${outputData.sublist(0, outputData.length > 10 ? 10 : outputData.length)}');
      debugPrint(
          'Dart: Raw ONNX Output (last 10): ${outputData.sublist(outputData.length > 10 ? outputData.length - 10 : 0)}');
      double minVal = double.maxFinite;
      double maxVal = double.negativeInfinity;
      for (var v in outputData) {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }
      debugPrint(
          'Dart: Raw ONNX Output min: $minVal, max: $maxVal, length: ${outputData.length}');

      return outputData;
    } catch (e) {
      throw Exception('Failed to run inference: $e');
    }
  }

  /// Checks if the model is initialized
  bool get isInitialized => _isInitialized;

  /// Gets information about the model's inputs
  List<String> get inputNames => _session?.inputNames ?? [];

  /// Gets information about the model's outputs
  List<String> get outputNames => _session?.outputNames ?? [];

  /// Disposes of the model resources
  Future<void> dispose() async {
    if (_session != null) {
      await _session!.close(); // Use close() instead of dispose()
      _session = null;
      _isInitialized = false;
    }
  }
}
