import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/utils/result.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;

import '../lsp_out.dart';
import '../message.dart';
import '../utils/path_utils.dart';

/// Indexes Apex `.cls` files under a set of package directories and writes JSON
/// metadata files into a hidden `.sf-zed` folder at each workspace root.
final class ApexIndexer {
  ApexIndexer({
    required LspOut logger,
    required SfdxWorkspaceLocator sfdxWorkspaceLocator,
  }) : _logger = logger,
       _sfdxWorkspaceLocator = sfdxWorkspaceLocator;

  static const String indexFolderName = '.sf-zed';

  final SfdxWorkspaceLocator _sfdxWorkspaceLocator;
  final LspOut _logger;

  // Workspace roots discovered during initialize.
  List<Uri> _workspaceRootUris = <Uri>[];

  // Source-of-truth index scope: all package directories across workspace roots.
  List<Uri> _packageDirectoryUris = <Uri>[];

  ProgressToken? _progressToken;

  // Minimal in-memory completion index derived from `.sf-zed/*.json`.
  // Top-level for now: just known class names.
  final Set<String> indexedClassNames = <String>{};

  Future<void> prepare(InitializeRequest req) async {
    final folders = req.params.workspaceFolders;
    if (folders == null || folders.isEmpty) return;

    final uris = <Uri>[];
    for (final folder in folders) {
      final uri = Uri.tryParse(folder.uri);
      if (uri != null) uris.add(uri);
    }
    _workspaceRootUris = uris;

    // Load SFDX project configs (if present) and compute package directory roots.
    _packageDirectoryUris = await _sfdxWorkspaceLocator
        .packageDirectoryScopeForWorkspaces(_workspaceRootUris);
  }

  /// Sends a work-done progress begin message for indexing.
  ///
  /// Prepares the progress token used for subsequent progress reports/ending.
  Future<void> begingIndexing() async {
    final token = ProgressToken.string(
      'apex-lsp-indexing-${DateTime.now().millisecondsSinceEpoch}',
    );

    await _logger.workDoneProgressCreate(token: token);
    await _logger.progress(
      token: token,
      value: const WorkDoneProgressBegin(
        title: 'Indexing Apex files',
        message: 'Preparing workspace index…',
        cancellable: false,
      ),
    );

    _progressToken = token;

    await _indexInBackground();
  }

  Future<void> _indexInBackground() async {
    if (_workspaceRootUris.isEmpty) {
      await _endIndexingProgress(message: 'Indexing complete (no workspaces)');
      return;
    }

    try {
      _logger.debug(
        'Indexing starting. Workspaces=${_workspaceRootUris.length}, '
        'packageDirs(total)=${_packageDirectoryUris.length}',
      );

      // The current design keeps `_packageDirectoryUris` as a combined scope across
      // all workspace roots. For indexing, we do a best-effort association:
      // index each workspace using the package directories that are under it.
      for (final root in _workspaceRootUris) {
        final rootPath = root.toFilePath(windows: Platform.isWindows);

        final packageDirsForRoot = _packageDirectoryUris.where((pkgUri) {
          final pkgPath = pkgUri.toFilePath(windows: Platform.isWindows);
          return pkgPath.startsWith(rootPath);
        }).toList();

        _logger.debug(
          'Indexing workspace root=$root (rootPath=$rootPath), '
          'packageDirs(forRoot)=${packageDirsForRoot.length}',
        );

        if (packageDirsForRoot.isNotEmpty) {
          _logger.debug(
            'Package dirs for $root: ${packageDirsForRoot.join(', ')}',
          );
        }

        await _indexWorkspace(
          workspaceRoot: root,
          packageDirectoryUris: packageDirsForRoot,
        );

        // Load class names from the generated `.sf-zed` JSON index.
        final loaded = await _loadIndexedClassNamesForWorkspace(root);
        _logger.debug('Loaded $loaded indexed class names for $root');
      }

      await _endIndexingProgress(message: 'Indexing complete');
      _logger.debug('Indexing complete');
    } catch (e) {
      await _endIndexingProgress(message: 'Indexing failed');
      await _logger.logMessage(MessageType.error, 'Indexing failed: $e');
    }
  }

  Future<int> _loadIndexedClassNamesForWorkspace(Uri workspaceRoot) async {
    final rootPath = workspaceRoot.toFilePath(windows: Platform.isWindows);
    final indexDir = Directory('$rootPath/.sf-zed');
    if (!await indexDir.exists()) return 0;

    var loaded = 0;

    await for (final entity in indexDir.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.json')) continue;

      try {
        final content = await entity.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is! Map) continue;

        final source = decoded['source'];
        if (source is! Map) continue;

        final relativePath = source['relativePath'];
        if (relativePath is! String) continue;

        final fileName = relativePath.split(Platform.pathSeparator).last;
        if (!fileName.toLowerCase().endsWith('.cls')) continue;

        final className = fileName.substring(0, fileName.length - 4);
        if (className.isEmpty) continue;

        if (indexedClassNames.add(className)) {
          loaded++;
        }
      } catch (_) {
        // Ignore malformed index entries for now.
      }
    }

    return loaded;
  }

  /// Builds the index for a single workspace.
  ///
  /// [workspaceRoot] should be a `file://` URI.
  /// [packageDirectoryUris] are absolute directory URIs.
  Future<void> _indexWorkspace({
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
            // Notify every 1% increase based on total file count.
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

  Future<void> _endIndexingProgress({required String message}) async {
    if (_progressToken == null) return;

    await _logger.progress(
      token: _progressToken!,
      value: WorkDoneProgressEnd(message: message),
    );

    // Reset token so a future re-index can start a new progress session cleanly.
    _progressToken = null;
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
    if (_progressToken == null) return;

    await _logger.progress(
      token: _progressToken!,
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
