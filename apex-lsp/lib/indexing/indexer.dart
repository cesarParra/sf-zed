import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;

import '../utils/path_utils.dart';

/// Indexes Apex `.cls` files under a set of package directories and writes JSON
/// metadata files into a hidden `.sf-zed` folder at each workspace root.
final class ApexIndexer {
  const ApexIndexer();

  static const String indexFolderName = '.sf-zed';

  /// Builds the index for a single workspace.
  ///
  /// [workspaceRoot] should be a `file://` URI.
  /// [packageDirectoryUris] are absolute directory URIs.
  Future<void> indexWorkspace({
    required Uri workspaceRoot,
    required List<Uri> packageDirectoryUris,
  }) async {
    _log('Indexing workspaceRoot=$workspaceRoot');

    final workspaceRootPath = _toFilePath(workspaceRoot);
    _log('workspaceRootPath=$workspaceRootPath');

    final workspaceRootDir = Directory(workspaceRootPath);
    _log(
      'workspaceRootDir.exists=${await workspaceRootDir.exists()} path=${workspaceRootDir.path}',
    );

    // Ensure `.sf-zed` is created under the actual on-disk workspace directory.
    final indexDirPath = PathUtils.join(workspaceRootDir.path, indexFolderName);
    final indexDir = Directory(indexDirPath);

    _log('indexDirPath=$indexDirPath');

    // At the moment, we always recreate the index from scratch.
    if (await indexDir.exists()) {
      _log('Deleting existing index dir: ${indexDir.path}');
      await indexDir.delete(recursive: true);
    }

    await indexDir.create(recursive: true);
    _log(
      'Created index dir: ${indexDir.path} (exists=${await indexDir.exists()})',
    );

    if (packageDirectoryUris.isEmpty) {
      _log('No package directories provided for indexing; nothing to do.');
    } else {
      _log('Package directories to scan:');
      for (final uri in packageDirectoryUris) {
        _log('  - $uri -> ${_toFilePath(uri)}');
      }
    }

    for (final pkgDirUri in packageDirectoryUris) {
      await _indexPackageDirectory(pkgDirUri, workspaceRoot, indexDir);
    }

    _log('Index output dir: ${indexDir.path}');
  }

  Future<void> _indexPackageDirectory(
    Uri pkgDirUri,
    Uri workspaceRoot,
    Directory indexDir,
  ) async {
    final pkgDirPath = _toFilePath(pkgDirUri);
    final pkgDir = Directory(pkgDirPath);

    final exists = await pkgDir.exists();
    _log('Scanning packageDir=$pkgDirUri path=$pkgDirPath exists=$exists');

    if (!exists) {
      return;
    }

    await for (final entity in pkgDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      if (!entity.path.toLowerCase().endsWith('.cls')) {
        continue;
      }

      await _indexSingleFile(
        workspaceRoot: workspaceRoot,
        indexDir: indexDir,
        apexFile: entity,
      );
    }
  }

  Future<bool> _indexSingleFile({
    required Uri workspaceRoot,
    required Directory indexDir,
    required File apexFile,
  }) async {
    try {
      final source = await apexFile.readAsString();
      final reflectionResponse = apex_reflection.Reflection.reflect(source);

      if (reflectionResponse.error != null) {
        _log(
          'Error reflecting ${apexFile.path}: ${reflectionResponse.error!.message}',
        );
        return false;
      }

      final className = reflectionResponse.typeMirror!.name;

      final outPath = PathUtils.join(indexDir.path, '$className.json');
      final outFile = File(outPath);

      final relativePath = _safeRelativePath(
        fromRoot: workspaceRoot,
        absolutePath: apexFile.path,
      );

      // TODO: This can be a standalone object rather than using maps
      final payload = <String, Object?>{
        'schemaVersion': 1,
        'className': className,
        'source': <String, Object?>{
          'uri': Uri.file(apexFile.path).toString(),
          'relativePath': relativePath,
        },
        'reflection': reflectionResponse.toJson(),
      };

      await outFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );

      _log('Wrote index file: $outPath');
      return true;
    } catch (e) {
      _log('Failed to index ${apexFile.path}: $e');
      return false;
    }
  }

  static String _toFilePath(Uri uri) {
    return uri.toFilePath(windows: Platform.isWindows);
  }

  /// Returns a best-effort relative path from [fromRoot] to [absolutePath].
  /// If the paths can’t be made relative (different roots), returns [absolutePath].
  static String _safeRelativePath({
    required Uri fromRoot,
    required String absolutePath,
  }) {
    final rootPath = _toFilePath(fromRoot);
    if (absolutePath.startsWith(rootPath)) {
      var rel = absolutePath.substring(rootPath.length);
      if (rel.startsWith(Platform.pathSeparator)) {
        rel = rel.substring(1);
      }
      return rel;
    }
    return absolutePath;
  }

  void _log(String message) {
    // Minimal, always-on logging for debugging indexing behavior.
    // (We don't have access to the server’s LSP logger from here.)
    stderr.writeln('[apex-lsp][indexer] $message');
  }
}
