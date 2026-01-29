// Use cases:
// All local
// top level class from root
// top level enum from root
// top level interface from root
// top level variable froom root
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

import 'dart:async';

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/indexing/indexed_class.dart';
import 'package:apex_lsp/indexing/scope.dart';
import 'package:apex_lsp/indexing/tree_sitter_completion_types.dart';
import 'package:apex_lsp/indexing/tree_sitter_indexer.dart';
import 'package:apex_lsp/message.dart';
import 'package:test/test.dart';

import '../support/lsp_test_harness.dart';

class FakeTreeSitterIndexer implements TreeSitterIndexer {
  FakeTreeSitterIndexer(this.index);

  final ApexDocumentIndex index;

  @override
  ApexDocumentIndex parseAndIndex(String text) {
    return index;
  }
}

class FakeIndexedClassProvider implements IndexedClassProvider {
  FakeIndexedClassProvider({this.types = const {}});

  final Map<String, IndexedType> types;

  @override
  Iterable<String> get classNames => types.keys;

  @override
  Future<IndexedType?> typeByNameAsync(String name) async {
    final parts = name.split('.');
    if (parts.isEmpty) return null;

    // Look up the top-level type
    IndexedType? current = types[parts[0]];
    if (current == null) return null;

    // Traverse nested types for qualified names
    for (var i = 1; i < parts.length; i++) {
      current = current?.nestedTypeByName(parts[i]);
      if (current == null) return null;
    }

    return current;
  }
}

class InMemoryIndexedType implements IndexedType {
  InMemoryIndexedType({
    required this.name,
    this.staticMembers = const [],
    this.instanceMembers = const [],
    this.nestedTypes = const {},
  });

  final String name;
  final List<String> staticMembers;
  final List<String> instanceMembers;
  final Map<String, IndexedType> nestedTypes;

  @override
  List<String> get memberNames =>
      {...staticMembers, ...instanceMembers}.toList()..sort();

  @override
  List<String> memberNamesByType(MemberType type) {
    return switch (type) {
      MemberType.static => [...staticMembers, ...nestedTypeNames],
      MemberType.instance => instanceMembers,
    };
  }

  @override
  bool hasMemberPrefix(String prefix) {
    return memberNames.any(
      (m) => m.toLowerCase().startsWith(prefix.toLowerCase()),
    );
  }

  @override
  List<String> get nestedTypeNames => nestedTypes.keys.toList();

  @override
  IndexedType? nestedTypeByName(String name) {
    final lowerName = name.toLowerCase();
    for (final entry in nestedTypes.entries) {
      if (entry.key.toLowerCase() == lowerName) {
        return entry.value;
      }
    }
    return null;
  }
}

void main() {}

// void main() {
//   setUpAll(setupTestLocator);

//   late FakeTreeSitterIndexer localIndexer;
//   late FakeIndexedClassProvider indexedClassProvider;

//   const uri = 'file:///path/to/file.cls';

//   setUp(() {
//     // Default empty indexer and provider
//     localIndexer = FakeTreeSitterIndexer(
//       ApexDocumentIndex(
//         rootScope: Scope(type: ScopeType.file, startByte: 0, endByte: 0),
//       ),
//     );
//     indexedClassProvider = FakeIndexedClassProvider();
//   });

//   Future<CompletionList> complete(
//     String? text, {
//     int line = 0,
//     int character = 0,
//   }) {
//     return onCompletion(
//       text: text,
//       params: CompletionParams(
//         textDocument: TextDocumentIdentifierWithUri(uri: uri),
//         position: Position(line: line, character: character),
//       ),
//       localIndexer: localIndexer,
//       indexedClassProvider: indexedClassProvider,
//     );
//   }

//   test('returns empty list if document is not found (text is null)', () async {
//     final result = await complete(null);

//     expect(result.isIncomplete, isFalse);
//     expect(result.items, isEmpty);
//   });

//   test('returns empty list if no context (empty text)', () async {
//     final result = await complete('');
//     expect(result.items, isEmpty);
//   });

//   group('Top-Level Completion', () {
//     test('suggests class names from global index', () async {
//       indexedClassProvider = FakeIndexedClassProvider(
//         types: {'GlobalClass': InMemoryIndexedType(name: 'GlobalClass')},
//       );

//       final text = 'Glo';
//       final result = await complete(text, line: 0, character: 3);

//       expect(result.items.map((i) => i.label), contains('GlobalClass'));
//     });

//     test('suggests local variables from local indexer', () async {
//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(
//           rootScope: Scope(
//             type: ScopeType.file,
//             startByte: 0,
//             endByte: 100,
//             definitions: [
//               ApexVariableInfo(
//                 name: 'myVar',
//                 typeName: 'String',
//                 startByte: 0,
//                 endByte: 0,
//                 kind: 'local_variable_declaration',
//               ),
//             ],
//           ),
//         ),
//       );

//       final text = 'my';
//       final result = await complete(text, line: 0, character: 2);

//       expect(result.items.map((i) => i.label), contains('myVar'));
//     });

//     test('suggests local enums from local indexer', () async {
//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(
//           rootScope: Scope(
//             type: ScopeType.file,
//             startByte: 0,
//             endByte: 100,
//             definitions: [
//               ApexEnumInfo(
//                 name: 'MyEnum',
//                 startByte: 0,
//                 endByte: 0,
//                 members: [],
//               ),
//             ],
//           ),
//         ),
//       );

//       final text = 'My';
//       final result = await complete(text, line: 0, character: 2);

//       expect(result.items.map((i) => i.label), contains('MyEnum'));
//     });

//     test('suggests local interfaces from local indexer', () async {
//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(
//           rootScope: Scope(
//             type: ScopeType.file,
//             startByte: 0,
//             endByte: 100,
//             definitions: [
//               ApexInterfaceInfo(
//                 name: 'MyInterface',
//                 startByte: 0,
//                 endByte: 0,
//                 members: [],
//               ),
//             ],
//           ),
//         ),
//       );

//       final text = 'My';
//       final result = await complete(text, line: 0, character: 2);

//       expect(result.items.map((i) => i.label), contains('MyInterface'));
//     });

//     test('filters results based on prefix', () async {
//       indexedClassProvider = FakeIndexedClassProvider(
//         types: {
//           'List': InMemoryIndexedType(name: 'List'),
//           'Map': InMemoryIndexedType(name: 'Map'),
//         },
//       );

//       final text = 'Li';
//       final result = await complete(text, line: 0, character: 2);

//       final labels = result.items.map((i) => i.label);
//       expect(labels, contains('List'));
//       expect(labels, isNot(contains('Map')));
//     });
//   });

//   group('Member Completion (Instance)', () {
//     test('suggests instance members when variable type matches', () async {
//       // Setup global type 'Account' with members
//       indexedClassProvider = FakeIndexedClassProvider(
//         types: {
//           'Account': InMemoryIndexedType(
//             name: 'Account',
//             instanceMembers: ['Name', 'Id'],
//             staticMembers: ['sObjectType'],
//           ),
//         },
//       );

//       final text = 'Account acc; acc.';
//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(
//           rootScope: Scope(
//             type: ScopeType.file,
//             startByte: 0,
//             endByte: 100,
//             definitions: [
//               ApexVariableInfo(
//                 name: 'acc',
//                 typeName: 'Account',
//                 startByte: 8, // "acc" starts around here
//                 endByte: 11,
//                 kind: 'local_variable_declaration',
//               ),
//             ],
//           ),
//         ),
//       );

//       final result = await complete(text, line: 0, character: text.length);

//       final labels = result.items.map((i) => i.label);
//       expect(labels, containsAll(['Name', 'Id']));
//       expect(labels, isNot(contains('sObjectType')));
//     });
//   });

//   group('Member Completion (Static)', () {
//     test(
//       'suggests static members when object name matches class name',
//       () async {
//         indexedClassProvider = FakeIndexedClassProvider(
//           types: {
//             'System': InMemoryIndexedType(
//               name: 'System',
//               staticMembers: ['debug', 'now'],
//               instanceMembers: ['clone'],
//             ),
//           },
//         );

//         final text = 'System.';

//         final result = await complete(text, line: 0, character: text.length);

//         final labels = result.items.map((i) => i.label);
//         expect(labels, containsAll(['debug', 'now']));
//         expect(labels, isNot(contains('clone')));
//       },
//     );

//     test('suggests enum values when object name matches enum name', () async {
//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(
//           rootScope: Scope(
//             type: ScopeType.file,
//             startByte: 0,
//             endByte: 100,
//             definitions: [
//               ApexEnumInfo(
//                 name: 'MyEnum',
//                 startByte: 0,
//                 endByte: 0,
//                 members: [
//                   ApexMemberInfo(name: 'VAL1', isStatic: true),
//                   ApexMemberInfo(name: 'VAL2', isStatic: true),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       );

//       final text = 'MyEnum.';

//       final result = await complete(text, line: 0, character: text.length);

//       final labels = result.items.map((i) => i.label);
//       expect(labels, containsAll(['VAL1', 'VAL2']));
//     });
//   });

//   group('Local Member Completion', () {
//     test('suggests instance members from local class definition', () async {
//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(
//           rootScope: Scope(
//             type: ScopeType.file,
//             startByte: 0,
//             endByte: 100,
//             definitions: [
//               ApexClassInfo(
//                 name: 'MyClass',
//                 startByte: 0,
//                 endByte: 0,
//                 members: [
//                   ApexMemberInfo(name: 'instanceField', isStatic: false),
//                   ApexMemberInfo(name: 'staticField', isStatic: true),
//                   ApexMemberInfo(name: 'instanceMethod', isStatic: false),
//                   ApexMemberInfo(name: 'staticMethod', isStatic: true),
//                 ],
//                 superclass: null,
//               ),
//               ApexVariableInfo(
//                 name: 'inst',
//                 typeName: 'MyClass',
//                 startByte: 0,
//                 endByte: 0,
//                 kind: 'local_variable_declaration',
//               ),
//             ],
//           ),
//         ),
//       );

//       final text = 'MyClass inst; inst.';
//       final result = await complete(text, line: 0, character: text.length);

//       final labels = result.items.map((i) => i.label);
//       expect(labels, containsAll(['instanceField', 'instanceMethod']));
//       expect(labels, isNot(contains('staticField')));
//       expect(labels, isNot(contains('staticMethod')));
//     });

//     test('suggests static members from local class definition', () async {
//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(
//           rootScope: Scope(
//             type: ScopeType.file,
//             startByte: 0,
//             endByte: 100,
//             definitions: [
//               ApexClassInfo(
//                 name: 'MyClass',
//                 startByte: 0,
//                 endByte: 0,
//                 members: [
//                   ApexMemberInfo(name: 'instanceField', isStatic: false),
//                   ApexMemberInfo(name: 'staticField', isStatic: true),
//                   ApexMemberInfo(name: 'instanceMethod', isStatic: false),
//                   ApexMemberInfo(name: 'staticMethod', isStatic: true),
//                 ],
//                 superclass: null,
//               ),
//             ],
//           ),
//         ),
//       );

//       final text = 'MyClass.';
//       final result = await complete(text, line: 0, character: text.length);

//       final labels = result.items.map((i) => i.label);
//       expect(labels, containsAll(['staticField', 'staticMethod']));
//       expect(labels, isNot(contains('instanceField')));
//       expect(labels, isNot(contains('instanceMethod')));
//     });
//   });

//   group('Scoping Rules', () {
//     test('instance members are not visible in static methods', () async {
//       final methodScope = Scope(
//         type: ScopeType.methodBody,
//         startByte: 50,
//         endByte: 100,
//         isStatic: true,
//       );

//       final typeScope = Scope(
//         type: ScopeType.typeDeclaration,
//         startByte: 0,
//         endByte: 200,
//         definitions: [
//           ApexMemberInfo(name: 'instanceField', isStatic: false),
//           ApexMemberInfo(name: 'staticField', isStatic: true),
//         ],
//         children: [methodScope],
//       );
//       methodScope.parent = typeScope;

//       final rootScope = Scope(
//         type: ScopeType.file,
//         startByte: 0,
//         endByte: 200,
//         definitions: [
//           ApexClassInfo(
//             name: 'MyClass',
//             startByte: 0,
//             endByte: 200,
//             members: [
//               ApexMemberInfo(name: 'instanceField', isStatic: false),
//               ApexMemberInfo(name: 'staticField', isStatic: true),
//             ],
//           ),
//         ],
//         children: [typeScope],
//       );
//       typeScope.parent = rootScope;

//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(rootScope: rootScope),
//       );

//       final result = await complete(' ' * 200, line: 0, character: 75);
//       final labels = result.items.map((i) => i.label);

//       expect(labels, contains('staticField'));
//       expect(labels, isNot(contains('instanceField')));
//     });

//     test('instance members are visible in instance methods', () async {
//       final methodScope = Scope(
//         type: ScopeType.methodBody,
//         startByte: 50,
//         endByte: 100,
//         isStatic: false,
//       );

//       final typeScope = Scope(
//         type: ScopeType.typeDeclaration,
//         startByte: 0,
//         endByte: 200,
//         definitions: [
//           ApexMemberInfo(name: 'instanceField', isStatic: false),
//           ApexMemberInfo(name: 'staticField', isStatic: true),
//         ],
//         children: [methodScope],
//       );
//       methodScope.parent = typeScope;

//       final rootScope = Scope(
//         type: ScopeType.file,
//         startByte: 0,
//         endByte: 200,
//         definitions: [
//           ApexClassInfo(
//             name: 'MyClass',
//             startByte: 0,
//             endByte: 200,
//             members: [
//               ApexMemberInfo(name: 'instanceField', isStatic: false),
//               ApexMemberInfo(name: 'staticField', isStatic: true),
//             ],
//           ),
//         ],
//         children: [typeScope],
//       );
//       typeScope.parent = rootScope;

//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(rootScope: rootScope),
//       );

//       final result = await complete(' ' * 200, line: 0, character: 75);
//       final labels = result.items.map((i) => i.label);

//       expect(labels, contains('staticField'));
//       expect(labels, contains('instanceField'));
//     });

//     test('local variables declared after cursor are not visible', () async {
//       final methodScope = Scope(
//         type: ScopeType.methodBody,
//         startByte: 0,
//         endByte: 100,
//         definitions: [
//           ApexVariableInfo(
//             name: 'visibleVar',
//             typeName: 'String',
//             startByte: 10,
//             endByte: 20,
//             kind: 'local_variable_declaration',
//           ),
//           ApexVariableInfo(
//             name: 'futureVar',
//             typeName: 'String',
//             startByte: 80,
//             endByte: 90,
//             kind: 'local_variable_declaration',
//           ),
//         ],
//       );

//       final rootScope = Scope(
//         type: ScopeType.file,
//         startByte: 0,
//         endByte: 100,
//         children: [methodScope],
//       );
//       methodScope.parent = rootScope;

//       localIndexer = FakeTreeSitterIndexer(
//         ApexDocumentIndex(rootScope: rootScope),
//       );

//       final result = await complete(' ' * 100, line: 0, character: 50);
//       final labels = result.items.map((i) => i.label);

//       expect(labels, contains('visibleVar'));
//       expect(labels, isNot(contains('futureVar')));
//     });
//   });

//   group('Pagination & Limits', () {
//     test('caps results at 25 and sets incomplete flag', () async {
//       // Create 30 classes
//       final types = <String, IndexedType>{};
//       for (var i = 0; i < 30; i++) {
//         final name = 'Class$i';
//         types[name] = InMemoryIndexedType(name: name);
//       }

//       indexedClassProvider = FakeIndexedClassProvider(types: types);

//       final text = 'Cla';
//       final result = await complete(text, line: 0, character: 3);

//       expect(result.items.length, 25);
//       expect(result.isIncomplete, isTrue);
//     });

//     test('returns all results if under limit', () async {
//       final types = <String, IndexedType>{};
//       for (var i = 0; i < 10; i++) {
//         final name = 'Class$i';
//         types[name] = InMemoryIndexedType(name: name);
//       }

//       indexedClassProvider = FakeIndexedClassProvider(types: types);

//       final text = 'Cla';
//       final result = await complete(text, line: 0, character: 3);

//       expect(result.items.length, 10);
//       expect(result.isIncomplete, isFalse);
//     });
//   });

//   group('Indexed File Submember Completion', () {
//     test(
//       'suggests inner classes, interfaces, and enums as static members',
//       () async {
//         indexedClassProvider = FakeIndexedClassProvider(
//           types: {
//             'OuterClass': InMemoryIndexedType(
//               name: 'OuterClass',
//               staticMembers: ['staticField'],
//               instanceMembers: ['instanceField'],
//               nestedTypes: {
//                 'InnerClass': InMemoryIndexedType(name: 'InnerClass'),
//                 'InnerInterface': InMemoryIndexedType(name: 'InnerInterface'),
//                 'InnerEnum': InMemoryIndexedType(name: 'InnerEnum'),
//               },
//             ),
//           },
//         );

//         final text = 'OuterClass.';
//         final result = await complete(text, line: 0, character: text.length);

//         final labels = result.items.map((i) => i.label);
//         expect(labels, contains('InnerClass'));
//         expect(labels, contains('InnerInterface'));
//         expect(labels, contains('InnerEnum'));
//         expect(labels, contains('staticField'));
//         expect(labels, isNot(contains('instanceField')));
//       },
//     );

//     test(
//       'suggests members of inner classes when accessed via qualified name',
//       () async {
//         indexedClassProvider = FakeIndexedClassProvider(
//           types: {
//             'OuterClass': InMemoryIndexedType(
//               name: 'OuterClass',
//               nestedTypes: {
//                 'InnerClass': InMemoryIndexedType(
//                   name: 'InnerClass',
//                   staticMembers: ['innerStaticField'],
//                   instanceMembers: ['innerInstanceField'],
//                 ),
//               },
//             ),
//           },
//         );

//         // Simulates: OuterClass.InnerClass.
//         final text = 'OuterClass.InnerClass.';
//         final result = await complete(text, line: 0, character: text.length);

//         final labels = result.items.map((i) => i.label);
//         expect(labels, contains('innerStaticField'));
//         expect(labels, isNot(contains('innerInstanceField')));
//       },
//     );

//     test(
//       'suggests values of inner enums when accessed via qualified name',
//       () async {
//         indexedClassProvider = FakeIndexedClassProvider(
//           types: {
//             'OuterClass': InMemoryIndexedType(
//               name: 'OuterClass',
//               nestedTypes: {
//                 'InnerEnum': InMemoryIndexedType(
//                   name: 'InnerEnum',
//                   staticMembers: ['VAL1', 'VAL2'],
//                 ),
//               },
//             ),
//           },
//         );

//         final text = 'OuterClass.InnerEnum.';
//         final result = await complete(text, line: 0, character: text.length);

//         final labels = result.items.map((i) => i.label);
//         expect(labels, containsAll(['VAL1', 'VAL2']));
//       },
//     );

//     test(
//       'suggests instance members when variable type is a qualified inner type',
//       () async {
//         indexedClassProvider = FakeIndexedClassProvider(
//           types: {
//             'OuterClass': InMemoryIndexedType(
//               name: 'OuterClass',
//               nestedTypes: {
//                 'InnerClass': InMemoryIndexedType(
//                   name: 'InnerClass',
//                   staticMembers: ['innerStaticField'],
//                   instanceMembers: ['innerInstanceField'],
//                 ),
//               },
//             ),
//           },
//         );

//         // Local variable with type OuterClass.InnerClass
//         localIndexer = FakeTreeSitterIndexer(
//           ApexDocumentIndex(
//             rootScope: Scope(
//               type: ScopeType.file,
//               startByte: 0,
//               endByte: 100,
//               definitions: [
//                 ApexVariableInfo(
//                   name: 'myVar',
//                   typeName: 'OuterClass.InnerClass',
//                   startByte: 0,
//                   endByte: 10,
//                   kind: 'local_variable_declaration',
//                 ),
//               ],
//             ),
//           ),
//         );

//         final text = 'OuterClass.InnerClass myVar; myVar.';
//         final result = await complete(text, line: 0, character: text.length);

//         final labels = result.items.map((i) => i.label);
//         expect(labels, contains('innerInstanceField'));
//         expect(labels, isNot(contains('innerStaticField')));
//       },
//     );
//   });
// }
