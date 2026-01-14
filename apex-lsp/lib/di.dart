import 'dart:io';

import 'package:apex_lsp/lsp_out.dart';
import 'package:get_it/get_it.dart';

import 'indexing/indexer.dart';
import 'init/sfdx_workspace_locator.dart';
import 'message.dart';
import 'server.dart';

final locator = GetIt.I;

void initializeDependencies() {
  if (!locator.isRegistered<LspOut>()) {
    locator.registerSingleton<LspOut>(LspOut(output: StdoutByteSink(stdout)));
  }

  if (!locator.isRegistered<SfdxWorkspaceLocator>()) {
    locator.registerSingleton<SfdxWorkspaceLocator>(
      const SfdxWorkspaceLocator(),
    );
  }

  if (!locator.isRegistered<ApexIndexer>()) {
    locator.registerFactoryParam<ApexIndexer, ProgressToken?, void>(
      (progressToken, _) => ApexIndexer(
        logger: locator<LspOut>(),
        progressToken: progressToken is ProgressToken ? progressToken : null,
      ),
    );
  }

  if (!locator.isRegistered<ExitFn>()) {
    locator.registerFactory<ExitFn>(() => exit);
  }
}
