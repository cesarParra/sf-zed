import 'package:test/test.dart';

import '../../support/lsp_client.dart';
import '../../support/lsp_matchers.dart';
import '../../support/test_workspace.dart';
import '../integration_server.dart';

void main() {
  group('LSP Completion', () {
    late TestWorkspace workspace;
    late LspClient client;

    setUp(() async {
      workspace = await createTestWorkspace(
        classFiles: {
          'Foo.cls': 'public class Foo {\n'
              '  public static void hello() {}\n'
              '}',
          'Season.cls': 'public enum Season { SPRING, SUMMER, FALL, WINTER }',
          'Greeter.cls': 'public interface Greeter {\n'
              '  String greet();\n'
              '  void sayGoodbye();\n'
              '}',
        },
      );
      client = createLspClient()..start();
      await client.initialize(
        workspaceUri: workspace.uri,
        waitForIndexing: true,
      );
    });

    tearDown(() async {
      await client.dispose();
      await deleteTestWorkspace(workspace);
    });

    test('completes local variables', () async {
      const documentUri = 'file:///test/anon.apex';
      const text = "String myVariable = 'hello';\nmy";
      await client.openDocument(uri: documentUri, text: text);

      final completions = await client.completion(
        uri: documentUri,
        line: 1,
        character: 2,
      );

      expect(completions, containsCompletion('myVariable'));
    });

    test('completes enum values via dot access', () async {
      const documentUri = 'file:///test/anon.apex';
      // The enum must be defined in the same document because the server's
      // completion handler uses the local indexer on the open document text.
      const text = 'public enum Season { SPRING, SUMMER, FALL, WINTER }\n'
          'Season.';
      await client.openDocument(uri: documentUri, text: text);

      final completions = await client.completion(
        uri: documentUri,
        line: 1,
        character: 7,
      );

      expect(
        completions,
        containsCompletions(['SPRING', 'SUMMER', 'FALL', 'WINTER']),
      );
    });

    test('completes interface methods via dot access', () async {
      const documentUri = 'file:///test/anon.apex';
      const text = 'public interface Greeter {\n'
          '  String greet();\n'
          '  void sayGoodbye();\n'
          '}\n'
          'Greeter g;\n'
          'g.';
      await client.openDocument(uri: documentUri, text: text);

      final completions = await client.completion(
        uri: documentUri,
        line: 5,
        character: 2,
      );

      expect(completions, containsCompletions(['greet', 'sayGoodbye']));
    });

    test('returns empty completions for empty context', () async {
      const documentUri = 'file:///test/anon.apex';
      const text = '';
      await client.openDocument(uri: documentUri, text: text);

      final completions = await client.completion(
        uri: documentUri,
        line: 0,
        character: 0,
      );

      expect(completions, hasNoCompletions);
    });

    test('completions update after document change', () async {
      const documentUri = 'file:///test/anon.apex';
      const initialText = 'String firstName = \'a\';\nfir';
      await client.openDocument(uri: documentUri, text: initialText);

      final first = await client.completion(
        uri: documentUri,
        line: 1,
        character: 3,
      );
      expect(first, containsCompletion('firstName'));

      const updatedText = 'Integer count = 0;\ncou';
      await client.changeDocument(uri: documentUri, text: updatedText);

      final second = await client.completion(
        uri: documentUri,
        line: 1,
        character: 3,
      );
      expect(second, containsCompletion('count'));
    });
  });
}
