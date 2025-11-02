import 'package:audioplayers/audioplayers.dart';

class SirenService {
  final AudioPlayer _player = AudioPlayer();

  Future<void> play() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/siren.mp3'));
    } catch (_) {
      // Ignore playback errors to avoid crashing the app.
      // On some emulators/devices, media playback may fail due to codecs or settings.
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
