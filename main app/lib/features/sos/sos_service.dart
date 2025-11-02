import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/storage_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../services/cloud_upload_service.dart';

class SosService {
  CameraController? _controller;
  bool _isRecording = false;

  Future<bool> _ensurePermissions() async {
    if (kIsWeb) return false; // Not supported in this flow yet

    final statuses = await [Permission.camera, Permission.microphone].request();
    final camOk = statuses[Permission.camera]?.isGranted ?? false;
    final micOk = statuses[Permission.microphone]?.isGranted ?? false;
    return camOk && micOk;
  }

  Future<bool> startRecording({bool includeAudio = true}) async {
    if (!await _ensurePermissions()) return false;
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.isNotEmpty ? cameras.first : throw Exception('No camera'),
      );
      _controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: includeAudio,
      );
      await _controller!.initialize();
      await _controller!.startVideoRecording();
      _isRecording = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> stopAndSaveEncrypted({Map<String, dynamic>? metadata}) async {
    if (_controller == null || !_isRecording) return null;
    try {
      final XFile file = await _controller!.stopVideoRecording();
      _isRecording = false;
      final bytes = await file.readAsBytes();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final baseName = 'sos_$ts';
      final encName = '$baseName.mp4.enc';
      final saved = await StorageService().saveEncryptedBytes(encName, bytes);
      // Save sidecar metadata (unencrypted JSON)
      if (metadata != null) {
        await StorageService().saveJsonSidecar(baseName, metadata);
      }
      // Try to delete plaintext file
      try { if (!kIsWeb) { final f = File(file.path); if (await f.exists()) await f.delete(); } } catch (_) {}

      // Try cloud upload (optional)
      try {
        final f = File(saved.path);
        if (await f.exists()) {
          await CloudUploadService().uploadEvidenceFile(f);
        }
      } catch (_) {}

      return saved.path;
    } catch (_) {
      return null;
    } finally {
      await _controller?.dispose();
      _controller = null;
    }
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
  }
}
