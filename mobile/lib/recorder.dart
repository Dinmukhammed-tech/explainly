import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records the answer from the microphone and gives back the audio bytes.
/// Works the same on a phone and in a browser.
class VoiceRecorder {
  final _recorder = AudioRecorder();
  String _fileName = 'answer.m4a';

  /// Returns false if the user did not allow the microphone.
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;

    // Browsers record Opus, phones record AAC. Whisper reads both.
    var encoder = AudioEncoder.aacLc;
    var path = '';
    if (kIsWeb) {
      if (await _recorder.isEncoderSupported(AudioEncoder.opus)) {
        encoder = AudioEncoder.opus;
        _fileName = 'answer.webm';
      }
    } else {
      path = '${(await getTemporaryDirectory()).path}/$_fileName';
    }
    await _recorder.start(RecordConfig(encoder: encoder, numChannels: 1), path: path);
    return true;
  }

  /// Stops and returns (bytes, file name), or null if nothing was recorded.
  Future<(Uint8List, String)?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final bytes = await XFile(path).readAsBytes();
    return bytes.isEmpty ? null : (bytes, _fileName);
  }

  Future<void> cancel() => _recorder.cancel();

  void dispose() => _recorder.dispose();
}
