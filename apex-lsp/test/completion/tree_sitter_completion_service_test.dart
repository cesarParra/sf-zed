import 'package:test/test.dart';

import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';

void main() {
  group('TreeSitterCompletionService (testOnly)', () {
    TreeSitterCompletionService buildService({
      required ApexDocumentIndex index,
    }) {
      return TreeSitterCompletionService.testOnly(indexBuilder: (_) => index);
    }

    test('suggests class names by prefix', () {
      final index = ApexDocumentIndex(
        classes: [
          ApexClassInfo(
            name: 'Foo',
            startByte: 0,
            endByte: 10,
            fields: const ['myVar'],
            superclass: null,
          ),
          ApexClassInfo(
            name: 'Bar',
            startByte: 11,
            endByte: 20,
            fields: const [],
            superclass: null,
          ),
        ],
        variables: const [],
      );

      final service = buildService(index: index);
      final text = 'Fo';
      final result = service.suggest(text: text, cursorOffset: text.length);

      expect(result.kind, CompletionKind.className);
      expect(result.labels, ['Foo']);
    });

    test('suggests members after dot', () {
      final index = ApexDocumentIndex(
        classes: [
          ApexClassInfo(
            name: 'Foo',
            startByte: 0,
            endByte: 100,
            fields: const ['myVar', 'other'],
            superclass: null,
          ),
        ],
        variables: [
          ApexVariableInfo(
            name: 'myFooInstance',
            typeName: 'Foo',
            startByte: 0,
            endByte: 50,
            kind: 'local_variable_declaration',
          ),
        ],
      );

      final service = buildService(index: index);
      final text = 'myFooInstance.';
      final result = service.suggest(text: text, cursorOffset: text.length);

      expect(result.kind, CompletionKind.member);
      expect(result.labels, ['myVar', 'other']);
      expect(result.memberOfType, 'Foo');
    });

    test('filters members by prefix', () {
      final index = ApexDocumentIndex(
        classes: [
          ApexClassInfo(
            name: 'Foo',
            startByte: 0,
            endByte: 100,
            fields: const ['myVar', 'other'],
            superclass: null,
          ),
        ],
        variables: [
          ApexVariableInfo(
            name: 'myFooInstance',
            typeName: 'Foo',
            startByte: 0,
            endByte: 50,
            kind: 'local_variable_declaration',
          ),
        ],
      );

      final service = buildService(index: index);
      final text = 'myFooInstance.my';
      final result = service.suggest(text: text, cursorOffset: text.length);

      expect(result.kind, CompletionKind.member);
      expect(result.labels, ['myVar']);
      expect(result.memberOfType, 'Foo');
    });

    test('supports safe-navigation operator', () {
      final index = ApexDocumentIndex(
        classes: [
          ApexClassInfo(
            name: 'Foo',
            startByte: 0,
            endByte: 100,
            fields: const ['myVar'],
            superclass: null,
          ),
        ],
        variables: [
          ApexVariableInfo(
            name: 'myFooInstance',
            typeName: 'Foo',
            startByte: 0,
            endByte: 50,
            kind: 'local_variable_declaration',
          ),
        ],
      );

      final service = buildService(index: index);
      final text = 'myFooInstance?.';
      final result = service.suggest(text: text, cursorOffset: text.length);

      expect(result.kind, CompletionKind.member);
      expect(result.labels, ['myVar']);
      expect(result.memberOfType, 'Foo');
    });

    test('resolves class name as member receiver', () {
      final index = ApexDocumentIndex(
        classes: [
          ApexClassInfo(
            name: 'Foo',
            startByte: 0,
            endByte: 100,
            fields: const ['myVar'],
            superclass: null,
          ),
        ],
        variables: const [],
      );

      final service = buildService(index: index);
      final text = 'Foo.';
      final result = service.suggest(text: text, cursorOffset: text.length);

      expect(result.kind, CompletionKind.member);
      expect(result.labels, ['myVar']);
      expect(result.memberOfType, 'Foo');
    });
  });
}
