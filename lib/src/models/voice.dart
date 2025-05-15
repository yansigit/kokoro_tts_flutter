import 'dart:typed_data';

/// Represents a voice in the Kokoro TTS system
class Voice {
  /// Unique identifier for the voice
  final String id;
  
  /// Display name of the voice
  final String name;
  
  /// The voice style vectors used for model inference
  /// Each index corresponds to a different token length
  final List<Float32List> styleVectors;
  
  /// Language code associated with this voice (e.g., 'en-us')
  final String languageCode;
  
  /// Gender of the voice ('male', 'female', or 'neutral')
  final String gender;
  
  /// Creates a voice instance
  const Voice({
    required this.id,
    required this.name,
    required this.styleVectors, 
    required this.languageCode,
    this.gender = 'neutral',
  });
  
  /// Gets the appropriate style vector for the given token length
  /// This is the key method that implements dynamic style vector selection
  /// as seen in the Python kokoro-onnx implementation
  Float32List getStyleVectorForTokens(int tokenLength) {
    // Ensure token length is within bounds of available style vectors
    // If out of bounds, use the closest available vector
    final int safeIndex = tokenLength.clamp(0, styleVectors.length - 1);
    return _ensureCorrectDimensions(styleVectors[safeIndex]);
  }
  
  /// Ensures the style vector has the correct dimensions (256) for the model
  /// If the vector is too short, it will be padded with zeros
  /// If the vector is too long, it will be truncated
  Float32List _ensureCorrectDimensions(Float32List vector) {
    const int requiredDimension = 256; // The model expects 256 dimensions
    
    if (vector.length == requiredDimension) {
      return vector; // Already the correct size
    }
    
    // Create a new vector with the required dimensions
    final Float32List result = Float32List(requiredDimension);
    
    // Copy values from the original vector, up to the minimum of the two lengths
    final int copyLength = vector.length < requiredDimension ? vector.length : requiredDimension;
    for (int i = 0; i < copyLength; i++) {
      result[i] = vector[i];
    }
    
    // The rest of the elements will remain as 0.0 (default value for Float32List)
    return result;
  }
  
  /// Create a copy of this voice with updated values
  Voice copyWith({
    String? id,
    String? name,
    List<Float32List>? styleVectors,
    String? languageCode,
    String? gender,
  }) {
    return Voice(
      id: id ?? this.id,
      name: name ?? this.name,
      styleVectors: styleVectors ?? this.styleVectors,
      languageCode: languageCode ?? this.languageCode,
      gender: gender ?? this.gender,
    );
  }
  
  @override
  String toString() => 'Voice(id: $id, name: $name, lang: $languageCode, styleVectors: ${styleVectors.length})';
}
