import 'package:test/test.dart';

import 'package:apex_lsp/completion/completion_aggregator.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_service.dart';
import 'package:apex_lsp/completion/tree_sitter_completion_types.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';

class LocalIndexedClass implements IndexedClass {
  LocalIndexedClass({
    required this.name,
    required this.fields,
    required this.properties,
    required this.methods,
    this.superclass,
  });

  final String name;
  final List<String> fields;
  final List<String> properties;
  final List<String> methods;
  final String? superclass;

  @override
  bool hasMemberPrefix(String prefix) {
    final lower = prefix.toLowerCase();
    return fields.any((m) => m.toLowerCase().startsWith(lower)) ||
        properties.any((m) => m.toLowerCase().startsWith(lower)) ||
        methods.any((m) => m.toLowerCase().startsWith(lower));
  }

  @override
  List<String> get memberNames {
    final all = <String>{...fields, ...properties, ...methods};
    final result = all.toList()..sort();
    return result;
  }

  @override
  List<String> membersMatching(String prefix) {
    if (prefix.isEmpty) return memberNames;
    final lower = prefix.toLowerCase();
    final matches = <String>{
      ...fields.where((m) => m.toLowerCase().startsWith(lower)),
      ...properties.where((m) => m.toLowerCase().startsWith(lower)),
      ...methods.where((m) => m.toLowerCase().startsWith(lower)),
    };
    final result = matches.toList()..sort();
    return result;
  }
}

void main() {
  group('CompletionAggregator', () {
    test('prefers local member completions when available', () async {
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

      final service = TreeSitterCompletionService.testOnly(
        indexBuilder: (_) => documentIndex,
      );

      final workspace = _FakeWorkspaceIndex(
        classesByName: {
          'Foo': LocalIndexedClass(
            name: 'Foo',
            fields: const ['workspaceField'],
            properties: const ['workspaceProp'],
            methods: const ['workspaceMethod'],
            superclass: null,
          ),
        },
      );

      final aggregator = CompletionAggregator(
        documentService: service,
        workspaceIndex: workspace,
      );

      final text = 'myFooInstance.';
      final result = await aggregator.suggest(
        text: text,
        cursorOffset: text.length,
      );

      expect(result.kind, CompletionKind.member);
      expect(result.labels, ['localField', 'localMethod', 'localProp']);
      expect(result.memberOfType, 'Foo');
    });

    test(
      'falls back to workspace members when document lacks class info',
      () async {
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

        final service = TreeSitterCompletionService.testOnly(
          indexBuilder: (_) => documentIndex,
        );

        final workspace = _FakeWorkspaceIndex(
          classesByName: {
            'Foo': LocalIndexedClass(
              name: 'Foo',
              fields: const ['memberField'],
              properties: const [],
              methods: const ['methodOne'],
              superclass: null,
            ),
          },
        );

        final aggregator = CompletionAggregator(
          documentService: service,
          workspaceIndex: workspace,
        );

        final text = 'myFooInstance.m';
        final result = await aggregator.suggest(
          text: text,
          cursorOffset: text.length,
        );

        expect(result.kind, CompletionKind.member);
        expect(result.labels, ['memberField', 'methodOne']);
        expect(result.memberOfType, 'Foo');
      },
    );

    test('falls back to class names when member type is unresolved', () async {
      final documentIndex = ApexDocumentIndex(
        classes: const [],
        variables: const [],
      );

      final service = TreeSitterCompletionService.testOnly(
        indexBuilder: (_) => documentIndex,
      );

      final workspace = _FakeWorkspaceIndex(
        classesByName: {
          'Foo': LocalIndexedClass(
            name: 'Foo',
            fields: const [],
            properties: const [],
            methods: const [],
            superclass: null,
          ),
          'Bar': LocalIndexedClass(
            name: 'Bar',
            fields: const [],
            properties: const [],
            methods: const [],
            superclass: null,
          ),
        },
      );

      final aggregator = CompletionAggregator(
        documentService: service,
        workspaceIndex: workspace,
      );

      final text = 'unknown.';
      final result = await aggregator.suggest(
        text: text,
        cursorOffset: text.length,
      );

      expect(result.kind, CompletionKind.className);
      expect(result.labels, ['Bar', 'Foo']);
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

        final service = TreeSitterCompletionService.testOnly(
          indexBuilder: (_) => documentIndex,
        );

        final workspace = _FakeWorkspaceIndex(
          classesByName: {
            'Bar': LocalIndexedClass(
              name: 'Bar',
              fields: const [],
              properties: const [],
              methods: const [],
              superclass: null,
            ),
            'Bazooka': LocalIndexedClass(
              name: 'Bazooka',
              fields: const [],
              properties: const [],
              methods: const [],
              superclass: null,
            ),
          },
        );

        final aggregator = CompletionAggregator(
          documentService: service,
          workspaceIndex: workspace,
        );

        final text = 'Ba';
        final result = await aggregator.suggest(
          text: text,
          cursorOffset: text.length,
        );

        expect(result.kind, CompletionKind.className);
        expect(result.labels, ['Bar', 'Baz', 'Bazooka']);
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
