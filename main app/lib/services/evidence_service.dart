import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'storage_service.dart';

class EvidenceItem {
  EvidenceItem({
    required this.baseName,
    required this.timestamp,
    this.encryptedVideoPath,
    this.sizeBytes,
    this.metadata,
  });

  final String baseName;
  final DateTime timestamp;
  final String? encryptedVideoPath;
  final int? sizeBytes;
  final Map<String, dynamic>? metadata;

  String get formattedTime => DateFormat('yyyy-MM-dd HH:mm').format(timestamp);
}

class EvidenceService {
  final StorageService _storage = StorageService();

  Future<List<EvidenceItem>> listRecent({int limit = 10}) async {
    final dir = await _storage.evidenceDir();
    if (!await dir.exists()) return [];
    final entries = await dir.list().toList();
    final jsonFiles = entries.where((e) => e is File && e.path.endsWith('.json')).cast<File>();

    final items = <EvidenceItem>[];
    for (final jf in jsonFiles) {
      try {
        final name = p.basenameWithoutExtension(jf.path);
        final content = await jf.readAsString();
        final meta = jsonDecode(content) as Map<String, dynamic>;
        final ts = DateTime.tryParse(meta['timestamp']?.toString() ?? '') ??
            (await jf.lastModified());
        final encVid = File(p.join(dir.path, '$name.mp4.enc'));
        final exists = await encVid.exists();
        final size = exists ? await encVid.length() : null;
        items.add(EvidenceItem(
          baseName: name,
          timestamp: ts,
          encryptedVideoPath: exists ? encVid.path : null,
          sizeBytes: size,
          metadata: meta,
        ));
      } catch (_) {
        // Skip malformed
      }
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (items.length > limit) return items.sublist(0, limit);
    return items;
  }

  Future<File?> decryptForPlayback(EvidenceItem item) async {
    if (item.encryptedVideoPath == null) return null;
    final f = File(item.encryptedVideoPath!);
    return StorageService().decryptToTempFile(f);
  }
}