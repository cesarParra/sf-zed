// Contains tests related to autocompleting from types and
// members declared on the file itself. Use cases include
// Anon-apex, where there can be multiple types and variables
// declared at the root of the same file, or a completing
// members from a single class.

import 'dart:io';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';
import 'package:apex_lsp/indexing/tree_sitter_indexer.dart';
import 'package:apex_lsp/message.dart';
import 'package:test/test.dart';

import '../../support/lsp_test_harness.dart';

// Use cases:
// all top levels from inner block
//
// Members - static
// static class members
// enum members
// inner types (class, enum, interface)
//
// Members - instance
// instance members (methods, variables, properties)
//
// Blocks
// referencing things from root
// referencing from class body
// referencing from static block
// referencing from constructor
// referencing from instance method
// referencing from inner block (for loop)
// referencing from static method
//
// From indexed files
// All of the above

/// IndexedClassProvider with no indexed files.
class FakeIndexedClassProvider implements IndexedClassProvider {
  FakeIndexedClassProvider({this.types = const {}});

  final Map<String, IndexedType> types;

  @override
  Iterable<String> get classNames => types.keys;

  @override
  Future<IndexedType?> typeByNameAsync(String name) async {
    return null;
  }
}

void main() {
  setUpAll(setupTestLocator);

  final libPath = Platform.environment['TS_SFAPEX_LIB'];

  group('root scope', () {
    late TreeSitterIndexer indexer;

    setUp(() {
      final bindings = TreeSitterBindings.load(path: libPath);
      indexer = TreeSitterIndexer(bindings: bindings);
    });

    Future<CompletionList> complete(
      String? text, {
      int line = 0,
      int character = 0,
    }) {
      return onCompletion(
        text: text,
        position: Position(line: line, character: character),
        localIndexer: indexer,
        indexedClassProvider: FakeIndexedClassProvider(),
      );
    }

    group('at the root level', () {
      test('suggests local variables', () async {
        final text = '''
String myVar;
m
      ''';

        final results = await complete(text, line: 1, character: 1);

        expect(results.items, isNotEmpty);
        expect(results.items.length, 1);
        expect(results.items.first.label, 'myVar');
      });

      test('suggests local classes', () async {
        final text = '''
class MyClass() {}
M
      ''';

        final results = await complete(text, line: 1, character: 1);

        expect(results.items, isNotEmpty);
        expect(results.items.length, 1);
        expect(results.items.first.label, 'MyClass');
      });

      test('suggests local interfaces', () async {
        final text = '''
  interface MyInterface() {}
M
      ''';

        final results = await complete(text, line: 1, character: 1);

        expect(results.items, isNotEmpty);
        expect(results.items.length, 1);
        expect(results.items.first.label, 'MyInterface');
      });

      test('suggests local enums', () async {
        final text = '''
  interface MyEnum() {A, B, C}
M
      ''';

        final results = await complete(text, line: 1, character: 1);

        expect(results.items, isNotEmpty);
        expect(results.items.length, 1);
        expect(results.items.first.label, 'MyEnum');
      });

      test('suggests local methods', () async {
        final text = '''
void doSomething() {}
d
      ''';

        final results = await complete(text, line: 1, character: 1);

        expect(results.items, isNotEmpty);
        expect(results.items.length, 1);
        expect(results.items.first.label, 'doSomething');
      });
    });
  });

  group('class scope', () {
    // TODO: can see things declared in root
    // TODO: can see any other member declared at the class level
  });

  // TODO: static block
  // TODO: constructor
  // TODO: instance method
  // TODO: static method
  // TODO: from inner/nested class
  // TODO: all of the above but for members (e.g. foo.bar)
}

//     test('parses class names from source', () async {
//       final text = '''
// public class Foo {}
// public class Bar {}
// ''';

//       final results = await suggest(
//         text: text,
//         cursorOffset: text.indexOf('Fo') + 2,
//       );

//       final names = results.map((c) => c.name).toList();
//       expect(names, contains('Foo'));
//       expect(names, contains('Bar'));
//     });

//     test('parses member fields for instance', () async {
//       final text = '''
// public class Foo {
//   public String myVar;
//   public Integer other;
// }

// public class Baz {
//   public void demo() {
//     Foo myFooInstance = new Foo();
//     myFooInstance.
//   }
// }
// ''';

//       final cursorOffset =
//           text.indexOf('myFooInstance.') + 'myFooInstance.'.length;

//       final results = await suggest(text: text, cursorOffset: cursorOffset);

//       final names = results.map((c) => c.name).toList();
//       expect(names, containsAll(['myVar', 'other']));

//       final members = results.whereType<MemberCandidate>();
//       for (final member in members) {
//         if (['myVar', 'other'].contains(member.name)) {
//           expect(member.member.parentType.name, equals('Foo'));
//         }
//       }
//     });

//     test('parses instance variables', () async {
//       final text = '''
// public class Foo {
//   public String myVar;
//   public Integer other;

//   public String concat() {
//     return myV
//   }
// }
// ''';

//       final cursorOffset = text.indexOf('return myV') + 'return myV.'.length;

//       final results = await suggest(text: text, cursorOffset: cursorOffset);

//       final names = results.map((c) => c.name).toList();
//       expect(names, contains('myVar'));
//     });

//     test('parses instance methods', () async {
//       final text = '''
// public class Foo {
//   public String concat() {
//     doSom
//   }

//   public void doSomething() {}
// }
// ''';

//       final cursorOffset = text.indexOf('doSom') + 'doSom'.length;

//       final results = await suggest(text: text, cursorOffset: cursorOffset);

//       final names = results.map((c) => c.name).toList();
//       expect(names, contains('doSomething'));
//     });

//     test('filters members by prefix', () async {
//       final text = '''
// public class Foo {
//   public String myVar;
//   public Integer other;
// }

// public class Baz {
//   public void demo() {
//     Foo myFooInstance = new Foo();
//     myFooInstance.my
//   }
// }
// ''';

//       final cursorOffset =
//           text.indexOf('myFooInstance.my') + 'myFooInstance.my'.length;

//       final results = await suggest(text: text, cursorOffset: cursorOffset);

//       final names = results.map((c) => c.name).toList();
//       // The service returns all members; filtering happens later in the pipeline
//       expect(names, containsAll(['myVar', 'other']));

//       final members = results.whereType<MemberCandidate>();
//       for (final member in members) {
//         if (['myVar', 'other'].contains(member.name)) {
//           expect(member.member.parentType.name, equals('Foo'));
//         }
//       }
//     });

//     test('parses enum names from source', () async {
//       final text = '''
// public enum MyEnum { A, B }
// ''';

//       final results = await suggest(
//         text: text,
//         cursorOffset: text.indexOf('MyEn') + 4,
//       );

//       final names = results.map((c) => c.name).toList();
//       expect(names, contains('MyEnum'));
//     });

//     test('parses mixed enum and class names', () async {
//       final text = '''
// public class MyClass {}
// public enum MyEnum { A, B }
// ''';

//       final results = await suggest(
//         text: text,
//         cursorOffset: text.indexOf('MyCl') + 2,
//       );

//       final names = results.map((c) => c.name).toList();
//       expect(names, contains('MyClass'));
//       expect(names, contains('MyEnum'));
//     });

//     test('parses enum values as static members', () async {
//       final text = '''
// public enum MyEnum { VAL1, VAL2 }

// public class Consumer {
//   public void test() {
//     MyEnum.
//   }
// }
// ''';

//       final cursorOffset = text.indexOf('MyEnum.') + 'MyEnum.'.length;

//       final results = await suggest(text: text, cursorOffset: cursorOffset);

//       final names = results.map((c) => c.name).toList();
//       expect(names, containsAll(['VAL1', 'VAL2']));
//     });

//     test('parses interface names from source', () async {
//       final text = '''
// public interface MyInterface {}
// ''';

//       final results = await suggest(
//         text: text,
//         cursorOffset: text.indexOf('MyInt') + 5,
//       );

//       final names = results.map((c) => c.name).toList();
//       expect(names, contains('MyInterface'));
//     });
//   });

//   group('Static vs Instance Integration', () {
//     late TreeSitterIndexer indexer;
//     late TreeSitterBindings bindings;

//     setUp(() {
//       bindings = TreeSitterBindings.load(path: libPath);
//       indexer = TreeSitterIndexer(bindings: bindings);
//     });

//     Future<List<CompletionCandidate>> suggest({
//       required String text,
//       required int cursorOffset,
//     }) async {
//       final index = indexer.parseAndIndex(text);
//       final detector = ContextDetector(index: index);
//       final context = detector.detect(text: text, cursorOffset: cursorOffset);
//       final service = TreeSitterCompletionService(index: index);
//       return service.suggest(context: context);
//     }

//     test('CollectionUtils static access', () async {
//       final text = '''
// public with sharing class CollectionUtils {
//     public String myVar;

//     public static List<Object> toObjectList(Iterable<Object> values) {
//         List<Object> objects = new List<Object>();
//         for (Object s : values) {
//             objects.add(s);
//         }

//         return objects;
//     }

//     public static Integer sum(Int a, Int b) {
//         return a + b;
//     }
// }

// public class Consumer {
//     public void test() {
//         CollectionUtils.
//     }
// }
// ''';

//       final cursorOffset =
//           text.indexOf('CollectionUtils.') + 'CollectionUtils.'.length;
//       final results = await suggest(text: text, cursorOffset: cursorOffset);
//       final names = results.map((c) => c.name).toList();

//       expect(names, containsAll(['toObjectList', 'sum']));
//       expect(names, isNot(contains('myVar')));
//     });

//     test('CollectionUtils instance access', () async {
//       final text = '''
// public with sharing class CollectionUtils {
//     public String myVar;

//     public static List<Object> toObjectList(Iterable<Object> values) {
//         List<Object> objects = new List<Object>();
//         for (Object s : values) {
//             objects.add(s);
//         }

//         return objects;
//     }

//     public static Integer sum(Int a, Int b) {
//         return a + b;
//     }
// }

// public class Consumer {
//     public void test() {
//         CollectionUtils utils = new CollectionUtils();
//         utils.
//     }
// }
// ''';

//       final cursorOffset = text.indexOf('utils.') + 'utils.'.length;
//       final results = await suggest(text: text, cursorOffset: cursorOffset);
//       final names = results.map((c) => c.name).toList();

//       expect(names, contains('myVar'));
//       expect(names, isNot(contains('toObjectList')));
//       expect(names, isNot(contains('sum')));
//     });
//   });
