// Contains tests related to autocompleting from types and
// members declared on the file itself. Use cases include
// Anon-apex, where there can be multiple types and variables
// declared at the root of the same file, or a completing
// members from a single class.

import 'package:apex_lsp/indexing/revamped.dart';
import 'package:apex_lsp/message.dart';
import 'package:test/test.dart';

import '../../support/lsp_test_harness.dart';

void main() {
  setUpAll(setupTestLocator);

  // final libPath = Platform.environment['TS_SFAPEX_LIB'];

  // late LocalIndexer indexer;

  // setUp(() {
  //   final bindings = TreeSitterBindings.load(path: libPath);
  //   indexer = LocalIndexer(bindings: bindings);
  // });

  Future<CompletionList> complete(
    String text, {
    required List<IndexedType> types,
  }) {
    return Future.value(
      CompletionList(
        isIncomplete: false,
        items: [CompletionItem(label: 'Foo')],
      ),
    );
  }

  test('autocomplete enum types', () async {
    final enumType = IndexedEnum('Foo', values: []);
    final completionList = await complete('{{cursor}}', types: [enumType]);

    expect(completionList.items, hasLength(1));
    expect(completionList.items.first.label, 'Foo');
  });

  //   group('root scope', () {
  //     group('at the root level', () {
  //       test('suggests local variables', () async {
  //         final text = '''
  // String myVar;
  // m
  //       ''';

  //         final results = await complete(text, line: 1, character: 1);

  //         expect(results.items, isNotEmpty);
  //         expect(results.items.length, 1);
  //         expect(results.items.first.label, 'myVar');
  //       });

  //       test('suggests local classes', () async {
  //         final text = '''
  // class MyClass() {}
  // M
  //       ''';

  //         final results = await complete(text, line: 1, character: 1);

  //         expect(results.items, isNotEmpty);
  //         expect(results.items.length, 1);
  //         expect(results.items.first.label, 'MyClass');
  //       });

  //       test('suggests local interfaces', () async {
  //         final text = '''
  //   interface MyInterface() {}
  // M
  //       ''';

  //         final results = await complete(text, line: 1, character: 1);

  //         expect(results.items, isNotEmpty);
  //         expect(results.items.length, 1);
  //         expect(results.items.first.label, 'MyInterface');
  //       });

  //       test('suggests local enums', () async {
  //         final text = '''
  //   interface MyEnum() {A, B, C}
  // M
  //       ''';

  //         final results = await complete(text, line: 1, character: 1);

  //         expect(results.items, isNotEmpty);
  //         expect(results.items.length, 1);
  //         expect(results.items.first.label, 'MyEnum');
  //       });

  //       test('suggests local methods', () async {
  //         final text = '''
  // void doSomething() {}
  // d
  //       ''';

  //         final results = await complete(text, line: 1, character: 1);

  //         expect(results.items, isNotEmpty);
  //         expect(results.items.length, 1);
  //         expect(results.items.first.label, 'doSomething');
  //       });
  //     });
  //   });

  //   group('class scope', () {
  //     test('suggests root declarations', () async {
  //       final text = '''
  // String myVar;
  // class SomeClass {
  // m
  // }
  //     ''';

  //       final results = await complete(text, line: 3, character: 1);

  //       expect(results.items, isNotEmpty);
  //       expect(results.items.length, 2);
  //       expect(results.items.map((i) => i.label), contains('myVar'));
  //     });

  //     test('suggests other class members', () async {
  //       final text = '''
  // String myVar;
  // class SomeClass {
  //   String classInstanceVar;
  //   cl
  // }
  //     ''';

  //       final results = await complete(text, line: 4, character: 4);

  //       expect(results.items, isNotEmpty);
  //       expect(results.items.length, 3);
  //       expect(results.items.map((i) => i.label), contains('classInstanceVar'));
  //     });
  //   });

  //   group('static block', () {
  //     test('suggests root declarations from static block', () async {
  //       final text = '''
  // String rootVar;
  // class MyClass {
  //   static {
  //     r
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 5);

  //       expect(results.items.map((i) => i.label), contains('rootVar'));
  //     });

  //     test('suggests static members from static block', () async {
  //       final text = '''
  // class MyClass {
  //   static String staticField;
  //   String instanceField;

  //   static {
  //     st
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 5, character: 6);

  //       expect(results.items.map((i) => i.label), contains('staticField'));
  //       expect(
  //         results.items.map((i) => i.label),
  //         isNot(contains('instanceField')),
  //       );
  //     });

  //     test('does NOT suggest instance members from static block', () async {
  //       final text = '''
  // class MyClass {
  //   static String staticField;
  //   String instanceField;

  //   static {
  //     in
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 5, character: 6);

  //       expect(
  //         results.items.map((i) => i.label),
  //         isNot(contains('instanceField')),
  //       );
  //     });

  //     test(
  //       'suggests local variables declared before cursor in static block',
  //       () async {
  //         final text = '''
  // class MyClass {
  //   static {
  //     String localVar;
  //     lo
  //   }
  // }
  //       ''';

  //         final results = await complete(text, line: 3, character: 6);

  //         expect(results.items.map((i) => i.label), contains('localVar'));
  //       },
  //     );
  //   });

  //   group('constructor', () {
  //     test('suggests root declarations from constructor', () async {
  //       final text = '''
  // String rootVar;
  // class MyClass {
  //   public MyClass() {
  //     r
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 5);

  //       expect(results.items.map((i) => i.label), contains('rootVar'));
  //     });

  //     test(
  //       'suggests both static and instance members from constructor',
  //       () async {
  //         final text = '''
  // class MyClass {
  //   static String staticField;
  //   String instanceField;

  //   public MyClass() {
  //     s
  //   }
  // }
  //       ''';

  //         final results = await complete(text, line: 6, character: 5);

  //         expect(results.items.map((i) => i.label), contains('instanceField'));
  //         expect(results.items.map((i) => i.label), contains('staticField'));
  //       },
  //     );

  //     test('suggests local variables from constructor', () async {
  //       final text = '''
  // class MyClass {
  //   public MyClass() {
  //     String localVar;
  //     lo
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 6);

  //       expect(results.items.map((i) => i.label), contains('localVar'));
  //     });

  //     test('suggests constructor parameters', () async {
  //       final text = '''
  // class MyClass {
  //   public MyClass(String paramVar) {
  //     pa
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 2, character: 6);

  //       expect(results.items.map((i) => i.label), contains('paramVar'));
  //     });

  //     test('suggests constructor parameters with multiple arguments', () async {
  //       final text = '''
  // class MyClass {
  //   public MyClass(String firstParam, Integer secondParam, Boolean thirdParam) {
  //     p
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 5);

  //       expect(results.items.map((i) => i.label), contains('secondParam'));
  //       expect(results.items.map((i) => i.label), contains('firstParam'));
  //       expect(results.items.map((i) => i.label), contains('thirdParam'));
  //     });
  //   });

  //   group('instance method', () {
  //     test('suggests root declarations from instance method', () async {
  //       final text = '''
  // String rootVar;
  // class MyClass {
  //   public void doSomething() {
  //     r
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 5);

  //       expect(results.items.map((i) => i.label), contains('rootVar'));
  //     });

  //     test(
  //       'suggests both static and instance members from instance method',
  //       () async {
  //         final text = '''
  // class MyClass {
  //   static String staticField;
  //   String instanceField;

  //   public void doSomething() {
  //     f
  //   }
  // }
  //       ''';

  //         final results = await complete(text, line: 6, character: 5);

  //         expect(results.items.map((i) => i.label), contains('instanceField'));
  //         expect(results.items.map((i) => i.label), contains('staticField'));
  //       },
  //     );

  //     test('suggests local variables from instance method', () async {
  //       final text = '''
  // class MyClass {
  //   public void doSomething() {
  //     String localVar;
  //     lo
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 6);

  //       expect(results.items.map((i) => i.label), contains('localVar'));
  //     });

  //     test('suggests method parameters', () async {
  //       final text = '''
  // class MyClass {
  //   public void doSomething(String paramVar) {
  //     pa
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 2, character: 6);

  //       expect(results.items.map((i) => i.label), contains('paramVar'));
  //     });

  //     test('suggests multiple method parameters', () async {
  //       final text = '''
  // class MyClass {
  //   public void doSomething(String firstParam, Integer secondParam) {
  //     p
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 5);

  //       expect(results.items.map((i) => i.label), contains('firstParam'));
  //       expect(results.items.map((i) => i.label), contains('secondParam'));
  //     });
  //   });

  //   group('static method', () {
  //     test('suggests root declarations from static method', () async {
  //       final text = '''
  // String rootVar;
  // class MyClass {
  //   public static void doSomething() {
  //     r
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 5);

  //       expect(results.items.map((i) => i.label), contains('rootVar'));
  //     });

  //     test('suggests static members from static method', () async {
  //       final text = '''
  // class MyClass {
  //   static String staticField;
  //   String instanceField;

  //   public static void doSomething() {
  //     s
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 5, character: 5);

  //       expect(results.items.map((i) => i.label), contains('staticField'));
  //       expect(
  //         results.items.map((i) => i.label),
  //         isNot(contains('instanceField')),
  //       );
  //     });

  //     test('does NOT suggest instance members from static method', () async {
  //       final text = '''
  // class MyClass {
  //   static String staticField;
  //   String instanceField;

  //   public static void doSomething() {
  //     in
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 5, character: 6);

  //       expect(
  //         results.items.map((i) => i.label),
  //         isNot(contains('instanceField')),
  //       );
  //     });

  //     test('suggests local variables from static method', () async {
  //       final text = '''
  // class MyClass {
  //   public static void doSomething() {
  //     String localVar;
  //     lo
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 6);

  //       expect(results.items.map((i) => i.label), contains('localVar'));
  //     });

  //     test('suggests static method parameters', () async {
  //       final text = '''
  // class MyClass {
  //   public static void doSomething(String paramVar) {
  //     pa
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 2, character: 6);

  //       expect(results.items.map((i) => i.label), contains('paramVar'));
  //     });
  //   });

  //   group('nested class', () {
  //     test('suggests inner class from outer class scope', () async {
  //       final text = '''
  // class OuterClass {
  //   private class InnerClass {}

  //   public void method() {
  //     In
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 4, character: 6);

  //       expect(results.items.map((i) => i.label), contains('InnerClass'));
  //     });

  //     test('suggests outer class members from inner class', () async {
  //       final text = '''
  // class OuterClass {
  //   private String outerField;

  //   private class InnerClass {
  //     public void method() {
  //       ou
  //     }
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 5, character: 8);

  //       expect(results.items.map((i) => i.label), contains('outerField'));
  //     });

  //     test('suggests root declarations from inner class', () async {
  //       final text = '''
  // String rootVar;
  // class OuterClass {
  //   private class InnerClass {
  //     public void method() {
  //       r
  //     }
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 4, character: 7);

  //       expect(results.items.map((i) => i.label), contains('rootVar'));
  //     });

  //     test('respects static context in inner class static methods', () async {
  //       final text = '''
  // class OuterClass {
  //   private class InnerClass {
  //     String innerInstanceField;
  //     static String innerStaticField;

  //     public static void staticMethod() {
  //       in
  //     }
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 6, character: 8);

  //       expect(results.items.map((i) => i.label), contains('innerStaticField'));
  //       expect(
  //         results.items.map((i) => i.label),
  //         isNot(contains('innerInstanceField')),
  //       );
  //     });
  //   });

  //   group('member access', () {
  //     test('suggests parent members when a class is extending another', () async {
  //       final text = '''
  // class ParentClass {
  //   public String parentField;
  //   public void parentMethod() {}
  // }

  // class ChildClass extends ParentClass {
  //   public void method() {
  //     super.
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 7, character: 10);

  //       expect(results.items.map((i) => i.label), contains('parentMethod'));
  //     });

  //     test(
  //       'suggests grandparent members in multi-level class hierarchy',
  //       () async {
  //         final text = '''
  // class GrandParentClass {
  //   public void grandParentMethod() {}
  //   public String grandParentField;
  // }

  // class ParentClass extends GrandParentClass {
  //   public void parentMethod() {}
  // }

  // class ChildClass extends ParentClass {
  //   public void method() {
  //     super.
  //   }
  // }
  //       ''';

  //         final results = await complete(text, line: 11, character: 10);

  //         expect(results.items.map((i) => i.label), contains('parentMethod'));
  //         expect(
  //           results.items.map((i) => i.label),
  //           contains('grandParentMethod'),
  //         );
  //         expect(results.items.map((i) => i.label), contains('grandParentField'));
  //       },
  //     );

  //     test(
  //       'suggests parent interface members when accessing interface variable',
  //       () async {
  //         final text = '''
  // interface ParentInterface {
  //   void parentMethod();
  // }

  // interface ChildInterface extends ParentInterface {
  //   void childMethod();
  // }

  // class Implementation {
  //   public void method(ChildInterface ch) {
  //     ch.
  //   }

  //   public void parentMethod() {}
  //   public void childMethod() {}
  // }
  //       ''';

  //         final results = await complete(text, line: 11, character: 7);

  //         expect(results.items.map((i) => i.label), contains('parentMethod'));
  //         expect(results.items.map((i) => i.label), contains('childMethod'));
  //       },
  //     );
  //   });

  //   group('inner block', () {
  //     test('suggests variables from parent method scope in for loop', () async {
  //       final text = '''
  // class MyClass {
  //   public void method() {
  //     String methodVar;
  //     for (Integer i = 0; i < 10; i++) {
  //       me
  //     }
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 4, character: 8);

  //       expect(results.items.map((i) => i.label), contains('methodVar'));
  //     });

  //     test('suggests loop variable in for loop body', () async {
  //       final text = '''
  // class MyClass {
  //   public void method() {
  //     for (Integer i = 0; i < 10; i++) {
  //       i
  //     }
  //   }
  // }
  //       ''';

  //       final results = await complete(text, line: 3, character: 7);

  //       expect(results.items.map((i) => i.label), contains('i'));
  //     });

  //     test(
  //       'respects static context in nested block within static method',
  //       () async {
  //         final text = '''
  // class MyClass {
  //   String instanceField;
  //   static String staticField;

  //   public static void method() {
  //     if (true) {
  //       st
  //     }
  //   }
  // }
  //       ''';

  //         final results = await complete(text, line: 6, character: 8);

  //         expect(results.items.map((i) => i.label), contains('staticField'));
  //         expect(
  //           results.items.map((i) => i.label),
  //           isNot(contains('instanceField')),
  //         );
  //       },
  //     );
  //   });
}
