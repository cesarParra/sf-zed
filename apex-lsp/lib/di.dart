import 'dart:io';

import 'package:apex_lsp/lsp_out.dart';
import 'package:get_it/get_it.dart';

import 'indexing/indexer.dart';
import 'init/sfdx_workspace_locator.dart';
import 'server.dart';

final locator = GetIt.I;

void initializeDependencies({GetIt? getIt}) {
  final serviceLocator = getIt ?? locator;

  if (!serviceLocator.isRegistered<LspOut>()) {
    serviceLocator.registerSingleton<LspOut>(
      LspOut(output: StdoutByteSink(stdout)),
    );
  }

  if (!serviceLocator.isRegistered<SfdxWorkspaceLocator>()) {
    serviceLocator.registerSingleton<SfdxWorkspaceLocator>(
      const SfdxWorkspaceLocator(),
    );
  }

  if (!serviceLocator.isRegistered<ApexIndexer>()) {
    serviceLocator.registerFactory<ApexIndexer>(
      () => ApexIndexer(logger: serviceLocator<LspOut>()),
    );
  }

  if (!serviceLocator.isRegistered<ExitFn>()) {
    serviceLocator.registerFactory<ExitFn>(() => exit);
  }
}
