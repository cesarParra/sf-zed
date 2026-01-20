import 'package:apex_lsp/completion/completion_context.dart';
import 'package:test/test.dart';

import 'package:apex_lsp/completion/completion_aggregator.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';

import '../support/lsp_test_harness.dart';

final class Field {
  final String name;
  final bool isStatic;

  const Field({required this.name, required this.isStatic});
}

final class Method {
  final String name;
  final bool isStatic;

  const Method({required this.name, required this.isStatic});
}

extension on String {
  Field staticField() => Field(name: this, isStatic: true);
  Field instanceField() => Field(name: this, isStatic: false);
  Method staticMethod() => Method(name: this, isStatic: true);
  Method instanceMethod() => Method(name: this, isStatic: false);
}

class InMemoryIndexedClass implements IndexedClass {
  InMemoryIndexedClass({
    required this.name,
    required this.fields,
    required this.methods,
    this.superclass,
  });

  final String name;
  final List<Field> fields;
  final List<Method> methods;
  final String? superclass;

  @override
  bool hasMemberPrefix(String prefix) {
    final lower = prefix.toLowerCase();
    return fields.any((m) => m.name.toLowerCase().startsWith(lower)) ||
        methods.any((m) => m.name.toLowerCase().startsWith(lower));
  }

  @override
  List<String> memberNamesByType(MemberType type) {
    return switch (type) {
      .static => [
        ...fields.where((f) => f.isStatic).map((f) => f.name),
        ...methods.where((m) => m.isStatic).map((m) => m.name),
      ],
      .instance => [
        ...fields.where((f) => !f.isStatic).map((f) => f.name),
        ...methods.where((m) => !m.isStatic).map((m) => m.name),
      ],
    };
  }

  @override
  List<String> get memberNames {
    final all = <String>{
      ...fields.map((f) => f.name),
      ...methods.map((m) => m.name),
    };
    final result = all.toList()..sort();
    return result;
  }
}

void main() {
  setUpAll(setupTestLocator);

  group('when autocompleting object members', () {
    group('and local candidates are available', () {
      test('the local document is used', () async {
        final documentIndex = ApexDocumentIndex(
          classes: [
            ApexClassInfo(
              name: 'Foo',
              startByte: 0,
              endByte: 100,
              fields: const ['localField'],
              properties: const ['localProp'],
              methods: const ['localMethod'],
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

        final service = TreeSitterCompletionService.withIndexBuilder(
          builder: (_) => documentIndex,
        );

        final workspace = _FakeWorkspaceIndex(
          classesByName: {
            'Foo': InMemoryIndexedClass(
              name: 'Foo',
              fields: [
                'workspaceField'.instanceField(),
                'workspaceProp'.instanceField(),
              ],
              methods: ['workspaceMethod'.instanceMethod()],
              superclass: null,
            ),
          },
        );

        final aggregator = CompletionAggregator(
          documentService: service,
          indexedClassesRepository: workspace,
        );

        final text = 'myFooInstance.';
        final result = await aggregator.suggest(
          text: text,
          cursorOffset: text.length,
        );

        expect(result.kind, CompletionKind.member);
        expect(
          result.labels,
          containsAll(['localField', 'localMethod', 'localProp']),
        );
        expect(result.memberOfType, 'Foo');
      });
    });

    group('and local candidates are not available', () {
      test('the index is used to complete instance members', () async {
        final documentIndex = ApexDocumentIndex(
          classes: const [],
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

        final service = TreeSitterCompletionService.withIndexBuilder(
          builder: (_) => documentIndex,
        );

        final workspace = _FakeWorkspaceIndex(
          classesByName: {
            'Foo': InMemoryIndexedClass(
              name: 'Foo',
              fields: ['memberField'.instanceField()],
              methods: ['methodOne'.instanceMethod()],
              superclass: null,
            ),
          },
        );

        final aggregator = CompletionAggregator(
          documentService: service,
          indexedClassesRepository: workspace,
        );

        final text = 'myFooInstance.m';
        final result = await aggregator.suggest(
          text: text,
          cursorOffset: text.length,
        );

        expect(result.kind, CompletionKind.member);
        expect(result.labels, ['memberField', 'methodOne']);
        expect(result.memberOfType, 'Foo');
      });

      test('the index is used to complete static members', () async {
        final documentIndex = ApexDocumentIndex(
          classes: const [],
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

        final service = TreeSitterCompletionService.withIndexBuilder(
          builder: (_) => documentIndex,
        );

        final workspace = _FakeWorkspaceIndex(
          classesByName: {
            'Foo': InMemoryIndexedClass(
              name: 'Foo',
              fields: ['memberField'.staticField()],
              methods: ['methodOne'.staticMethod()],
              superclass: null,
            ),
          },
        );

        final aggregator = CompletionAggregator(
          documentService: service,
          indexedClassesRepository: workspace,
        );

        final text = 'Foo.m';
        final result = await aggregator.suggest(
          text: text,
          cursorOffset: text.length,
        );

        expect(result.kind, CompletionKind.member);
        expect(result.labels, ['memberField', 'methodOne']);
        expect(result.memberOfType, 'Foo');
      });
    });

    // TODO: This is actually not good behavior, if we don't know
    // what the user is talking about, we do not want to autocomplete
    test('falls back to class names when member type is unresolved', () async {
      final documentIndex = ApexDocumentIndex(
        classes: const [],
        variables: const [],
      );

      final service = TreeSitterCompletionService.withIndexBuilder(
        builder: (_) => documentIndex,
      );

      final workspace = _FakeWorkspaceIndex(
        classesByName: {
          'Foo': InMemoryIndexedClass(
            name: 'Foo',
            fields: const [],
            methods: const [],
            superclass: null,
          ),
          'Bar': InMemoryIndexedClass(
            name: 'Bar',
            fields: const [],
            methods: const [],
            superclass: null,
          ),
        },
      );

      final aggregator = CompletionAggregator(
        documentService: service,
        indexedClassesRepository: workspace,
      );

      final text = 'unknown.';
      final result = await aggregator.suggest(
        text: text,
        cursorOffset: text.length,
      );

      expect(result.kind, CompletionKind.className);
      expect(result.labels, containsAll(['Bar', 'Foo']));
    });

    test(
      'merges class name candidates across document and workspace',
      () async {
        final documentIndex = ApexDocumentIndex(
          classes: [
            ApexClassInfo(
              name: 'Baz',
              startByte: 0,
              endByte: 10,
              fields: const [],
              properties: const [],
              methods: const [],
              superclass: null,
            ),
            ApexClassInfo(
              name: 'Foo',
              startByte: 11,
              endByte: 20,
              fields: const [],
              properties: const [],
              methods: const [],
              superclass: null,
            ),
          ],
          variables: const [],
        );

        final service = TreeSitterCompletionService.withIndexBuilder(
          builder: (_) => documentIndex,
        );

        final workspace = _FakeWorkspaceIndex(
          classesByName: {
            'Bar': InMemoryIndexedClass(
              name: 'Bar',
              fields: const [],
              methods: const [],
              superclass: null,
            ),
            'Bazooka': InMemoryIndexedClass(
              name: 'Bazooka',
              fields: const [],
              methods: const [],
              superclass: null,
            ),
          },
        );

        final aggregator = CompletionAggregator(
          documentService: service,
          indexedClassesRepository: workspace,
        );

        final text = 'Ba';
        final result = await aggregator.suggest(
          text: text,
          cursorOffset: text.length,
        );

        expect(result.kind, CompletionKind.className);
        expect(result.labels, containsAll(['Bar', 'Baz', 'Bazooka', 'Foo']));
      },
    );
  });
}

final class _FakeWorkspaceIndex implements IndexedClassProvider {
  _FakeWorkspaceIndex({required Map<String, IndexedClass> classesByName})
    : _classesByName = classesByName;

  final Map<String, IndexedClass> _classesByName;

  @override
  Iterable<String> get classNames => _classesByName.keys;

  @override
  Future<IndexedClass?> classByNameAsync(String name) async {
    return _classesByName[name];
  }
}

// TODO: Tests to add
// When the . gets typed -> show all static members
// When the user starts typing after the dot for a class -> show static members that match what the user is typing
