import 'dart:io';

import 'package:test/test.dart';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';

void main() {
  final libPath = Platform.environment['TS_SFAPEX_LIB'];
  final shouldRun = libPath != null && libPath.isNotEmpty;

  group('TreeSitterCompletionService integration', () {
    if (!shouldRun) {
      test('skipped (set TS_SFAPEX_LIB to run)', () {
        expect(true, isTrue);
      });
      return;
    }

    late TreeSitterCompletionService service;

    setUp(() {
      final bindings = TreeSitterBindings.load(path: libPath);
      service = TreeSitterCompletionService(bindings: bindings);
    });

    tearDown(() {
      service.dispose();
    });

    test('parses class names from source', () {
      final text = '''
public class Foo {}
public class Bar {}
''';

      final result = service.suggest(
        text: text,
        cursorOffset: text.indexOf('Fo') + 2,
      );

      expect(result.kind, CompletionKind.className);
      expect(result.labels, contains('Foo'));
      expect(result.labels, isNot(contains('Bar')));
    });

    test('parses member fields for instance', () {
      final text = '''
public class Foo {
  public String myVar;
  public Integer other;
}

public class Baz {
  public void demo() {
    Foo myFooInstance = new Foo();
    myFooInstance.
  }
}
''';

      final cursorOffset =
          text.indexOf('myFooInstance.') + 'myFooInstance.'.length;

      final result = service.suggest(text: text, cursorOffset: cursorOffset);

      expect(result.kind, CompletionKind.member);
      expect(result.memberOfType, 'Foo');
      expect(result.labels, containsAll(['myVar', 'other']));
    });

    test('filters members by prefix', () {
      final text = '''
public class Foo {
  public String myVar;
  public Integer other;
}

public class Baz {
  public void demo() {
    Foo myFooInstance = new Foo();
    myFooInstance.my
  }
}
''';

      final cursorOffset =
          text.indexOf('myFooInstance.my') + 'myFooInstance.my'.length;

      final result = service.suggest(text: text, cursorOffset: cursorOffset);

      expect(result.kind, CompletionKind.member);
      expect(result.memberOfType, 'Foo');
      expect(result.labels, ['myVar']);
    });
  });
}
