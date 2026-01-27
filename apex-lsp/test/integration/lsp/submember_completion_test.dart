import 'dart:io';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/completion_aggregator.dart';
import 'package:apex_lsp/completion/completion_context.dart';
import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/tree_sitter_indexer.dart';
import 'package:test/test.dart';

import '../../support/lsp_test_harness.dart';

void main() {
  setUpAll(setupTestLocator);

  final libPath = Platform.environment['TS_SFAPEX_LIB'];

  group('Submember Completion', () {
    late TreeSitterIndexer indexer;
    late TreeSitterBindings bindings;

    setUp(() {
      bindings = TreeSitterBindings.load(path: libPath);
      indexer = TreeSitterIndexer(bindings: bindings);
    });

    Future<List<CompletionCandidate>> suggest({
      required String text,
      required int cursorOffset,
    }) async {
      final index = indexer.parseAndIndex(text);
      final detector = ContextDetector(index: index);
      final context = detector.detect(text: text, cursorOffset: cursorOffset);
      final service = TreeSitterCompletionService(index: index);
      return service.suggest(context: context);
    }

    test(
      'suggests inner classes, interfaces, and enums as static members',
      () async {
        final text = '''
public class AnotherClass {
    private static String something;
    class MySubClass {}
    interface MySubInterface {}
    enum MySubEnum { VAL }
}

public class Consumer {
    public void test() {
        AnotherClass.
    }
}
''';

        final cursorOffset =
            text.indexOf('AnotherClass.') + 'AnotherClass.'.length;
        final results = await suggest(text: text, cursorOffset: cursorOffset);
        final names = results.map((c) => c.name).toList();

        // Currently expected to fail as these are not yet indexed as members
        expect(names, contains('MySubClass'));
        expect(names, contains('MySubInterface'));
        expect(names, contains('MySubEnum'));
        expect(names, contains('something'));
      },
    );

    test(
      'suggests inner types when in top-level context within the class',
      () async {
        final text = '''
public class CollectionUtils {
    public class MyInner {}

    public void sum() {
        MyI // cursor here
    }
}
''';

        final cursorOffset = text.indexOf('MyI') + 3;
        final results = await suggest(text: text, cursorOffset: cursorOffset);
        final names = results.map((c) => c.name).toList();

        expect(names, contains('MyInner'));
      },
    );

    test(
      'suggests inner interfaces and enums when in top-level context within the class',
      () async {
        final text = '''
public class CollectionUtils {
    public interface MyInnerInterface {}
    public enum MyInnerEnum { A }

    public void sum() {
        MyI // cursor here
    }
}
''';

        final cursorOffset = text.indexOf('MyI') + 3;
        final results = await suggest(text: text, cursorOffset: cursorOffset);
        final names = results.map((c) => c.name).toList();

        expect(names, contains('MyInnerInterface'));
        expect(names, contains('MyInnerEnum'));
      },
    );
  });
}
