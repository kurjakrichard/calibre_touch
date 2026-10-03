import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileService {
  /// The ONE place that defines where book files live.
  ///
  /// [customPath] should be whatever `pathProvider` currently holds — that
  /// provider (backed by `SharedUtility`/`SharedPreferences`) is the single
  /// source of truth for the user's chosen library folder. This method never
  /// reads SharedPreferences itself; when [customPath] is null or empty it
  /// falls back to the app's own documents directory.
  Future<String> libraryRoot({String? customPath}) async {
    if (customPath != null && customPath.isNotEmpty) {
      return customPath;
    }
    return defaultLibraryRoot();
  }

  /// The default library location, ignoring any custom folder the user
  /// picked on the Settings page. Handy for showing the user what "default"
  /// means before they commit to it.
  Future<String> defaultLibraryRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'ebooks');
  }

  /// Absolute path of a book file, built from the values stored in the DB.
  /// Calibre stores the format upper case (EPUB) but names the file with a
  /// lower-case extension (.epub).
  ///
  /// Pass the current `pathProvider` value as [customPath] whenever the
  /// caller isn't explicitly asking for the default location.
  Future<String> bookFilePath({
    required String path,
    required String filename,
    required String format,
    String? customPath,
  }) async {
    return p.joinAll([
      await libraryRoot(customPath: customPath),
      ...path.split('/'),
      '$filename.${format.toLowerCase()}'
    ]);
  }

  /// Name of the cover image Calibre keeps in every book folder.
  static const String coverFileName = 'cover.jpg';

  /// Absolute path of a book's cover, from its `books.path` value:
  /// `<library>/<Author>/<Title (id)>/cover.jpg` - exactly where Calibre
  /// stores it.
  Future<String> coverFilePath({
    required String path,
    String? customPath,
  }) async {
    return coverPathIn(await libraryRoot(customPath: customPath), path);
  }

  /// Same as [coverFilePath] when the library root is already known
  /// (lets widgets build the path synchronously).
  static String coverPathIn(String libraryRoot, String path) =>
      p.joinAll([libraryRoot, ...path.split('/'), coverFileName]);

  /// Moves cover.jpg from one book folder to another (used when a book's
  /// folder is renamed). Best-effort: a missing cover is not an error.
  Future<void> moveCover({
    required String fromPath,
    required String toPath,
    String? customPath,
  }) async {
    if (fromPath == toPath) return;
    final root = await libraryRoot(customPath: customPath);
    final from = File(coverPathIn(root, fromPath));
    final to = coverPathIn(root, toPath);
    try {
      if (!await from.exists() || await File(to).exists()) return;
      await Directory(p.dirname(to)).create(recursive: true);
      try {
        await from.rename(to);
      } on FileSystemException {
        await from.copy(to);
        await from.delete();
      }
    } catch (e) {
      debugPrint('Cover not moved: $e');
    }
  }

  Future<bool> fileExists(String path) => File(path).exists();

  void openFile(String path) {
    OpenFilex.open(path);
  }

  /// Absolute path of a book's folder (`<library>/<Author>/<Title (id)>`).
  Future<String> bookFolderPath({
    required String path,
    String? customPath,
  }) async {
    return p.joinAll([
      await libraryRoot(customPath: customPath),
      ...path.split('/'),
    ]);
  }

  /// Shows [folder] in the system file manager (Explorer on Windows).
  /// Returns false if it could not be opened.
  Future<bool> openFolder(String folder) async {
    try {
      if (Platform.isWindows) {
        // explorer.exe returns exit code 1 even on success - don't check it.
        await Process.run('explorer', [folder]);
        return true;
      }
      if (Platform.isMacOS) {
        return (await Process.run('open', [folder])).exitCode == 0;
      }
      if (Platform.isLinux) {
        return (await Process.run('xdg-open', [folder])).exitCode == 0;
      }
      // Android / iOS: ask the system for an app that can show the folder.
      final result = await OpenFilex.open(folder);
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('Could not open folder $folder: $e');
      return false;
    }
  }

  Future<File> copyFile({
    required String oldpath,
    required String newpath,
  }) async {
    File oldFile = File(oldpath);
    return await File(newpath).create(recursive: true).then((File file) {
      return oldFile.copy(newpath);
    });
  }

  /// Moves a book file. Throws if the source is missing or the target
  /// already exists, so nothing is ever overwritten or lost.
  ///
  /// Pass the current `pathProvider` value as [customPath] so the empty-
  /// folder cleanup below never guesses at the library root itself.
  Future<void> moveBookFile({
    required String from,
    required String to,
    String? customPath,
  }) async {
    if (p.equals(from, to)) return;

    final source = File(from);
    if (!await source.exists()) {
      throw FileSystemException('Source file not found', from);
    }
    if (await File(to).exists()) {
      throw FileSystemException('A file already exists at the target', to);
    }

    await Directory(p.dirname(to)).create(recursive: true);
    try {
      await source.rename(to);
    } on FileSystemException {
      // rename can fail across drives/partitions -> copy + delete instead
      await source.copy(to);
      try {
        await source.delete();
      } catch (e) {
        debugPrint('Copied, but could not remove the old file: $e');
      }
    }

    // The move itself succeeded. Tidying up is best-effort only: on Windows,
    // OneDrive/Explorer can lock a folder, and that must not fail the save.
    unawaited(_cleanupEmptyDirs(from, customPath: customPath)); // background
  }

  /// Moves a book to its new place after its title or author changed, the
  /// way Calibre does: the book folder [fromPath] becomes [toPath]
  /// (`books.path` values) and every file named [fromName] (`data.name`)
  /// is renamed to [toName], keeping its extension - so all formats
  /// (.epub, .pdf, ...) follow, and cover.jpg, metadata.opf and any other
  /// files move with the folder. The old author folder is removed if it is
  /// left empty.
  ///
  /// Throws if the book folder is missing or another folder is already at
  /// [toPath] - nothing is ever overwritten.
  Future<void> relocateBook({
    required String fromPath,
    required String toPath,
    required String fromName,
    required String toName,
    String? customPath,
  }) async {
    final root = await libraryRoot(customPath: customPath);
    final fromDir = Directory(p.joinAll([root, ...fromPath.split('/')]));
    final toDir = Directory(p.joinAll([root, ...toPath.split('/')]));
    if (!p.isWithin(root, fromDir.path) || !p.isWithin(root, toDir.path)) {
      throw FileSystemException('Invalid book path', toDir.path);
    }
    if (!await fromDir.exists()) {
      throw FileSystemException('Book folder not found', fromDir.path);
    }

    // 1) The folder.
    final sameFolder = p.equals(fromDir.path, toDir.path);
    if (!sameFolder) {
      if (await toDir.exists()) {
        throw FileSystemException('A folder already exists at the target', toDir.path);
      }
      await toDir.parent.create(recursive: true);
      try {
        await fromDir.rename(toDir.path);
      } on FileSystemException {
        // rename fails across drives (and sometimes on Android storage):
        // copy everything, then remove the old folder.
        await _copyDirectory(fromDir, toDir);
        try {
          await fromDir.delete(recursive: true);
        } catch (e) {
          debugPrint('Copied, but the old folder was not removed: $e');
        }
      }
    }

    // 2) The files inside: "<fromName>.<ext>" -> "<toName>.<ext>".
    if (fromName != toName) {
      final files = await toDir.list().where((e) => e is File).toList();
      for (final file in files) {
        if (p.basenameWithoutExtension(file.path) != fromName) continue;
        final target = p.join(toDir.path, '$toName${p.extension(file.path)}');
        if (p.equals(file.path, target) || await File(target).exists()) continue;
        await file.rename(target);
      }
    }

    // 3) Tidy up the old author folder (best effort).
    if (!sameFolder) {
      try {
        await _removeIfEmpty(fromDir, root);
        await _removeIfEmpty(fromDir.parent, root);
      } catch (e) {
        debugPrint('Old folder not removed (harmless): $e');
      }
    }
  }

  Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list()) {
      final target = p.join(to.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }

  Future<void> _cleanupEmptyDirs(String movedFilePath, {String? customPath}) async {
    try {
      final root = await libraryRoot(customPath: customPath);
      final titleDir = Directory(p.dirname(movedFilePath));
      await _removeIfEmpty(titleDir, root); // .../Author/Title
      await _removeIfEmpty(titleDir.parent, root); // .../Author
    } catch (e) {
      debugPrint('Old folder not removed (harmless): $e');
    }
  }

  /// Deletes the folder of a book (recursively), given its relative `path`
  /// from the DB.
  ///
  /// Returns `null` on success (a folder that is already gone counts as
  /// success) or an error message if it could not be deleted, so callers can
  /// stop before touching the database. Pass the current `pathProvider`
  /// value as [customPath].
  Future<String?> deleteBookFolder(String relativePath, {String? customPath}) async {
    final root = await libraryRoot(customPath: customPath);
    final dir = Directory(p.joinAll([root, ...relativePath.split('/')]));

    // Safety net: never delete the library itself or anything outside it
    // (e.g. if a book ever has an empty or '..' path).
    if (!p.isWithin(root, dir.path)) {
      return 'Invalid book path: "$relativePath"';
    }

    // On Windows a file can be locked for a moment (reader, OneDrive,
    // antivirus), so try a few times before giving up.
    Object? lastError;
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        debugPrint('Delete attempt $attempt failed: $e');
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    if (lastError != null) {
      // What matters is that the book FILES are gone. If only empty folders
      // are left (Windows/OneDrive refusing to remove the folder itself),
      // count it as success and leave the empty folder behind.
      if (await _containsFiles(dir)) return '$lastError';
      debugPrint('Book files deleted, empty folder left behind: $lastError');
      return null;
    }

    // Remove the now-empty author folder; best-effort only.
    try {
      await _removeIfEmpty(dir.parent, root);
    } catch (e) {
      debugPrint('Author folder not removed (harmless): $e');
    }
    return null;
  }

  /// Removes [dir] if it is empty. Retries a few times because OneDrive or
  /// Explorer can hold a folder for a moment. Never throws.
  Future<void> _removeIfEmpty(Directory dir, String root) async {
    if (p.equals(dir.path, root) || !p.isWithin(root, dir.path)) return;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        if (!await dir.exists()) return;
        if (!await dir.list().isEmpty) return; // still has content: keep it
        await dir.delete();
        return;
      } catch (e) {
        debugPrint('Folder not removed (attempt $attempt): $e');
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  Future<bool> _containsFiles(Directory dir) async {
    try {
      if (!await dir.exists()) return false;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) return true;
      }
      return false;
    } catch (_) {
      return true; // can't tell -> assume files are still there
    }
  }
}
