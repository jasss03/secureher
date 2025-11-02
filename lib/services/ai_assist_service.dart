import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class AiAssistService {
  final stt.SpeechToText _stt = stt.SpeechToText();
  StreamController<String> _transcriptCtrl = StreamController.broadcast();
  Timer? _kick;

  bool _listening = false;
  bool dangerDetected = false;
  String? matchedKeyword;

  // Keywords to watch for
  final List<String> keywords;

  AiAssistService({this.keywords = const [
    'help',
    'help me',
    'save',
    'save me',
    'police',
    'emergency',
    'danger',
    'stay away',
    "don't touch me",
    'leave me alone',
  ]});

  Stream<String> get transcripts => _transcriptCtrl.stream;

  Future<bool> startListening() async {
    // Ensure microphone permission is granted
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return false;

    final available = await _stt.initialize();
    if (!available) return false;
    dangerDetected = false;
    matchedKeyword = null;
    _listening = true;

    // Start continuous listening with periodic restarts to avoid timeouts
    void _begin() {
      _stt.listen(
        onResult: (res) {
          final text = res.recognizedWords.toLowerCase();
          if (text.isNotEmpty) {
            _transcriptCtrl.add(text);
            for (final k in keywords) {
              if (text.contains(k)) {
                dangerDetected = true;
                matchedKeyword = k;
                break;
              }
            }
          }
        },
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      );
    }

    _begin();
    _kick?.cancel();
    _kick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_listening) return;
      if (_stt.isListening) {
        _stt.stop();
      }
      _begin();
    });
    return true;
  }

  Future<void> stop() async {
    _listening = false;
    _kick?.cancel();
    try { await _stt.stop(); } catch (_) {}
    await _transcriptCtrl.close();
    _transcriptCtrl = StreamController.broadcast();
  }
}
