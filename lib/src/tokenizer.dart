import 'dart:async';
import 'package:malsami/malsami.dart';
import 'config.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:developer' as developer;

/// Represents a segment of text, categorized as word, punctuation, or whitespace.
class _TextPart {
  final String text;
  final String type; // "word", "punctuation", "whitespace"

  _TextPart(this.text, this.type);
}

/// Splits text into words, punctuation, and whitespace parts.
List<_TextPart> _advancedSplit(String text) {
  final List<_TextPart> parts = [];
  // Regex to capture words, punctuation, or whitespace sequences.
  final RegExp r = RegExp(r"(\w+)|([^\w\s]+)|(\s+)");

  for (final Match match in r.allMatches(text)) {
    if (match.group(1) != null) {
      // Word
      parts.add(_TextPart(match.group(1)!, 'word'));
    } else if (match.group(2) != null) {
      // Punctuation
      parts.add(_TextPart(match.group(2)!, 'punctuation'));
    } else if (match.group(3) != null) {
      // Whitespace
      parts.add(_TextPart(match.group(3)!, 'whitespace'));
    }
  }
  return parts;
}

/// Tokenizer for Kokoro TTS
///
/// This class handles text normalization, phoneme conversion, and tokenization
/// using the malsami library (Dart port of Malsami G2P engine).
class Tokenizer {
  final EnglishG2P _g2p = EnglishG2P();
  late final Map<String, int> _vocab;
  late final Map<String, String> _lexicon;
  bool _isInitialized = false;

  /// The configuration for this tokenizer
  final TokenizerConfig? config;

  /// Creates a tokenizer with optional configuration
  ///
  /// If [config] is provided, it can specify a custom lexicon path
  Tokenizer({this.config});

  /// Initializes the tokenizer
  Future<void> _initialize() async {
    if (_isInitialized) return;

    await _g2p.initialize();
    await _loadVocabulary();
    await _loadLexicon();
    _isInitialized = true;
  }

  /// Ensures the tokenizer is initialized
  Future<void> ensureInitialized() async {
    if (!_isInitialized) {
      await _initialize();
    }
  }

  /// Loads the vocabulary mapping from phonemes to token IDs from assets/tokenizer_vocab.json
  Future<void> _loadVocabulary() async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/tokenizer_vocab.json');
      final Map<String, dynamic> vocabMap =
          Map<String, dynamic>.from(jsonDecode(jsonString));
      _vocab = vocabMap.map((k, v) => MapEntry(k, v as int));
      developer.log('Loaded vocabulary with ${_vocab.length} entries',
          name: 'kokoro_tokenizer');
    } catch (e) {
      throw Exception(
          'Failed to load vocabulary from assets/tokenizer_vocab.json: $e');
    }
  }

  /// Loads the lexicon mapping from words to phonemes
  Future<void> _loadLexicon() async {
    try {
      // Default to assets/lexicon.json if not specified in config
      final lexiconPath = config?.lexiconPath ?? 'assets/lexicon.json';
      final jsonString = await rootBundle.loadString(lexiconPath);
      final Map<String, dynamic> lexiconMap =
          Map<String, dynamic>.from(jsonDecode(jsonString));
      // Ensure lexicon keys are lowercase for consistent lookup
      _lexicon =
          lexiconMap.map((k, v) => MapEntry(k.toLowerCase(), v as String));
      developer.log(
          'Loaded lexicon with ${_lexicon.length} entries (keys lowercased)',
          name: 'kokoro_tokenizer');

      // Add custom entries to the G2P engine's lexicon
      // Since there's no direct API to add entries, we'll use reflection to access the lexicon
      // Add entries to the gold dictionary for highest quality
      for (final entry in _lexicon.entries) {
        // Access the lexicon's gold dictionary directly
        // Keys in _lexicon are already lowercased
        _g2p.lexicon.golds[entry.key] = entry.value;
      }
      developer.log('Added custom entries to G2P lexicon',
          name: 'kokoro_tokenizer');
    } catch (e) {
      // Just log the error but don't fail - lexicon is optional
      developer.log('Warning: Failed to load lexicon: $e',
          name: 'kokoro_tokenizer');
      _lexicon = {};
    }
  }

  /// Normalizes input text
  static String normalizeText(String text) {
    return text.trim(); // Basic trim, can be expanded
  }

  /// Converts text to phonemes and returns both phonemes and tokens
  ///
  /// This method supports markdown phoneme links in the format [Word](/fənˈɛtɪk/)
  /// which will be converted to the specified phonetic representation
  Future<(String, List<MToken>)> phonemizeWithTokens(
      String text, String lang) async {
    await ensureInitialized();

    // Normalize text - Note: phonemize method has a more advanced approach now.
    // This method might need to align with phonemize's splitting or be deprecated.
    var normalizedText = normalizeText(text);

    // Debug separate pieces of text with punctuation
    // This will help us understand how G2P processes the text
    // debugPunctuationProcessing(normalizedText); // Consider if still needed or how to adapt

    // *** TEMPORARY TEST: Lowercase for G2P lexicon lookup ***
    // normalizedText = normalizedText.toLowerCase(); // This is handled by _lexicon keys now
    // developer.log('DEBUG: Lowercased normalizedText for G2P: $normalizedText',
    //     name: 'kokoro_tokenizer');

    // Currently only supporting English
    // For other languages, we'd need specialized phonemizers
    // The _g2p.convert method likely does its own tokenization similar to spaCy's full pipeline.
    if (lang.startsWith('en')) {
      final (phonemes, tokens) = await _g2p.convert(normalizedText);
      developer.log('Phonemes (phonemizeWithTokens): $phonemes',
          name: 'kokoro_tokenizer');
      developer.log(
          'Tokens (phonemizeWithTokens): ${tokens.map((t) => t.text).join(', ')}',
          name: 'kokoro_tokenizer');
      return (phonemes, tokens);
    }

    // Fallback to English if language is not supported
    final (phonemes, tokens) = await _g2p.convert(normalizedText);
    developer.log('Phonemes (fallback in phonemizeWithTokens): $phonemes',
        name: 'kokoro_tokenizer');
    return (phonemes, tokens);
  }

  /// Converts text to phonemes, preserving all original spacing and punctuation.
  ///
  /// This method processes the input text by splitting it into words, punctuation,
  /// and whitespace segments. Words are phonemized using a lexicon lookup first,
  /// then falling back to the G2P engine. Punctuation and whitespace are
  /// preserved literally.
  /// The final output string is a concatenation of these processed segments.
  Future<String> phonemize(String text, {String lang = 'en-us'}) async {
    await ensureInitialized();

    if (text.isEmpty) {
      return ''; // Return empty string if input is empty
    }
    // No trim here, _advancedSplit handles all text as is.

    if (_lexicon.isEmpty) {
      developer.log(
          'Warning: Lexicon is empty. Phonemization quality may be reduced.',
          name: 'kokoro_tokenizer');
    }

    final List<_TextPart> parts = _advancedSplit(text);
    developer.log(
        'Advanced split parts for phonemization: ${parts.map((p) => '(${p.text}, ${p.type})').join(', ')}',
        name: 'kokoro_tokenizer');

    final List<String> resultSegments = [];

    for (final _TextPart part in parts) {
      switch (part.type) {
        case 'word':
          String wordToProcess = part.text;
          // Try lexicon first (lexicon keys are already lowercased)
          final String? lexiconPhonemes = _lexicon[wordToProcess.toLowerCase()];

          if (lexiconPhonemes != null) {
            resultSegments.add(lexiconPhonemes);
            developer.log('Lexicon hit for "${part.text}": $lexiconPhonemes',
                name: 'kokoro_tokenizer');
          } else {
            // Fallback to G2P.
            final (phonemes, /* List<MToken> tokens */ _) = await _g2p.convert(
                wordToProcess); // lang is implicitly handled by EnglishG2P
            String phonemesFromG2P = phonemes;

            // Handle potential empty result OR '❓' from G2P for certain inputs
            if ((phonemesFromG2P.trim().isEmpty || phonemesFromG2P == '❓') &&
                wordToProcess.isNotEmpty) {
              developer.log(
                  'G2P for "$wordToProcess" resulted in unusable phonemes ("$phonemesFromG2P"). Generating rule-based fallback.',
                  name: 'kokoro_tokenizer');
              phonemesFromG2P = _attemptRuleBasedFallback(wordToProcess);
              if (phonemesFromG2P.isEmpty) {
                developer.log(
                    'Rule-based fallback for "$wordToProcess" was empty, attempting spell-out fallback.',
                    name: 'kokoro_tokenizer');
                phonemesFromG2P = _generateFallbackPhonemes(wordToProcess);
              }
            }

            // Log the final phonemes (either from G2P or fallback) and add to results
            developer.log('Phonemizing "${part.text}" as "$phonemesFromG2P"',
                name: 'kokoro_tokenizer');
            resultSegments.add(phonemesFromG2P);
          }
          break;
        case 'punctuation':
          resultSegments.add(part.text);
          developer.log('Punctuation: "${part.text}"',
              name: 'kokoro_tokenizer');
          break;
        case 'whitespace':
          resultSegments.add(part.text);
          // Escape for clearer logging of whitespace characters
          final String printableWhitespace = part.text
              .replaceAll('\n', '\\n')
              .replaceAll('\t', '\\t')
              .replaceAll('\r', '\\r');
          developer.log('Whitespace: "$printableWhitespace"',
              name: 'kokoro_tokenizer');
          break;
      }
    }
    return resultSegments.join('');
  }

  /// Debug method to analyze how G2P processes text with punctuation
  void debugPunctuationProcessing(String text) async {
    // 1. Print the original text
    developer.log('PUNCTUATION DEBUG: Original text: "$text"',
        name: 'kokoro_tokenizer');

    // 2. Split by words and punctuation to test individually
    final RegExp wordOrPunctRegex =
        RegExp(r"([\w']+|[^\w\s]+)"); // Match words or punctuation
    final matches =
        wordOrPunctRegex.allMatches(text).map((m) => m.group(0)!).toList();

    developer.log('PUNCTUATION DEBUG: Split into ${matches.length} parts:',
        name: 'kokoro_tokenizer');
    for (int i = 0; i < matches.length; i++) {
      developer.log('PUNCTUATION DEBUG: Part $i: "${matches[i]}"',
          name: 'kokoro_tokenizer');
    }

    // 3. Test how G2P processes each part separately
    for (int i = 0; i < matches.length; i++) {
      final part = matches[i];
      try {
        final (partPhonemes, partTokens) =
            await _g2p.convert(part.toLowerCase());
        developer.log(
            'PUNCTUATION DEBUG: G2P for "$part" → "$partPhonemes" (${partTokens.map((t) => t.text).join(", ")})',
            name: 'kokoro_tokenizer');
      } catch (e) {
        developer.log('PUNCTUATION DEBUG: Error processing "$part": $e',
            name: 'kokoro_tokenizer');
      }
    }

    // 4. Try combinations of adjacent words with punctuation
    for (int i = 0; i < matches.length - 1; i++) {
      final combo = matches[i] + matches[i + 1];
      try {
        final (comboPhonemes, comboTokens) =
            await _g2p.convert(combo.toLowerCase());
        developer.log(
            'PUNCTUATION DEBUG: G2P for combined "$combo" → "$comboPhonemes" (${comboTokens.map((t) => t.text).join(", ")})',
            name: 'kokoro_tokenizer');
      } catch (e) {
        developer.log(
            'PUNCTUATION DEBUG: Error processing combined "$combo": $e',
            name: 'kokoro_tokenizer');
      }
    }
  }

  /// Tokenizes phonemes into token IDs
  ///
  /// This method converts a phoneme string into a list of integer IDs
  /// that can be fed into the ONNX model. It filters out any characters
  /// that don't have a corresponding entry in the vocabulary.
  ///
  /// Note: This method does NOT add padding tokens (0 at start and end).
  /// The padding is handled by the OnnxModelRunner to match the Python implementation.
  List<int> tokenize(String phonemes) {
    if (phonemes.length > maxPhonemeLength) {
      throw Exception(
          'Text is too long, must be less than $maxPhonemeLength phonemes');
    }

    List<int> tokens = [];
    for (int i = 0; i < phonemes.length; i++) {
      String charPhoneme = phonemes[i];
      if (_vocab.containsKey(charPhoneme)) {
        tokens.add(_vocab[charPhoneme]!);
      } else {
        // Optional: Log unknown phoneme characters, or decide on a specific UNK token
        // For now, we'll skip unknown characters to match Python's `if i is not None`
        // print('Warning: Unknown phoneme character "$charPhoneme"');
      }
    }
    developer.log('Tokenized phonemes: "$phonemes" -> ${tokens.length} tokens',
        name: 'kokoro_tokenizer');
    return tokens;
  }

  // Map of letters to their phonemic representations for spell-out fallback
  static const Map<String, String> _letterPhonemes = {
    'a': 'ˈeɪ', 'b': 'bˈiː', 'c': 'sˈiː', 'd': 'dˈiː', 'e': 'ˈiː',
    'f': 'ˈɛf', 'g': 'ʤˈiː', 'h': 'ˈeɪʧ', 'i': 'ˈaɪ', 'j': 'ʤˈeɪ',
    'k': 'kˈeɪ', 'l': 'ˈɛl', 'm': 'ˈɛm', 'n': 'ˈɛn', 'o': 'ˈoʊ',
    'p': 'pˈiː', 'q': 'kjˈuː', 'r': 'ˈɑːɹ', 's': 'ˈɛs', 't': 'tˈiː',
    'u': 'jˈuː', 'v': 'vˈiː', 'w': 'dˈʌbəljuː', 'x': 'ˈɛks', 'y': 'wˈaɪ',
    'z': 'zˈiː',
    // Numbers - can be expanded
    '0': 'zˈɪəɹoʊ', '1': 'wˈʌn', '2': 'tˈuː', '3': 'θɹˈiː', '4': 'fˈɔːɹ',
    '5': 'fˈaɪv', '6': 'sˈɪks', '7': 'sˈɛvən', '8': 'ˈeɪt', '9': 'nˈaɪn'
  };

  // More comprehensive grapheme-to-phoneme rules.
  // Rules are applied longest-match first.
  static final Map<String, String> _graphemePhonemeRules = {
    // Common Suffixes (order can matter if overlapping)
    'tion': 'ʃən', // station
    'sion': 'ʃən', // tension (can also be ʒən e.g. vision - simplify for now)
    'ious': 'iəs', // precious (approximation)
    'ness': 'nəs', // happiness
    'ment': 'mənt', // payment
    'able': 'əbəl', // capable
    'ible': 'ɪbəl', // visible
    'ing': 'ɪŋ', // singing (especially at word end)
    'ful': 'fəl', // helpful
    'less': 'ləs', // fearless
    'ly': 'li', // happily
    'er': 'ɚ', // teacher (schwar)
    'est': 'ɪst', // biggest

    // Trigraphs
    'igh': 'aɪ', // high, night
    'tch': 'tʃ', // watch, catch
    'dge': 'dʒ', // judge, bridge
    'eau': 'oʊ', // bureau, beau (can be other sounds, e.g. beauty /juː/)

    // Digraphs - Consonants
    'sh': 'ʃ', // ship, wash
    'ch':
        'tʃ', // chip, much (can also be k as in chemistry, or ʃ as in machine)
    'th':
        'θ', // thin, path (can also be ð as in this, that - simplified to unvoiced)
    'ph': 'f', // phone, graph
    'kn': 'n', // know, knife
    'wr': 'r', // write, wrong
    'wh': 'w', // what, when (some dialects hw)
    'ng': 'ŋ', // sing, long (can be ŋg if not at end, e.g. finger)
    'ck': 'k', // black, luck
    'sc': 'sk', // scan, scope (can be ʃ before e, i, y e.g. scene - simplified)
    'qu': 'kw', // queen, quiet
    'gu': 'g', // guard, guess (before e,i often hard g, not dʒ)
    'dg': 'dʒ', // (as in dge) - covered by dge mostly
    'mb': 'm', // comb, thumb (b is silent at end of word/morpheme)
    'bt': 't', // debt, doubt (b is silent)

    // Digraphs - Vowels (these are approximations for common pronunciations)
    'ee': 'iː', // see, feet
    'ea': 'iː', // meat, read (present) (can also be ɛ as in bread, read (past))
    'oo': 'uː', // moon, food (can also be ʊ as in book, good)
    'ai': 'eɪ', // rain, wait
    'ay': 'eɪ', // day, say
    'oi': 'ɔɪ', // coin, boil
    'oy': 'ɔɪ', // boy, toy
    'ou':
        'aʊ', // house, out (many variations: oʊ as in soul, uː as in group, ʌ as in tough)
    'ow': 'aʊ', // cow, now (can also be oʊ as in snow, low)
    'au': 'ɔː', // author, pause
    'aw': 'ɔː', // saw, law
    'ew': 'juː', // new, few (can be uː after r, j, l, e.g. grew, flew)
    'ey': 'eɪ', // grey, they (can be iː as in key)
    'ie': 'iː', // brief, chief (can be aɪ as in pie, tie)
    'oa': 'oʊ', // boat, coat
    'oe': 'oʊ', // toe, hoe
    'ue':
        'uː', // blue, true (can be juː as in cue, or silent at end of word e.g. vague)
    'ui': 'uː', // fruit, suit (can be ɪ as in build, guitar)
  };

  // Basic phonemes for single letters (used as a fallback within rule-based G2P)
  // These are very approximate and represent common sounds, not exhaustive.
  static const Map<String, String> _singleGraphemePhonemes = {
    'a': 'æ',
    'b': 'b',
    'c': 'k',
    'd': 'd',
    'e': 'ɛ',
    'f': 'f',
    'g': 'ɡ',
    'h': 'h',
    'i': 'ɪ',
    'j': 'dʒ',
    'k': 'k',
    'l': 'l',
    'm': 'm',
    'n': 'n',
    'o': 'ɒ',
    'p': 'p',
    'q': 'k',
    /* q is usually 'kw' with u, 'k' is a guess */ 'r': 'ɹ',
    's': 's',
    't': 't',
    'u': 'ʌ',
    'v': 'v',
    'w': 'w',
    'x': 'ks',
    'y': 'j',
    'z': 'z',
  };

  String _attemptRuleBasedFallback(String word) {
    final lowerWord = word.toLowerCase();
    final List<String> phonemeList = [];
    int i = 0;

    // Sort rule keys by length, longest first, to ensure maximal munch strategy.
    final List<String> sortedRuleKeys = _graphemePhonemeRules.keys.toList();
    sortedRuleKeys.sort((a, b) => b.length.compareTo(a.length));

    while (i < lowerWord.length) {
      bool ruleAppliedThisPass = false;
      for (final ruleKey in sortedRuleKeys) {
        if (ruleKey.isNotEmpty && // Ensure ruleKey is not empty
            i + ruleKey.length <= lowerWord.length &&
            lowerWord.substring(i, i + ruleKey.length) == ruleKey) {
          phonemeList.add(_graphemePhonemeRules[ruleKey]!);
          i += ruleKey.length;
          ruleAppliedThisPass = true;
          break; // Found the longest matching multi-character rule for this position
        }
      }

      if (!ruleAppliedThisPass) {
        // No multi-character rule applied, try single character phoneme
        final char = lowerWord[i];
        if (_singleGraphemePhonemes.containsKey(char)) {
          phonemeList.add(_singleGraphemePhonemes[char]!);
        } else if (RegExp(r'[0-9]').hasMatch(char) &&
            _letterPhonemes.containsKey(char)) {
          // For digits 0-9, use their spelled-out phoneme if available in _letterPhonemes
          phonemeList.add(_letterPhonemes[char]!);
        } else {
          // If character is not in _singleGraphemePhonemes (which covers a-z),
          // and it's not a digit with a spelled-out form,
          // treat as unknown. Avoids spelling out other letters if they were missed in _singleGraphemePhonemes.
          developer.log(
              'Rule-based fallback: No specific rule or phoneme for character "$char" in "$word". Using "?".',
              name: 'kokoro_tokenizer');
          phonemeList.add('?'); // Use '?' for unknown characters
        }
        i++; // Advance by one character
      }
    }
    return phonemeList.join('');
  }

  /// Generates phonemes by spelling out the word letter by letter.
  /// This is now primarily for numbers if their direct phoneme isn't found or for explicit spell-out needs.
  String _generateFallbackPhonemes(String word) {
    final lowerWord = word.toLowerCase();
    final List<String> phonemeList = [];
    for (int i = 0; i < lowerWord.length; i++) {
      final char = lowerWord[i];
      if (_letterPhonemes.containsKey(char)) {
        phonemeList.add(_letterPhonemes[char]!);
      } else {
        // If a character is not in the map (e.g., special symbols not filtered out yet),
        // we might add it as is, or a placeholder. For now, skip unknown chars in spell-out.
        developer.log(
            'Character "$char" not found in _letterPhonemes map during spell-out.',
            name: 'kokoro_tokenizer');
      }
    }
    return phonemeList.join(' ');
  }
}
