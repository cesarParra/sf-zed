import 'dart:io' as io;

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';
import 'package:apex_lsp/indexing/revamped.dart';
import 'package:apex_lsp/indexing/tree_sitter_indexer.dart';
import 'package:apex_lsp/lsp_out.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:get_it/get_it.dart';

import 'indexing/indexer.dart';
import 'indexing/sfdx_workspace_locator.dart';
import 'server.dart';

final locator = GetIt.I;

void initializeDependencies() {
  if (!locator.isRegistered<FileSystem>()) {
    locator.registerSingleton<FileSystem>(const LocalFileSystem());
  }

  if (!locator.isRegistered<LspPlatform>()) {
    locator.registerSingleton<LspPlatform>(const DartIoLspPlatform());
  }

  if (!locator.isRegistered<LspOut>()) {
    locator.registerSingleton<LspOut>(
      LspOut(output: StdoutByteSink(io.stdout)),
    );
  }

  if (!locator.isRegistered<SfdxWorkspaceLocator>()) {
    locator.registerSingleton<SfdxWorkspaceLocator>(
      SfdxWorkspaceLocator(
        fileSystem: locator<FileSystem>(),
        platform: locator<LspPlatform>(),
      ),
    );
  }

  if (!locator.isRegistered<Indexer>()) {
    locator.registerSingleton<Indexer>(
      Indexer(
        sfdxWorkspaceLocator: locator<SfdxWorkspaceLocator>(),
        fileSystem: locator<FileSystem>(),
        platform: locator<LspPlatform>(),
      ),
    );
  }

  if (!locator.isRegistered<TreeSitterIndexer>()) {
    locator.registerLazySingleton<TreeSitterIndexer>(() {
      String resolveFromCurrentDirectory(String location) {
        final fileSystem = locator<FileSystem>();
        final scriptDir = fileSystem.path.dirname(
          io.Platform.script.toFilePath(),
        );
        return fileSystem.path.join(scriptDir, location);
      }

      final bindings = TreeSitterBindings.load(
        pathResolver: resolveFromCurrentDirectory,
        path: io.Platform.environment['TS_SFAPEX_LIB'],
      );

      return TreeSitterIndexer(bindings: bindings);
    });
  }

  if (!locator.isRegistered<IndexedClassProvider>()) {
    locator.registerLazySingleton<IndexedClassProvider>(() {
      return ApexIndexerWorkspaceIndexAdapter(locator<ApexIndexer>());
    });
  }

  if (!locator.isRegistered<ExitFn>()) {
    locator.registerFactory<ExitFn>(() => io.exit);
  }
}
