import 'dart:io';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/indexing/revamped.dart';
import 'package:test/test.dart';

void main() {
  final libPath = Platform.environment['TS_SFAPEX_LIB'];

  final bindings = TreeSitterBindings.load(path: libPath);
  late LocalIndexer indexer;

  setUp(() {
    indexer = LocalIndexer(bindings: bindings);
  });

  group('indexes enums', () {
    test('indexes top level declaration', () {
      final text = '''
public Enum Foo { A, B, C };
      ''';

      final result = indexer.parseAndIndex(text);

      expect(result.first, isA<IndexedEnum>());
      final enumDeclaration = result.first as IndexedEnum;
      expect(enumDeclaration.name, 'Foo');
    });

    test('index contains location of the declaration', () {
      final text = 'public Enum Foo { A, B, C }';

      final result = indexer.parseAndIndex(text);

      expect(result.first, isA<IndexedEnum>());
      final enumDeclaration = result.first as IndexedEnum;
      expect(enumDeclaration.location, isNotNull);
      expect(enumDeclaration.location, equals((0, text.length)));
    });

    test('parses member values', () {
      final text = 'public Enum Foo { A, B, C }';

      final result = indexer.parseAndIndex(text);

      expect(result.first, isA<IndexedEnum>());
      final enumDeclaration = result.first as IndexedEnum;
      expect(enumDeclaration.values, hasLength(3));
    });
  });

  group('indexes variables', () {
    test('indexes a simple variable declaration', () {
      final text = "String myVar = 'hello';";

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedVariable>());
      final variable = result.first as IndexedVariable;
      expect(variable.name, 'myVar');
      expect(variable.typeName, 'String');
    });

    test('indexes multiple declarators', () {
      final text = 'Integer a, b;';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(2));
      final variables = result.whereType<IndexedVariable>().toList();
      expect(variables, hasLength(2));
      expect(variables[0].name, 'a');
      expect(variables[0].typeName, 'Integer');
      expect(variables[1].name, 'b');
      expect(variables[1].typeName, 'Integer');
    });

    test('indexes declaration without initializer', () {
      final text = 'String items;';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      final variable = result.first as IndexedVariable;
      expect(variable.name, 'items');
      expect(variable.typeName, 'String');
    });

    test('indexes final variable', () {
      final text = "final String name = 'test';";

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      final variable = result.first as IndexedVariable;
      expect(variable.name, 'name');
      expect(variable.typeName, 'String');
    });

    test('tracks location', () {
      final text = "String myVar = 'hello';";

      final result = indexer.parseAndIndex(text);

      final variable = result.first as IndexedVariable;
      expect(variable.location, isNotNull);
    });
  });

  group('indexes interfaces', () {
    test('indexes top level interface declaration', () {
      final text = '''
public interface Foo {
  String doSomething();
  void saySomething();
}
      ''';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      expect(result.first, isA<IndexedInterface>());
      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.name, 'Foo');
    });

    test('parses method declarations', () {
      final text = '''
public interface Foo {
  String doSomething();
  void saySomething();
}
      ''';

      final result = indexer.parseAndIndex(text);

      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.methods, hasLength(2));
      expect(interfaceDeclaration.methods[0].name, 'doSomething');
      expect(interfaceDeclaration.methods[1].name, 'saySomething');
    });

    test('methods are marked as non-static', () {
      final text = '''
public interface Foo {
  String doSomething();
}
      ''';

      final result = indexer.parseAndIndex(text);

      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.methods.first.isStatic, isFalse);
    });

    test('index contains location of the declaration', () {
      final text = 'public interface Foo { String doSomething(); }';

      final result = indexer.parseAndIndex(text);

      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.location, isNotNull);
      expect(interfaceDeclaration.location, equals((0, text.length)));
    });

    test('indexes interface with no methods', () {
      final text = 'public interface Empty { }';

      final result = indexer.parseAndIndex(text);

      expect(result, hasLength(1));
      final interfaceDeclaration = result.first as IndexedInterface;
      expect(interfaceDeclaration.name, 'Empty');
      expect(interfaceDeclaration.methods, isEmpty);
    });
  });
}
