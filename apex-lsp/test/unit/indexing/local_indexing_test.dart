import 'dart:io';

import 'package:apex_lsp/completion/tree_sitter_bindings.dart';
import 'package:apex_lsp/indexing/local_indexer.dart';
import 'package:apex_lsp/indexing/revamped.dart';
import 'package:test/test.dart';

import '../../support/lsp_test_harness.dart';

void main() {
  setUpAll(setupTestLocator);

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

      expect(result, isA<IndexedEnum>());
      final enumDeclaration = result as IndexedEnum;
      expect(enumDeclaration.name, 'Foo');
    });

    test('index contains location of the declaration', () {
      final text = 'public Enum Foo { A, B, C }';

      final result = indexer.parseAndIndex(text);

      expect(result, isA<IndexedEnum>());
      final enumDeclaration = result as IndexedEnum;
      expect(enumDeclaration.location, isNotNull);
      expect(enumDeclaration.location, equals((0, text.length)));
    });

    test('parses member values', () {
      final text = 'public Enum Foo { A, B, C }';

      final result = indexer.parseAndIndex(text);

      expect(result, isA<IndexedEnum>());
      final enumDeclaration = result as IndexedEnum;
      expect(enumDeclaration.values, hasLength(3));
    });
  });
}
