import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/backup.dart';
import '../services/backup/data_sync.dart';
import '../services/chat/chat_service.dart';

class BackupProvider extends ChangeNotifier {
  final DataSync _dataSync;
  bool _busy = false;
  String? _message;

  BackupProvider({required ChatService chatService})
      : _dataSync = DataSync(chatService: chatService);

  bool get busy => _busy;
  String? get message => _message;

  Future<File> exportToFile() =>
      _dataSync.exportToFile(const WebDavConfig());

  Future<void> restoreFromLocalFile(
    File file, {
    RestoreMode mode = RestoreMode.overwrite,
  }) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      await _dataSync.restoreFromLocalFile(
        file,
        const WebDavConfig(),
        mode: mode,
      );
      _message = 'Restored';
    } catch (e) {
      _message = e.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
