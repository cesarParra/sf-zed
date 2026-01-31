import 'dart:convert';
import 'dart:io';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';
import 'package:apex_lsp/indexing/indexer.dart';
import 'package:apex_lsp/indexing/sfdx_workspace_locator.dart';
import 'package:apex_lsp/indexing/tree_sitter_indexer.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/utils/platform.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import '../../support/lsp_test_harness.dart';

final class FakeLspPlatform implements LspPlatform {
  FakeLspPlatform({this.isWindows = false, this.pathSeparator = '/'});

  @override
  final bool isWindows;

  @override
  final String pathSeparator;
}

/// Tests for completion suggestions when using indexed files (types from other files).
/// This mirrors the scenarios in local_file_completion_test.dart but for indexed types.
void main() {
  setUpAll(setupTestLocator);

  final libPath = Platform.environment['TS_SFAPEX_LIB'];

  late TreeSitterIndexer indexer;

  group('indexed file completions', () {
    late FileSystem fs;
    late FakeLspPlatform platform;
    late SfdxWorkspaceLocator locator;
    late ApexIndexer apexIndexer;
    late IndexedClassProvider indexedClassProvider;
    late Directory workspaceRoot;
    late Uri workspaceUri;
    late Directory classesDir;

    setUp(() async {
      // Setup memory file system
      fs = MemoryFileSystem();
      platform = FakeLspPlatform();
      locator = SfdxWorkspaceLocator(fileSystem: fs, platform: platform);
      apexIndexer = ApexIndexer(
        sfdxWorkspaceLocator: locator,
        fileSystem: fs,
        platform: platform,
      );

      workspaceRoot = fs.directory('/repo')..createSync();
      workspaceUri = Uri.directory(workspaceRoot.path);

      // Setup SFDX project structure
      final projectFile = workspaceRoot.childFile('sfdx-project.json');
      projectFile.writeAsStringSync(
        jsonEncode({
          'packageDirectories': [
            {'path': 'force-app', 'default': true},
          ],
        }),
      );

      classesDir = fs.directory('/repo/force-app/main/default/classes')
        ..createSync(recursive: true);

      // Initialize indexer
      final params = InitializedParams([
        WorkspaceFolder(workspaceUri.toString(), 'repo'),
      ]);
      await apexIndexer
          .index(params, token: ProgressToken.string('test'))
          .toList();

      // Create the real indexed class provider
      indexedClassProvider = ApexIndexerWorkspaceIndexAdapter(apexIndexer);

      // Setup tree-sitter indexer for local completions
      final bindings = TreeSitterBindings.load(path: libPath);
      indexer = TreeSitterIndexer(bindings: bindings);
    });

    /// Helper to add an indexed class by creating a .cls file and re-indexing
    Future<void> addIndexedClass(String name, String apexSource) async {
      final classFile = classesDir.childFile('$name.cls');
      classFile.writeAsStringSync(apexSource);

      // Re-run indexing to pick up the new file
      final params = InitializedParams([
        WorkspaceFolder(workspaceUri.toString(), 'repo'),
      ]);
      await apexIndexer
          .index(params, token: ProgressToken.string('test'))
          .toList();
    }

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
        await addIndexedClass(
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
        await addIndexedClass(
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
        await addIndexedClass(
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
        await addIndexedClass(
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
        await addIndexedClass(
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
        await addIndexedClass('MyClass', '''
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
        await addIndexedClass('MyClass', '''
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
        await addIndexedClass('MyClass', '''
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
        await addIndexedClass('Status', '''
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
        await addIndexedClass('MyClass', '''
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
        await addIndexedClass('MyClass', '''
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
        await addIndexedClass('MyClass', '''
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

    group('inheritance and interface implementation', () {
      test('parent class members via child instance', () async {
        await addIndexedClass('Parent', '''
          public class Parent {
            public void parentMethod() {}
            public String parentField;
          }
          ''');

        await addIndexedClass('Child', '''
          public class Child extends Parent {
            public void childMethod() {}
          }
          ''');

        final text =
            'public class TestClass { void m() { Child c; c.parent } }';
        final cursorOffset = text.indexOf('c.parent') + 'c.parent'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('parentMethod'));
        expect(results.items.map((i) => i.label), contains('parentField'));
      });

      test('grandparent members via grandchild', () async {
        await addIndexedClass('GrandParent', '''
          public class GrandParent {
            public void grandParentMethod() {}
          }
          ''');

        await addIndexedClass('Parent', '''
          public class Parent extends GrandParent {
            public void parentMethod() {}
          }
          ''');

        await addIndexedClass('Child', '''
          public class Child extends Parent {
            public void childMethod() {}
          }
          ''');

        final text =
            'public class TestClass { void m() { Child c; c.grandParent } }';
        final cursorOffset =
            text.indexOf('c.grandParent') + 'c.grandParent'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(
          results.items.map((i) => i.label),
          contains('grandParentMethod'),
        );
      });

      test('interface members via implementing class', () async {
        await addIndexedClass('Runnable', '''
          public interface Runnable {
            void run();
          }
          ''');

        await addIndexedClass('Task', '''
          public class Task implements Runnable {
            public void run() {}
            public void taskMethod() {}
          }
          ''');

        final text = 'public class TestClass { void m() { Task t; t.ru } }';
        final cursorOffset = text.indexOf('t.ru') + 't.ru'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('run'));
      });

      test('multiple interface implementation', () async {
        await addIndexedClass('Runnable', '''
          public interface Runnable {
            void run();
          }
          ''');

        await addIndexedClass('Closeable', '''
          public interface Closeable {
            void close();
          }
          ''');

        await addIndexedClass('Worker', '''
          public class Worker implements Runnable, Closeable {
            public void run() {}
            public void close() {}
            public void work() {}
          }
          ''');

        final text = 'public class TestClass { void m() { Worker w; w.clo } }';
        final cursorOffset = text.indexOf('w.clo') + 'w.clo'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('close'));
      });

      test('super keyword accesses indexed parent', () async {
        await addIndexedClass('Parent', '''
          public class Parent {
            public void parentMethod() {}
          }
          ''');

        final text =
            'public class Child extends Parent { void m() { super.parent } }';
        final cursorOffset =
            text.indexOf('super.parent') + 'super.parent'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('parentMethod'));
      });

      test('static members inherited via child class name', () async {
        await addIndexedClass('Parent', '''
          public class Parent {
            public static void staticParentMethod() {}
          }
          ''');

        await addIndexedClass('Child', '''
          public class Child extends Parent {
            public static void staticChildMethod() {}
          }
          ''');

        final text =
            'public class TestClass { void m() { Child.staticParent } }';
        final cursorOffset =
            text.indexOf('Child.staticParent') + 'Child.staticParent'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(
          results.items.map((i) => i.label),
          contains('staticParentMethod'),
        );
      });

      test('overridden methods show in completion', () async {
        await addIndexedClass('Parent', '''
          public class Parent {
            public void doWork() {}
          }
          ''');

        await addIndexedClass('Child', '''
          public class Child extends Parent {
            public override void doWork() {}
          }
          ''');

        final text = 'public class TestClass { void m() { Child c; c.doW } }';
        final cursorOffset = text.indexOf('c.doW') + 'c.doW'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('doWork'));
      });
    });

    group('nested types in indexed files', () {
      test('suggests nested class from indexed outer class', () async {
        await addIndexedClass('OuterClass', '''
          public class OuterClass {
            public class InnerClass {
              public void innerMethod() {}
            }
          }
          ''');

        final text = 'public class TestClass { void m() { OuterClass.Inner } }';
        final cursorOffset =
            text.indexOf('OuterClass.Inner') + 'OuterClass.Inner'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('InnerClass'));
      });

      test('static members of nested class', () async {
        await addIndexedClass('Outer', '''
          public class Outer {
            public class Inner {
              public static void staticInnerMethod() {}
              public void instanceInnerMethod() {}
            }
          }
          ''');

        final text =
            'public class TestClass { void m() { Outer.Inner.staticInner } }';
        final cursorOffset =
            text.indexOf('Outer.Inner.staticInner') +
            'Outer.Inner.staticInner'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(
          results.items.map((i) => i.label),
          contains('staticInnerMethod'),
        );
      });

      test('instance members of nested class variable', () async {
        await addIndexedClass('Outer', '''
          public class Outer {
            public class Inner {
              public void innerMethod() {}
            }
          }
          ''');

        final text =
            'public class TestClass { void m() { Outer.Inner obj; obj.inner } }';
        final cursorOffset = text.indexOf('obj.inner') + 'obj.inner'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('innerMethod'));
      });

      test('nested enum values', () async {
        await addIndexedClass('Outer', '''
          public class Outer {
            public enum Status { PENDING, APPROVED, REJECTED }
          }
          ''');

        final text =
            'public class TestClass { void m() { Outer.Status.PEND } }';
        final cursorOffset =
            text.indexOf('Outer.Status.PEND') + 'Outer.Status.PEND'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('PENDING'));
      });

      test('nested interface methods', () async {
        await addIndexedClass('Outer', '''
          public class Outer {
            public interface Runnable {
              void run();
            }
          }
          ''');

        final text =
            'public class TestClass { void m() { Outer.Runnable obj; obj.ru } }';
        final cursorOffset = text.indexOf('obj.ru') + 'obj.ru'.length;

        final results = await complete(text, line: 0, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('run'));
      });
    });

    group('mixed local and indexed completions', () {
      test('both local and indexed classes suggested', () async {
        await addIndexedClass('IndexedHelper', '''
          public class IndexedHelper {
            public void helpFromIndex() {}
          }
          ''');

        final text = '''
          public class LocalHelper {
            public void helpFromLocal() {}
          }
          public class TestClass {
            void m() {
              Helper
            }
          }
          ''';
        final cursorOffset = text.indexOf('Helper') + 'Helper'.length;

        final results = await complete(text, line: 6, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('IndexedHelper'));
        expect(results.items.map((i) => i.label), contains('LocalHelper'));
      });

      // TODO
      // test('indexed parent, local child', () async {
      //   await addIndexedClass('IndexedParent', '''
      //     public class IndexedParent {
      //       public void parentMethod() {}
      //     }
      //     ''');

      //   final text = '''
      //     public class LocalChild extends IndexedParent {
      //       public void childMethod() {}
      //     }
      //     public class TestClass {
      //       void m() {
      //         LocalChild obj;
      //         obj.parent
      //       }
      //     }
      //     ''';
      //   final cursorOffset = text.indexOf('obj.parent') + 'obj.parent'.length;

      //   final results = await complete(text, line: 9, character: cursorOffset);

      //   expect(results.items.map((i) => i.label), contains('parentMethod'));
      // });

      test('local variable of indexed type', () async {
        await addIndexedClass('IndexedService', '''
          public class IndexedService {
            public void serviceMethod() {}
          }
          ''');

        final text = '''
          public class TestClass {
            void m() {
              IndexedService svc;
              svc.service
            }
          }
          ''';
        final cursorOffset = text.indexOf('svc.service') + 'svc.service'.length;

        final results = await complete(text, line: 3, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('serviceMethod'));
      });

      test('method returns indexed type', () async {
        await addIndexedClass('IndexedResult', '''
          public class IndexedResult {
            public String resultValue;
          }
          ''');

        final text = '''
          public class TestClass {
            IndexedResult getResult() {
              return null;
            }
            void m() {
              IndexedResult res = getResult();
              res.result
            }
          }
          ''';
        final cursorOffset = text.indexOf('res.result') + 'res.result'.length;

        final results = await complete(text, line: 6, character: cursorOffset);

        expect(results.items.map((i) => i.label), contains('resultValue'));
      });
    });
  });
}
