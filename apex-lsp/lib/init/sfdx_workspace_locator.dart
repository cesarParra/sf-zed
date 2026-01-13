import 'dart:convert';
import 'dart:io';

import '../sfdx_project.dart';
import '../utils/path_utils.dart';

/// Discovers Salesforce DX workspace metadata from a workspace root.
final class SfdxWorkspaceLocator {
  const SfdxWorkspaceLocator();

  static const String sfdxProjectFileName = 'sfdx-project.json';

  /// Returns the absolute URI to `sfdx-project.json` for [workspaceRoot], if it exists.
  Future<Uri?> findSfdxProjectFile(Uri workspaceRoot) async {
    final rootPath = workspaceRoot.toFilePath(windows: Platform.isWindows);
    final file = File('$rootPath/$sfdxProjectFileName');
    if (!await file.exists()) return null;
    return workspaceRoot.resolve(sfdxProjectFileName);
  }

  /// Loads and parses `sfdx-project.json` for [workspaceRoot], if present.
  ///
  /// Returns `null` if the file is missing or cannot be parsed.
  Future<SfdxProject?> loadProject(Uri workspaceRoot) async {
    final rootPath = workspaceRoot.toFilePath(windows: Platform.isWindows);
    final file = File('$rootPath/$sfdxProjectFileName');
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, Object?>) return null;
      return SfdxProject.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Computes the package directory scope for indexing, anchored at [workspaceRoot].
  ///
  /// Returns a list of absolute directory URIs (each with a trailing slash).
  Future<List<Uri>> packageDirectoryScope(Uri workspaceRoot) async {
    final project = await loadProject(workspaceRoot);
    final dirs = project?.packageDirectories;
    if (dirs == null || dirs.isEmpty) {
      return const <Uri>[];
    }

    final rootPath = workspaceRoot.toFilePath(windows: Platform.isWindows);

    final scope = <Uri>[];
    for (final dir in dirs) {
      final relative = dir.path.trim();
      if (relative.isEmpty) {
        continue;
      }

      final resolvedPath = PathUtils.join(rootPath, relative);
      final resolvedDir = Directory(resolvedPath);

      // Ensure the URI represents a directory.
      scope.add(Uri.directory(resolvedDir.path));
    }

    return scope;
  }

  /// Computes the combined package directory scope across multiple workspace roots.
  Future<List<Uri>> packageDirectoryScopeForWorkspaces(
    List<Uri> workspaceRoots,
  ) async {
    final all = <Uri>[];
    for (final root in workspaceRoots) {
      all.addAll(await packageDirectoryScope(root));
    }
    return all;
  }
}
