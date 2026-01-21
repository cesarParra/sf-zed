import 'dart:io';

import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';
import 'package:test/test.dart';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';

import '../../support/lsp_test_harness.dart';

void main() {
  setUpAll(setupTestLocator);

  final libPath = Platform.environment['TS_SFAPEX_LIB'];

  group('TreeSitterCompletionService integration', () {
    late TreeSitterCompletionService service;

    setUp(() {
      final bindings = TreeSitterBindings.load(path: libPath);
      service = TreeSitterCompletionService.withBindings(bindings: bindings);
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

      expect(result, isA<ClassNameOrLocalCandidates>());
      expect(result.labels, contains('Foo'));
      expect(result.labels, contains('Bar'));
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

      expect(result, isA<MemberCandidates>());
      expect(result.labels, containsAll(['myVar', 'other']));
      expect(
        result,
        predicate<MemberCandidates>((result) {
          return result.memberOfType == 'Foo';
        }),
      );
    });

    test('parses instance variables', () {
      final text = '''
public class Foo {
  public String myVar;
  public Integer other;

  public String concat() {
    return myV
  }
}
''';

      final cursorOffset = text.indexOf('return myV') + 'return myV.'.length;

      final result = service.suggest(text: text, cursorOffset: cursorOffset);

      expect(result, isA<ClassNameOrLocalCandidates>());
      expect(result.labels, containsAll(['myVar']));
    });

    test('parses instance methods', () {
      final text = '''
public class Foo {
  public String concat() {
    doSom
  }

  public void doSomething() {}
}
''';

      final cursorOffset = text.indexOf('doSom') + 'doSom'.length;

      final result = service.suggest(text: text, cursorOffset: cursorOffset);

      expect(result, isA<ClassNameOrLocalCandidates>());
      expect(result.labels, containsAll(['doSomething']));
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

      expect(result, isA<MemberCandidates>());
      expect(result.labels, containsAll(['myVar', 'other']));
      expect(
        result,
        predicate<MemberCandidates>((result) {
          return result.memberOfType == 'Foo';
        }),
      );
    });
  });
}
