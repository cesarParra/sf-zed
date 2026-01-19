import 'dart:async';
import 'dart:convert';

import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:apex_lsp/utils/result.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;
import 'package:file/file.dart';

import '../message.dart';

/// Indexes Apex `.cls` files under a set of package directories and writes JSON
/// metadata files into a hidden `.sf-zed` folder at each workspace root.
final class ApexIndexer {
  ApexIndexer({
    required SfdxWorkspaceLocator sfdxWorkspaceLocator,
    required FileSystem fileSystem,
    required LspPlatform platform,
  }) : _sfdxWorkspaceLocator = sfdxWorkspaceLocator,
       _fileSystem = fileSystem,
       _platform = platform;

  static const String indexFolderName = '.sf-zed';

  final SfdxWorkspaceLocator _sfdxWorkspaceLocator;
  final FileSystem _fileSystem;
  final LspPlatform _platform;

  // Workspace roots discovered during initialize.
  List<Uri> _workspaceRootUris = <Uri>[];

  // Minimal in-memory completion index derived from `.sf-zed/*.json`.
  // Top-level for now: just known class names.
  final Set<String> _indexedClassNames = <String>{};
  bool _indexedClassNamesLoaded = false;

  Set<String> get indexedClassNames {
    _ensureIndexedClassNamesLoaded();
    return _indexedClassNames;
  }

  final _indexedClassByNameCache = <String, apex_reflection.ClassMirror>{};
  final Set<String> _workspaceClassNotFound = <String>{};

  Stream<WorkDoneProgressParams> index(InitializedParams params) async* {
    final folders = params.workspaceFolders;
    if (folders == null || folders.isEmpty) return;

    final uris = <Uri>[];
    for (final folder in folders) {
      final uri = Uri.tryParse(folder.uri);
      if (uri != null) uris.add(uri);
    }
    _workspaceRootUris = uris;
    _resetCachesForReindex();

    // Load SFDX project configs (if present) and compute package directory roots.
    final packageDirectoryUris = await _sfdxWorkspaceLocator
        .packageDirectoryScopeForWorkspaces(_workspaceRootUris);
    final token = _generateProgressToken(
      packageDirectoryUris: packageDirectoryUris,
    );
    yield WorkDoneProgressParams(
      token: token,
      value: const WorkDoneProgressBegin(
        title: 'Indexing Apex files',
        message: 'Preparing workspace index…',
        cancellable: false,
      ),
    );

    yield* _indexInBackground(
      packageDirectoryUris: packageDirectoryUris,
      token: token,
    );
  }

  ProgressToken _generateProgressToken({
    required List<Uri> packageDirectoryUris,
  }) {
    return ProgressToken.string(
      'apex-lsp-indexing-${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  Stream<WorkDoneProgressParams> _indexInBackground({
    required List<Uri> packageDirectoryUris,
    required ProgressToken token,
  }) async* {
    if (_workspaceRootUris.isEmpty) {
      yield WorkDoneProgressParams(
        token: token,
        value: WorkDoneProgressEnd(
          message: 'Indexing complete (no workspaces)',
        ),
      );
      return;
    }

    try {
      // The current design keeps `_packageDirectoryUris` as a combined scope across
      // all workspace roots. For indexing, we do a best-effort association:
      // index each workspace using the package directories that are under it.
      for (final root in _workspaceRootUris) {
        final rootPath = root.toFilePath(windows: _platform.isWindows);

        final packageDirsForRoot = packageDirectoryUris.where((pkgUri) {
          final pkgPath = pkgUri.toFilePath(windows: _platform.isWindows);
          return pkgPath.startsWith(rootPath);
        }).toList();

        yield* _indexWorkspace(
          workspaceRoot: root,
          packageDirectoryUris: packageDirsForRoot,
          token: token,
        );

        // Class names are loaded lazily on demand.
      }

      yield WorkDoneProgressParams(
        token: token,
        value: WorkDoneProgressEnd(message: 'Indexing complete'),
      );
    } catch (e) {
      yield WorkDoneProgressParams(
        token: token,
        value: WorkDoneProgressEnd(message: 'Indexing failed'),
      );
    }
  }

  void _resetCachesForReindex() {
    _indexedClassNamesLoaded = false;
    _indexedClassNames.clear();
    _indexedClassByNameCache.clear();
    _workspaceClassNotFound.clear();
  }

  void _ensureIndexedClassNamesLoaded() {
    if (_indexedClassNamesLoaded) return;

    if (_workspaceRootUris.isEmpty) {
      _indexedClassNamesLoaded = true;
      return;
    }

    for (final root in _workspaceRootUris) {
      _loadIndexedClassNamesForWorkspace(root);
    }

    _indexedClassNamesLoaded = true;
  }

  void _loadIndexedClassNamesForWorkspace(Uri workspaceRoot) {
    final rootPath = workspaceRoot.toFilePath(windows: _platform.isWindows);
    final indexDir = _fileSystem.directory(
      _fileSystem.path.join(rootPath, indexFolderName),
    );
    if (!indexDir.existsSync()) return;

    for (final entity in indexDir.listSync(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.json')) continue;

      try {
        final fileName = _fileSystem.path.basename(entity.path);
        if (!fileName.toLowerCase().endsWith('.json')) continue;

        final className = fileName.substring(0, fileName.length - 5);
        if (className.isEmpty) continue;

        _indexedClassNames.add(className);
      } catch (_) {
        // Ignore malformed index entries for now.
      }
    }
  }

  Future<apex_reflection.ClassMirror?> loadWorkspaceClassInfo(
    String className,
  ) async {
    if (className.isEmpty) return null;

    final cached = _indexedClassByNameCache[className];
    if (cached != null) return cached;

    if (_workspaceClassNotFound.contains(className)) return null;

    for (final root in _workspaceRootUris) {
      final info = await _tryLoadWorkspaceClassInfoForRoot(root, className);
      if (info != null) {
        _indexedClassByNameCache[className] = info;
        return info;
      }
    }

    _workspaceClassNotFound.add(className);
    return null;
  }

  Future<apex_reflection.ClassMirror?> _tryLoadWorkspaceClassInfoForRoot(
    Uri workspaceRoot,
    String className,
  ) async {
    final rootPath = workspaceRoot.toFilePath(windows: _platform.isWindows);
    final indexDirPath = _fileSystem.path.join(rootPath, indexFolderName);
    final filePath = _fileSystem.path.join(indexDirPath, '$className.json');
    final file = _fileSystem.file(filePath);

    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      return _parseIndexedClassInfo(decoded);
    } catch (_) {
      return null;
    }
  }

  apex_reflection.ClassMirror? _parseIndexedClassInfo(Object? decoded) {
    if (decoded is! Map) return null;
    final typeMirror = decoded['typeMirror'];
    if (typeMirror is! Map) return null;

    final classMirror = apex_reflection.ClassMirror.fromJson(
      typeMirror as Map<String, dynamic>,
    );

    return classMirror;
  }

  /// Builds the index for a single workspace.
  ///
  /// [workspaceRoot] should be a `file://` URI.
  /// [packageDirectoryUris] are absolute directory URIs.
  Stream<WorkDoneProgressParams> _indexWorkspace({
    required Uri workspaceRoot,
    required List<Uri> packageDirectoryUris,
    required ProgressToken token,
  }) async* {
    final workspaceRootPath = workspaceRoot.toFilePath(
      windows: _platform.isWindows,
    );
    final workspaceRootDir = _fileSystem.directory(workspaceRootPath);

    // Ensure `.sf-zed` is created under the actual on-disk workspace directory.
    final indexDirPath = _fileSystem.path.join(
      workspaceRootDir.path,
      indexFolderName,
    );
    final indexDir = _fileSystem.directory(indexDirPath);

    // At the moment, we always recreate the index from scratch.
    if (await indexDir.exists()) {
      await indexDir.delete(recursive: true);
    }

    await indexDir.create(recursive: true);

    // Compute total files up-front so we can report accurate progress as we go.
    final totalFiles = await _countApexFilesToIndex(packageDirectoryUris);

    var processedFiles = 0;
    var lastReportedPercent = -1;

    for (final pkgDirUri in packageDirectoryUris) {
      yield* _indexPackageDirectory(
        pkgDirUri,
        workspaceRoot,
        indexDir,
        totalFiles: totalFiles,
        processedFiles: processedFiles,
        lastReportedPercent: lastReportedPercent,
        token: token,
      );
    }

    // Ensure we end on 100% if there was anything to do.
    if (totalFiles > 0 && lastReportedPercent < 100) {
      yield WorkDoneProgressParams(
        token: token,
        value: WorkDoneProgressReport(percentage: 100),
      );
    }
  }

  Stream<WorkDoneProgressParams> _indexPackageDirectory(
    Uri pkgDirUri,
    Uri workspaceRoot,
    Directory indexDir, {
    required int totalFiles,
    required int processedFiles,
    required int lastReportedPercent,
    required ProgressToken token,
  }) async* {
    final pkgDirPath = pkgDirUri.toFilePath(windows: _platform.isWindows);
    final pkgDir = _fileSystem.directory(pkgDirPath);

    final exists = await pkgDir.exists();

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
              yield WorkDoneProgressParams(
                token: token,
                value: WorkDoneProgressReport(
                  percentage: percent,
                  message: value,
                  cancellable: false,
                ),
              );
            }
          }
        case Failure():
          // Ignoring indexing issues for now.
          break;
      }
    }
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
        return Failure(reflectionResponse.error!.message);
      }

      final className = reflectionResponse.typeMirror!.name;

      final outPath = _fileSystem.path.join(indexDir.path, '$className.json');
      final outFile = _fileSystem.file(outPath);

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
        'typeMirror': reflectionResponse.typeMirror!.toJson(),
      };

      await outFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );

      return Success(reflectionResponse.typeMirror!.name);
    } catch (e) {
      return Failure('Failed to index ${apexFile.path}: $e');
    }
  }

  /// Returns a best-effort relative path from [fromRoot] to [absolutePath].
  /// If the paths can’t be made relative (different roots), returns [absolutePath].
  String _safeRelativePath({
    required Uri fromRoot,
    required String absolutePath,
  }) {
    final rootPath = fromRoot.toFilePath(windows: _platform.isWindows);
    if (absolutePath.startsWith(rootPath)) {
      var rel = absolutePath.substring(rootPath.length);
      if (rel.startsWith(_platform.pathSeparator)) {
        rel = rel.substring(1);
      }
      return rel;
    }
    return absolutePath;
  }

  Future<int> _countApexFilesToIndex(List<Uri> packageDirectoryUris) async {
    var total = 0;

    for (final pkgDirUri in packageDirectoryUris) {
      final pkgDirPath = pkgDirUri.toFilePath(windows: _platform.isWindows);
      final pkgDir = _fileSystem.directory(pkgDirPath);

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
}
