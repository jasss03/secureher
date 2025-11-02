import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;

class CloudUploadResult {
  final String? url;
  final String? path;
  CloudUploadResult({this.url, this.path});
}

class CloudUploadService {
  Future<CloudUploadResult?> uploadEvidenceFile(File file) async {
    try {
      final name = p.basename(file.path);
      final ref = FirebaseStorage.instance.ref().child('evidence/$name');
      final task = await ref.putFile(file);
      final url = await task.ref.getDownloadURL();
      return CloudUploadResult(url: url, path: task.ref.fullPath);
    } catch (_) {
      return null; // Storage not configured or upload failed; ignore silently
    }
  }
}