import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Book files handed to Calibre Touch from outside the app:
///
/// * Android: "Open with" (ACTION_VIEW) and the Share menu (ACTION_SEND /
///   SEND_MULTIPLE), see the intent filters in AndroidManifest.xml. The
///   receive_sharing_intent plugin copies `content://` files into the app's
///   cache folder and gives us that path.
/// * Windows: the file path(s) on the command line ("Open with" in
///   Explorer). When the app is already running, the new process forwards
///   its files to the running one (windows/runner/main.cpp) and they arrive
///   over the `calibre_touch/incoming_files` channel.
///
/// The files wait in a queue until the home page imports them (see
/// HomePage._handleIncoming / BookImport). One queue entry = the files of
/// one "open" / "share" action.
class IncomingFiles {
  IncomingFiles._();

  /// Book formats the app accepts from other apps (lower case).
  static const extensions = {
    'epub', 'pdf', 'mobi', 'azw', 'azw3', 'prc', 'txt', 'docx', 'odt', 'rtf',
    'fb2', 'fbz',
  };

  static const _mimeExtensions = {
    'application/epub+zip': 'epub',
    'application/pdf': 'pdf',
    'application/x-mobipocket-ebook': 'mobi',
    'application/vnd.amazon.ebook': 'azw',
    'application/vnd.amazon.mobi8-ebook': 'azw3',
    'application/x-mobi8-ebook': 'azw3',
    'text/plain': 'txt',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        'docx',
    'application/vnd.oasis.opendocument.text': 'odt',
    'application/rtf': 'rtf',
    'text/rtf': 'rtf',
    'application/x-fictionbook+xml': 'fb2',
    'application/x-fictionbook': 'fb2',
    'application/x-zip-compressed-fb2': 'fbz',
  };

  static const _windowsChannel = MethodChannel('calibre_touch/incoming_files');

  static final List<List<String>> _queue = [];
  static final _arrived = StreamController<void>.broadcast();

  /// Whether files are waiting to be imported.
  static bool get hasPending => _queue.isNotEmpty;

  /// Fires whenever new files were queued.
  static Stream<void> get onArrived => _arrived.stream;

  /// The next group of files, removed from the queue (null if none).
  static List<String>? takeNext() => _queue.isEmpty ? null : _queue.removeAt(0);

  /// Call once in main(), before runApp. [args] = main's arguments
  /// (Windows command line).
  static Future<void> init(List<String> args) async {
    if (Platform.isWindows) {
      _add(args);
      _windowsChannel.setMethodCallHandler((call) async {
        if (call.method == 'openFiles') {
          _add(_strings(call.arguments));
        }
        return null;
      });
      try {
        // Files forwarded by a second instance before Dart was listening.
        _add(_strings(await _windowsChannel.invokeMethod<List>('ready')));
      } catch (e) {
        debugPrint('Incoming files channel not available: $e');
      }
    } else if (Platform.isAndroid) {
      try {
        final sharing = ReceiveSharingIntent.instance;
        // While running (singleTask activity -> onNewIntent).
        sharing.getMediaStream().listen(
              (files) async => _add(await _sharedPaths(files)),
              onError: (Object e) => debugPrint('Shared file failed: $e'),
            );
        // The intent that started the app.
        final initial = await sharing
            .getInitialMedia()
            .timeout(const Duration(seconds: 3), onTimeout: () => const []);
        _add(await _sharedPaths(initial));
        // Consumed: a hot restart / activity re-creation must not import
        // the same file again.
        await sharing.reset();
      } catch (e) {
        debugPrint('Incoming files not available: $e');
      }
    }
  }

  /// Deletes the app's own temporary copy of an incoming file (Android
  /// copies `content://` files into the cache folder). The user's files are
  /// never touched.
  static Future<void> release(String path) async {
    if (!Platform.isAndroid) return;
    try {
      final cache = (await getTemporaryDirectory()).path;
      if (p.isWithin(cache, path)) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      debugPrint('Temporary file not deleted: $e');
    }
  }

  static List<String> _strings(Object? value) =>
      value is List ? [for (final v in value) '$v'] : const [];

  static bool _isBook(String path) => extensions
      .contains(p.extension(path).replaceFirst('.', '').toLowerCase());

  static void _add(Iterable<String> paths) {
    final files = [
      for (final path in paths)
        if (path.trim().isNotEmpty && _isBook(path)) File(path).absolute.path
    ];
    if (files.isEmpty) return;
    _queue.add(files);
    _arrived.add(null);
  }

  /// Paths of shared files. A cache copy without a usable extension (some
  /// apps share files without a proper name) gets one from its MIME type.
  static Future<List<String>> _sharedPaths(List<SharedMediaFile> files) async {
    final paths = <String>[];
    for (final file in files) {
      if (file.type == SharedMediaType.text ||
          file.type == SharedMediaType.url) {
        continue;
      }
      var path = file.path;
      if (path.isEmpty) continue;
      if (!_isBook(path)) {
        final ext = _mimeExtensions[file.mimeType?.toLowerCase()];
        if (ext == null) continue;
        try {
          final cache = (await getTemporaryDirectory()).path;
          if (!p.isWithin(cache, path)) continue;
          path = (await File(path).rename('$path.$ext')).path;
        } catch (e) {
          debugPrint('Shared file not renamed: $e');
          continue;
        }
      }
      paths.add(path);
    }
    return paths;
  }
}
