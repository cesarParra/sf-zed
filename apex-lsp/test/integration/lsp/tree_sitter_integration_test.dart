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

  group('TreeSitterCompletionService integration', () {
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

    test('parses class names from source', () async {
      final text = '''
public class Foo {}
public class Bar {}
''';

      final results = await suggest(
        text: text,
        cursorOffset: text.indexOf('Fo') + 2,
      );

      final names = results.map((c) => c.name).toList();
      expect(names, contains('Foo'));
      expect(names, contains('Bar'));
    });

    test('parses member fields for instance', () async {
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

      final results = await suggest(text: text, cursorOffset: cursorOffset);

      final names = results.map((c) => c.name).toList();
      expect(names, containsAll(['myVar', 'other']));

      final members = results.whereType<MemberCandidate>();
      for (final member in members) {
        if (['myVar', 'other'].contains(member.name)) {
          expect(member.member.parentType.name, equals('Foo'));
        }
      }
    });

    test('parses instance variables', () async {
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

      final results = await suggest(text: text, cursorOffset: cursorOffset);

      final names = results.map((c) => c.name).toList();
      expect(names, contains('myVar'));
    });

    test('parses instance methods', () async {
      final text = '''
public class Foo {
  public String concat() {
    doSom
  }

  public void doSomething() {}
}
''';

      final cursorOffset = text.indexOf('doSom') + 'doSom'.length;

      final results = await suggest(text: text, cursorOffset: cursorOffset);

      final names = results.map((c) => c.name).toList();
      expect(names, contains('doSomething'));
    });

    test('filters members by prefix', () async {
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

      final results = await suggest(text: text, cursorOffset: cursorOffset);

      final names = results.map((c) => c.name).toList();
      // The service returns all members; filtering happens later in the pipeline
      expect(names, containsAll(['myVar', 'other']));

      final members = results.whereType<MemberCandidate>();
      for (final member in members) {
        if (['myVar', 'other'].contains(member.name)) {
          expect(member.member.parentType.name, equals('Foo'));
        }
      }
    });
  });

  group('Static vs Instance Integration', () {
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

    test('CollectionUtils static access', () async {
      final text = '''
public with sharing class CollectionUtils {
    public String myVar;

    public static List<Object> toObjectList(Iterable<Object> values) {
        List<Object> objects = new List<Object>();
        for (Object s : values) {
            objects.add(s);
        }

        return objects;
    }

    public static Integer sum(Int a, Int b) {
        return a + b;
    }
}

public class Consumer {
    public void test() {
        CollectionUtils.
    }
}
''';

      final cursorOffset =
          text.indexOf('CollectionUtils.') + 'CollectionUtils.'.length;
      final results = await suggest(text: text, cursorOffset: cursorOffset);
      final names = results.map((c) => c.name).toList();

      expect(names, containsAll(['toObjectList', 'sum']));
      expect(names, isNot(contains('myVar')));
    });

    test('CollectionUtils instance access', () async {
      final text = '''
public with sharing class CollectionUtils {
    public String myVar;

    public static List<Object> toObjectList(Iterable<Object> values) {
        List<Object> objects = new List<Object>();
        for (Object s : values) {
            objects.add(s);
        }

        return objects;
    }

    public static Integer sum(Int a, Int b) {
        return a + b;
    }
}

public class Consumer {
    public void test() {
        CollectionUtils utils = new CollectionUtils();
        utils.
    }
}
''';

      final cursorOffset = text.indexOf('utils.') + 'utils.'.length;
      final results = await suggest(text: text, cursorOffset: cursorOffset);
      final names = results.map((c) => c.name).toList();

      expect(names, contains('myVar'));
      expect(names, isNot(contains('toObjectList')));
      expect(names, isNot(contains('sum')));
    });
  });
}
