import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/utils/result.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;

import '../message.dart';
import '../utils/path_utils.dart';

/// Indexes Apex `.cls` files under a set of package directories and writes JSON
/// metadata files into a hidden `.sf-zed` folder at each workspace root.
final class ApexIndexer {
  ApexIndexer({required SfdxWorkspaceLocator sfdxWorkspaceLocator})
    : _sfdxWorkspaceLocator = sfdxWorkspaceLocator;

  static const String indexFolderName = '.sf-zed';

  final SfdxWorkspaceLocator _sfdxWorkspaceLocator;

  // Workspace roots discovered during initialize.
  List<Uri> _workspaceRootUris = <Uri>[];

  // Minimal in-memory completion index derived from `.sf-zed/*.json`.
  // Top-level for now: just known class names.
  final Set<String> indexedClassNames = <String>{};

  Stream<WorkDoneProgressParams> index(InitializedParams params) async* {
    final folders = params.workspaceFolders;
    if (folders == null || folders.isEmpty) return;

    final uris = <Uri>[];
    for (final folder in folders) {
      final uri = Uri.tryParse(folder.uri);
      if (uri != null) uris.add(uri);
    }
    _workspaceRootUris = uris;

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
        final rootPath = root.toFilePath(windows: Platform.isWindows);

        final packageDirsForRoot = packageDirectoryUris.where((pkgUri) {
          final pkgPath = pkgUri.toFilePath(windows: Platform.isWindows);
          return pkgPath.startsWith(rootPath);
        }).toList();

        yield* _indexWorkspace(
          workspaceRoot: root,
          packageDirectoryUris: packageDirsForRoot,
          token: token,
        );

        // Load class names from the generated `.sf-zed` JSON index.
        await _loadIndexedClassNamesForWorkspace(root);
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

  Future<void> _loadIndexedClassNamesForWorkspace(Uri workspaceRoot) async {
    final rootPath = workspaceRoot.toFilePath(windows: Platform.isWindows);
    final indexDir = Directory('$rootPath/.sf-zed');
    if (!await indexDir.exists()) return;

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

        // TODO: Everything is currently in memory, but at some point
        // we will want to actually load on completion request
        // to be more performant (or at least keep less things in memory)
        indexedClassNames.add(className);
      } catch (_) {
        // Ignore malformed index entries for now.
      }
    }
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
    final workspaceRootPath = _toFilePath(workspaceRoot);
    final workspaceRootDir = Directory(workspaceRootPath);

    // Ensure `.sf-zed` is created under the actual on-disk workspace directory.
    final indexDirPath = PathUtils.join(workspaceRootDir.path, indexFolderName);
    final indexDir = Directory(indexDirPath);

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
    final pkgDirPath = _toFilePath(pkgDirUri);
    final pkgDir = Directory(pkgDirPath);

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

      return Success(reflectionResponse.typeMirror!.name);
    } catch (e) {
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
}
