
/// Maximum phoneme length allowed
const int maxPhonemeLength = 510;

/// Sample rate for audio output
const int sampleRate = 24000;

/// Tokenizer configuration
class TokenizerConfig {
  /// Path to lexicon files (optional)
  final String? lexiconPath;

  const TokenizerConfig({this.lexiconPath});
}

/// Core Kokoro configuration
class KokoroConfig {
  /// Path to the model file
  final String modelPath;
  
  /// Path to the voices file
  final String voicesPath;
  
  /// Tokenizer configuration
  final TokenizerConfig? tokenizerConfig;

  const KokoroConfig({
    required this.modelPath,
    required this.voicesPath,
    this.tokenizerConfig,
  });

  /// Validates the configuration
  ///
  /// Note: This method no longer checks if the files exist as assets are accessed
  /// differently in Flutter and cannot be checked with File.existsSync().
  /// The actual existence will be verified when the assets are loaded.
  void validate() {
    // Just check that the paths are non-empty
    if (voicesPath.isEmpty) {
      throw ArgumentError('Voices path cannot be empty');
    }

    if (modelPath.isEmpty) {
      throw ArgumentError('Model path cannot be empty');
    }
  }
  
  /// Create a copy of this config with updated values
  KokoroConfig copyWith({
    String? modelPath,
    String? voicesPath,
    TokenizerConfig? tokenizerConfig,
  }) {
    return KokoroConfig(
      modelPath: modelPath ?? this.modelPath,
      voicesPath: voicesPath ?? this.voicesPath,
      tokenizerConfig: tokenizerConfig ?? this.tokenizerConfig,
    );
  }
}
