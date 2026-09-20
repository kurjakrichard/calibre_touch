import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FileService {
  /// The ONE place that defines where book files live.
  Future<String> libraryRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'ebooks');
  }

  /// Absolute path of a book file, built from the values stored in the DB.
  Future<String> bookFilePath({
    required String path,
    required String filename,
    required String format,
  }) async {
    return p.joinAll(
        [await libraryRoot(), ...path.split('/'), '$filename.$format']);
  }

  Future<bool> fileExists(String path) => File(path).exists();

  void openFile(String path) {
    OpenFilex.open(path);
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
  Future<void> moveBookFile({required String from, required String to}) async {
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
    unawaited(_cleanupEmptyDirs(from)); // runs in the background
  }

  Future<void> _cleanupEmptyDirs(String movedFilePath) async {
    try {
      final root = await libraryRoot();
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
  /// stop before touching the database.
  Future<String?> deleteBookFolder(String relativePath) async {
    final root = await libraryRoot();
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

  // Old API, still used by update_book2.dart
  Future<void> deleteBook(String oldPath) async {
    try {
      Directory dir = Directory(oldPath);
      Directory parentDir = dir.parent;
      await dir.delete(recursive: true);
      bool isEmpty = await Directory(parentDir.path).list().isEmpty;
      if (isEmpty) {
        parentDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Nincs ilyen fájl!');
    }
  }
}
