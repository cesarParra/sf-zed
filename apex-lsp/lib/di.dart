import 'dart:io';

import 'package:apex_lsp/completion/completion_aggregator.dart';
import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';
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
    locator.registerSingleton<LspOut>(LspOut(output: StdoutByteSink(stdout)));
  }

  if (!locator.isRegistered<SfdxWorkspaceLocator>()) {
    locator.registerSingleton<SfdxWorkspaceLocator>(
      SfdxWorkspaceLocator(
        fileSystem: locator<FileSystem>(),
        platform: locator<LspPlatform>(),
      ),
    );
  }

  if (!locator.isRegistered<ApexIndexer>()) {
    locator.registerSingleton<ApexIndexer>(
      ApexIndexer(
        sfdxWorkspaceLocator: locator<SfdxWorkspaceLocator>(),
        fileSystem: locator<FileSystem>(),
        platform: locator<LspPlatform>(),
      ),
    );
  }

  if (!locator.isRegistered<CompletionAggregator>()) {
    locator.registerLazySingleton<CompletionAggregator>(() {
      final libPath =
          Platform.environment['TS_SFAPEX_LIB'] ??
          '/Users/cesarparra/IdeaProjects/sf-zed/apex-lsp/libtree_sitter_sfapex.dylib';

      final bindings = TreeSitterBindings.load(path: libPath);
      final treeSitterService = TreeSitterCompletionService(bindings: bindings);
      final completionAggregator = CompletionAggregator(
        documentService: treeSitterService,
        indexedClassesRepository: ApexIndexerWorkspaceIndexAdapter(
          locator<ApexIndexer>(),
        ),
      );
      return completionAggregator;
    });
  }

  if (!locator.isRegistered<ExitFn>()) {
    locator.registerFactory<ExitFn>(() => exit);
  }
}
