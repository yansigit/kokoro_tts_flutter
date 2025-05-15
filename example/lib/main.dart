import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:kokoro_tts_flutter/kokoro_tts_flutter.dart';

void main() {
  runApp(const KokoroTTSApp());
}

class KokoroTTSApp extends StatelessWidget {
  const KokoroTTSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kokoro TTS Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      home: const KokoroTTSDemoPage(),
    );
  }
}

class KokoroTTSDemoPage extends StatefulWidget {
  const KokoroTTSDemoPage({super.key});

  @override
  State<KokoroTTSDemoPage> createState() => _KokoroTTSDemoPageState();
}

class _KokoroTTSDemoPageState extends State<KokoroTTSDemoPage> {
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  Kokoro? _kokoro;
  bool _isInitialized = false;
  bool _isGenerating = false;
  bool _isPlaying = false;
  String _phonemes = '';
  String _selectedVoice = 'en_sarah';
  double _speed = 1.0;
  
  List<String> _availableVoices = [];
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeKokoro();
  }
  
  Future<void> _initializeKokoro() async {
    setState(() {
      _statusMessage = 'Initializing Kokoro TTS engine...';
    });

    try {
      // Get application documents directory
      final appDocDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDocDir.path}/kokoro-model.tflite';
      final voicesPath = '${appDocDir.path}/kokoro-voices.bin';
      
      // Check if model files exist, in a real app you would download them if not
      if (!File(modelPath).existsSync()) {
        setState(() {
          _statusMessage = 'Model file not found. In a real app, you would download it.';
        });
        return;
      }
      
      if (!File(voicesPath).existsSync()) {
        setState(() {
          _statusMessage = 'Voices file not found. In a real app, you would download it.';
        });
        return;
      }
      
      // Create configuration
      final config = KokoroConfig(
        modelPath: modelPath,
        voicesPath: voicesPath,
      );
      
      // Initialize Kokoro TTS
      _kokoro = Kokoro(config);
      await _kokoro!.initialize();
      
      // Get available voices
      _availableVoices = _kokoro!.getVoices();
      
      setState(() {
        _isInitialized = true;
        _statusMessage = 'Kokoro TTS engine initialized successfully!';
        if (_availableVoices.isNotEmpty) {
          _selectedVoice = _availableVoices.first;
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error initializing Kokoro TTS: $e';
      });
    }
  }
  
  Future<void> _generateSpeech() async {
    if (!_isInitialized || _textController.text.isEmpty) return;
    
    setState(() {
      _isGenerating = true;
      _statusMessage = 'Generating speech...';
    });
    
    try {
      // Generate speech
      final result = await _kokoro!.createTTS(
        text: _textController.text,
        voice: _selectedVoice,
        speed: _speed,
        lang: 'en-us',
      );
      
      setState(() {
        _phonemes = result.phonemes;
      });
      
      // Save audio to temp file for playback
      final tempDir = await getTemporaryDirectory();
      final audioFile = File('${tempDir.path}/kokoro_audio.wav');
      
      // Write WAV file (simplified - in a real implementation you'd properly format a WAV file)
      final int16PCM = result.toInt16PCM();
      await audioFile.writeAsBytes(int16PCM.buffer.asUint8List());
      
      // Set up audio player
      await _audioPlayer.setFilePath(audioFile.path);
      
      setState(() {
        _isGenerating = false;
        _statusMessage = 'Speech generated successfully!';
      });
      
      // Play audio
      await _playAudio();
      
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _statusMessage = 'Error generating speech: $e';
      });
    }
  }
  
  Future<void> _playAudio() async {
    if (_audioPlayer.audioSource == null) return;
    
    setState(() {
      _isPlaying = true;
    });
    
    await _audioPlayer.play();
    
    // Wait for audio to complete
    await _audioPlayer.playerStateStream.firstWhere(
      (state) => state.processingState == ProcessingState.completed
    );
    
    setState(() {
      _isPlaying = false;
    });
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _audioPlayer.dispose();
    _kokoro?.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kokoro TTS Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Enter text to speak',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              enabled: _isInitialized && !_isGenerating,
            ),
            const SizedBox(height: 16),
            
            // Voice selection
            DropdownButtonFormField<String>(
              value: _selectedVoice,
              decoration: const InputDecoration(
                labelText: 'Voice',
                border: OutlineInputBorder(),
              ),
              items: _availableVoices.map((voice) {
                return DropdownMenuItem<String>(
                  value: voice,
                  child: Text(voice),
                );
              }).toList(),
              onChanged: _isInitialized && !_isGenerating 
                ? (value) {
                    if (value != null) {
                      setState(() {
                        _selectedVoice = value;
                      });
                    }
                  }
                : null,
            ),
            const SizedBox(height: 16),
            
            // Speed slider
            Row(
              children: [
                const Text('Speed:'),
                Expanded(
                  child: Slider(
                    value: _speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: _speed.toStringAsFixed(1),
                    onChanged: _isInitialized && !_isGenerating
                      ? (value) {
                          setState(() {
                            _speed = value;
                          });
                        }
                      : null,
                  ),
                ),
                Text('${_speed.toStringAsFixed(1)}x'),
              ],
            ),
            const SizedBox(height: 16),
            
            // Generate and play buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isInitialized && !_isGenerating && !_isPlaying
                      ? _generateSpeech
                      : null,
                    child: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Generate Speech'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isInitialized && !_isGenerating && !_isPlaying && _audioPlayer.audioSource != null
                      ? _playAudio
                      : null,
                    child: _isPlaying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Play Again'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Status
            Text(
              _statusMessage,
              style: TextStyle(
                color: _statusMessage.contains('Error')
                  ? Colors.red
                  : Colors.green,
              ),
            ),
            const SizedBox(height: 16),
            
            // Phonemes display
            const Text(
              'Phonetic Representation:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                _phonemes.isEmpty
                  ? 'Enter text and press Generate Speech'
                  : _phonemes,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Example inputs
            const Text(
              'Example Inputs:',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _exampleChip('Hello world!'),
                _exampleChip('Kokoro TTS is amazing.'),
                _exampleChip('How are you today?'),
                _exampleChip('This is a test of the Kokoro TTS engine.'),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _exampleChip(String text) {
    return InputChip(
      label: Text(text),
      onPressed: _isInitialized && !_isGenerating && !_isPlaying
        ? () {
            _textController.text = text;
            _generateSpeech();
          }
        : null,
    );
  }
}
