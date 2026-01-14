import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apex_lsp/utils/result.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;

import '../lsp_out.dart';
import '../message.dart';
import '../utils/path_utils.dart';

/// Indexes Apex `.cls` files under a set of package directories and writes JSON
/// metadata files into a hidden `.sf-zed` folder at each workspace root.
final class ApexIndexer {
  const ApexIndexer({
    required LspOut logger,
    required ProgressToken? progressToken,
  }) : _logger = logger,
       _indexingProgressToken = progressToken;

  static const String indexFolderName = '.sf-zed';

  final LspOut _logger;
  final ProgressToken? _indexingProgressToken;

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

    // Compute total files up-front so we can report accurate progress as we go.
    final totalFiles = await _countApexFilesToIndex(packageDirectoryUris);
    _log('Total Apex files to index: $totalFiles');

    var processedFiles = 0;
    var lastReportedPercent = -1;

    for (final pkgDirUri in packageDirectoryUris) {
      final result = await _indexPackageDirectory(
        pkgDirUri,
        workspaceRoot,
        indexDir,
        totalFiles: totalFiles,
        processedFiles: processedFiles,
        lastReportedPercent: lastReportedPercent,
      );

      processedFiles = result.processedFiles;
      lastReportedPercent = result.lastReportedPercent;
    }

    // Ensure we end on 100% if there was anything to do.
    if (totalFiles > 0 && lastReportedPercent < 100) {
      await _reportProgress(percentage: 100);
    }

    _log('Index output dir: ${indexDir.path}');
  }

  Future<_IndexProgressState> _indexPackageDirectory(
    Uri pkgDirUri,
    Uri workspaceRoot,
    Directory indexDir, {
    required int totalFiles,
    required int processedFiles,
    required int lastReportedPercent,
  }) async {
    final pkgDirPath = _toFilePath(pkgDirUri);
    final pkgDir = Directory(pkgDirPath);

    final exists = await pkgDir.exists();
    _log('Scanning packageDir=$pkgDirUri path=$pkgDirPath exists=$exists');

    if (!exists) {
      return _IndexProgressState(
        processedFiles: processedFiles,
        lastReportedPercent: lastReportedPercent,
      );
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

      final result = await _indexSingleFile(
        workspaceRoot: workspaceRoot,
        indexDir: indexDir,
        apexFile: entity,
      );

      switch (result) {
        case Success(:final value):
          processedFiles++;

          if (totalFiles > 0) {
            final percent = ((processedFiles * 100) / totalFiles).floor();
            // Notify every 1% increase (1, 2, 3, ...), based on total file count.
            if (percent >= 1 &&
                percent <= 100 &&
                percent > lastReportedPercent) {
              lastReportedPercent = percent;
              await _reportProgress(percentage: percent, fileName: value);
            }
          }
        case Failure():
          // Ignoring indexing issues for now.
          break;
      }
    }

    return _IndexProgressState(
      processedFiles: processedFiles,
      lastReportedPercent: lastReportedPercent,
    );
  }

  Future<Result<String>> _indexSingleFile({
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
        return Failure(reflectionResponse.error!.message);
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
      return Success(reflectionResponse.typeMirror!.name);
    } catch (e) {
      _log('Failed to index ${apexFile.path}: $e');
      return Failure('Failed to index ${apexFile.path}: $e');
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

  Future<int> _countApexFilesToIndex(List<Uri> packageDirectoryUris) async {
    var total = 0;

    for (final pkgDirUri in packageDirectoryUris) {
      final pkgDirPath = _toFilePath(pkgDirUri);
      final pkgDir = Directory(pkgDirPath);

      if (!await pkgDir.exists()) {
        continue;
      }

      await for (final entity in pkgDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (!entity.path.toLowerCase().endsWith('.cls')) continue;
        total++;
      }
    }

    return total;
  }

  Future<void> _reportProgress({
    required int percentage,
    String? fileName,
  }) async {
    final token = _indexingProgressToken;
    if (token == null) {
      _log('Indexing Apex files ($percentage%).');
      return;
    }

    await _logger.progress(
      token: token,
      value: WorkDoneProgressReport(
        percentage: percentage,
        message: fileName,
        cancellable: false,
      ),
    );
  }

  void _log(String message) async {
    _logger.debug('[indexer] $message');
  }
}

final class _IndexProgressState {
  final int processedFiles;
  final int lastReportedPercent;

  const _IndexProgressState({
    required this.processedFiles,
    required this.lastReportedPercent,
  });
}
