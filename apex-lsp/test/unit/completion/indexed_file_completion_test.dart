import 'dart:io';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';
import 'package:apex_lsp/indexing/tree_sitter_indexer.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_reflection/apex_reflection.dart' as apex_reflection;
import 'package:test/test.dart';

import '../../support/lsp_test_harness.dart';

/// Tests for completion suggestions when using indexed files (types from other files).
/// This mirrors the scenarios in local_file_completion_test.dart but for indexed types.
void main() {
  setUpAll(setupTestLocator);

  final libPath = Platform.environment['TS_SFAPEX_LIB'];

  late TreeSitterIndexer indexer;

  group('indexed file completions', () {
    late TestIndexedClassProvider indexedClassProvider;

    setUp(() {
      final bindings = TreeSitterBindings.load(path: libPath);
      indexer = TreeSitterIndexer(bindings: bindings);
      indexedClassProvider = TestIndexedClassProvider();
    });

    /// Helper function to get completions with indexed types available
    Future<CompletionList> complete(
      String? text, {
      int line = 0,
      int character = 0,
    }) {
      return onCompletion(
        text: text,
        position: Position(line: line, character: character),
        localIndexer: indexer,
        indexedClassProvider: indexedClassProvider,
      );
    }

    group('top-level indexed type completions', () {
      test('suggests indexed classes', () async {
        indexedClassProvider.addClass(
          'AccountService',
          'public class AccountService { }',
        );

        final results = await complete(
          'public class TestClass { void m() { AccountSer } }',
          line: 0,
          character: 48,
        );

        expect(results.items.map((i) => i.label), contains('AccountService'));
      });

      test('suggests indexed interfaces', () async {
        indexedClassProvider.addClass(
          'Runnable',
          'public interface Runnable { void run(); }',
        );

        final results = await complete(
          'public class TestClass { void m() { Runna } }',
          line: 0,
          character: 45,
        );

        expect(results.items.map((i) => i.label), contains('Runnable'));
      });

      test('suggests indexed enums', () async {
        indexedClassProvider.addClass(
          'Status',
          'public enum Status { PENDING, APPROVED, REJECTED }',
        );

        final results = await complete(
          'public class TestClass { void m() { Stat } }',
          line: 0,
          character: 44,
        );

        expect(results.items.map((i) => i.label), contains('Status'));
      });

      test('indexed types in method body', () async {
        indexedClassProvider.addClass(
          'Helper',
          'public class Helper { public static void assist() {} }',
        );

        final results = await complete(
          'public class TestClass { void m() { Help } }',
          line: 0,
          character: 44,
        );

        expect(results.items.map((i) => i.label), contains('Helper'));
      });

      test('indexed types as variable types', () async {
        indexedClassProvider.addClass(
          'Logger',
          'public class Logger { public void log(String message) {} }',
        );

        final results = await complete(
          'public class TestClass { void m() { Logg } }',
          line: 0,
          character: 44,
        );

        expect(results.items.map((i) => i.label), contains('Logger'));
      });
    });

    group('static member access on indexed classes', () {
      test('suggests static fields from indexed class', () async {
        indexedClassProvider.addClass('MyClass', '''
          public class MyClass {
            public static String staticField;
            public String instanceField;
          }
          ''');

        final text = 'public class TestClass { void m() { MyClass.staticF } }';
        final cursorOffset =
            text.indexOf('MyClass.staticF') + 'MyClass.staticF'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('staticField'));
      });

      test('suggests static methods from indexed class', () async {
        indexedClassProvider.addClass('MyClass', '''
          public class MyClass {
            public static void staticMethod() {}
            public void instanceMethod() {}
          }
          ''');

        final text = 'public class TestClass { void m() { MyClass.staticM } }';
        final cursorOffset =
            text.indexOf('MyClass.staticM') + 'MyClass.staticM'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('staticMethod'));
      });

      test('suggests only static members for class name access', () async {
        indexedClassProvider.addClass('MyClass', '''
          public class MyClass {
            public static String staticField;
            public String instanceField;
            public static void staticMethod() {}
            public void instanceMethod() {}
          }
          ''');

        final text = 'public class TestClass { void m() { MyClass. } }';
        final cursorOffset = text.indexOf('MyClass.') + 'MyClass.'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('staticField'));
        expect(results.items.map((i) => i.label), contains('staticMethod'));
        expect(
          results.items.map((i) => i.label),
          isNot(contains('instanceField')),
        );
        expect(
          results.items.map((i) => i.label),
          isNot(contains('instanceMethod')),
        );
      });

      test('suggests enum values as static members', () async {
        indexedClassProvider.addClass('Status', '''
          public enum Status { PENDING, APPROVED, REJECTED }
          ''');

        final text = 'public class TestClass { void m() { Status.PEND } }';
        final cursorOffset = text.indexOf('Status.PEND') + 'Status.PEND'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('PENDING'));
      });
    });

    group('instance member access on indexed types', () {
      test('suggests instance fields from indexed class', () async {
        indexedClassProvider.addClass('MyClass', '''
          public class MyClass {
            public static String staticField;
            public String instanceField;
          }
          ''');

        final text =
            'public class TestClass { void m() { MyClass obj; obj.instanceF } }';
        final cursorOffset =
            text.indexOf('obj.instanceF') + 'obj.instanceF'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('instanceField'));
      });

      test('suggests instance methods from indexed class', () async {
        indexedClassProvider.addClass('MyClass', '''
          public class MyClass {
            public static void staticMethod() {}
            public void instanceMethod() {}
          }
          ''');

        final text =
            'public class TestClass { void m() { MyClass obj; obj.instanceM } }';
        final cursorOffset =
            text.indexOf('obj.instanceM') + 'obj.instanceM'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('instanceMethod'));
      });

      test('suggests only instance members for variable access', () async {
        indexedClassProvider.addClass('MyClass', '''
          public class MyClass {
            public static String staticField;
            public String instanceField;
            public static void staticMethod() {}
            public void instanceMethod() {}
          }
          ''');

        final text =
            'public class TestClass { void m() { MyClass obj; obj. } }';
        final cursorOffset = text.indexOf('obj.') + 'obj.'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('instanceField'));
        expect(results.items.map((i) => i.label), contains('instanceMethod'));
        expect(
          results.items.map((i) => i.label),
          isNot(contains('staticField')),
        );
        expect(
          results.items.map((i) => i.label),
          isNot(contains('staticMethod')),
        );
      });
    });
  });
}

/// Test implementation of IndexedClassProvider that uses the real apex_reflection library
/// to create indexed types from Apex source code.
class TestIndexedClassProvider implements IndexedClassProvider {
  // Maps className (preserving case) to IndexedType
  final Map<String, IndexedType> _types = {};

  /// Adds an indexed class from Apex source code using the real reflection library
  void addClass(String name, String apexSource) {
    final reflectionResult = apex_reflection.Reflection.reflect(apexSource);

    if (reflectionResult.error != null) {
      throw Exception(
        'Failed to reflect Apex source for $name: ${reflectionResult.error!.message}',
      );
    }

    final typeMirror = reflectionResult.typeMirror;
    if (typeMirror != null &&
        typeMirror.name.toLowerCase() == name.toLowerCase()) {
      final indexedType = _wrapTypeMirror(typeMirror);
      if (indexedType != null) {
        // Store with the actual type name to preserve case
        _types[typeMirror.name] = indexedType;
      }
    }
  }

  /// Wraps a TypeMirror in the appropriate IndexedType implementation
  IndexedType? _wrapTypeMirror(apex_reflection.TypeMirror typeMirror) {
    return switch (typeMirror) {
      apex_reflection.ClassMirror classMirror => ClassMirrorWrapper(
        classMirror: classMirror,
      ),
      apex_reflection.EnumMirror enumMirror => EnumMirrorWrapper(
        enumMirror: enumMirror,
      ),
      apex_reflection.InterfaceMirror interfaceMirror => InterfaceMirrorWrapper(
        interfaceMirror: interfaceMirror,
      ),
      _ => null,
    };
  }

  @override
  Iterable<String> get classNames => _types.keys;

  @override
  Future<IndexedType?> typeByNameAsync(String name) async {
    // Lookup is case-insensitive (Apex is case-insensitive)
    final entry = _types.entries
        .where((e) => e.key.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    return entry?.value;
  }
}
