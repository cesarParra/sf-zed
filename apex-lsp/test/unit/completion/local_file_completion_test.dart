// Contains tests related to autocompleting from types and
// members declared on the file itself. Use cases include
// Anon-apex, where there can be multiple types and variables
// declared at the root of the same file, or a completing
// members from a single class.

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/indexing/declarations.dart';
import 'package:apex_lsp/message.dart';
import 'package:apex_lsp/type_name.dart';
import 'package:test/test.dart';

/// Result of extracting cursor position from text with a {cursor} marker.
class TextWithPosition {
  /// The text with the {cursor} marker removed.
  final String text;

  /// The position where the cursor was located.
  final Position position;

  const TextWithPosition({required this.text, required this.position});
}

/// Converts text containing a {cursor} marker into a Position and clean text.
///
/// The marker {cursor} indicates where the cursor position should be.
/// Lines are 0-indexed and characters are 0-indexed as per LSP specification.
///
/// Example:
/// ```dart
/// final result = extractCursorPosition('Foo.{cursor}');
/// // result.position == Position(line: 0, character: 4)
/// // result.text == 'Foo.'
/// ```
///
/// Throws [ArgumentError] if the text does not contain exactly one {cursor} marker.
TextWithPosition extractCursorPosition(String text) {
  const marker = '{cursor}';

  final markerIndex = text.indexOf(marker);
  if (markerIndex == -1) {
    throw ArgumentError('Text must contain a {cursor} marker');
  }

  // Check for multiple markers
  if (text.indexOf(marker, markerIndex + 1) != -1) {
    throw ArgumentError('Text must contain exactly one {cursor} marker');
  }

  // Calculate line and character position
  int line = 0;
  int character = 0;

  for (int i = 0; i < markerIndex; i++) {
    if (text[i] == '\n') {
      line++;
      character = 0;
    } else {
      character++;
    }
  }

  // Remove the marker from the text
  final cleanText = text.replaceFirst(marker, '');

  return TextWithPosition(
    text: cleanText,
    position: Position(line: line, character: character),
  );
}

void main() {
  Future<CompletionList> complete(
    TextWithPosition textWithPosition, {
    required List<Declaration> index,
  }) {
    return onCompletion(
      text: textWithPosition.text,
      position: textWithPosition.position,
      index: index,
    );
  }

  group('enums', () {
    test('autocomplete enum types on empty file', () async {
      final enumType = IndexedEnum(TypeName('Foo'), values: []);
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Foo');
    });

    test('autocomplete enum types when typing a top level name', () async {
      final enumType = IndexedEnum(TypeName('Foo'), values: []);
      final completionList = await complete(
        extractCursorPosition('F{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Foo');
    });

    test('autocompletes all enum values', () async {
      final enumType = IndexedEnum(
        TypeName('Foo'),
        values: ['Bar'.enumValueMember(), 'Baz'.enumValueMember()],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(2));
      expect(completionList.items, contains(CompletionItem(label: 'Bar')));
      expect(completionList.items, contains(CompletionItem(label: 'Baz')));
    });

    test('autocompletes all enum values by name', () async {
      final enumType = IndexedEnum(
        TypeName('Foo'),
        values: ['Bar'.enumValueMember(), 'Other'.enumValueMember()],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.B{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items, contains(CompletionItem(label: 'Bar')));
    });
  });

  group('variables', () {
    test('autocomplete variable names at top level', () async {
      final variable = IndexedVariable(
        TypeName('myVar'),
        typeName: TypeName('String'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [variable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'myVar');
    });

    test('autocomplete variable names with prefix', () async {
      final variable = IndexedVariable(
        TypeName('myVar'),
        typeName: TypeName('String'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('my{cursor}'),
        index: [variable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'myVar');
    });

    test('mixed types and variables', () async {
      final enumType = IndexedEnum(TypeName('Foo'), values: []);
      final variable = IndexedVariable(
        TypeName('fooInstance'),
        typeName: TypeName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('f{cursor}'),
        index: [enumType, variable],
      );

      expect(completionList.items, hasLength(2));
      expect(completionList.items, contains(CompletionItem(label: 'Foo')));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'fooInstance')),
      );
    });

    test('does not autocomplete variables declared after cursor', () async {
      // The variable is declared at bytes 20-40, but the cursor is at byte 5
      final variable = IndexedVariable(
        TypeName('laterVar'),
        typeName: TypeName('String'),
        location: (20, 40),
      );
      final completionList = await complete(
        extractCursorPosition('l{cursor}                                     '),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });
  });

  group('methods', () {
    test('autocomplete method names at top level', () async {
      final method = MethodDeclaration(
        TypeName('sampleMethod'),
        isStatic: false,
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [method],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'sampleMethod');
    });

    test('autocomplete method names with a prefix', () async {
      final method = MethodDeclaration(
        TypeName('sampleMethod'),
        isStatic: false,
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('sam{cursor}'),
        index: [method],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'sampleMethod');
    });

    test('autocompletes methods declared after cursor', () async {
      final method = MethodDeclaration(
        TypeName('laterMethod'),
        isStatic: false,
        location: (20, 40),
      );
      final completionList = await complete(
        extractCursorPosition('l{cursor}                                     '),
        index: [method],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'laterMethod');
    });
  });

  group('method parameters', () {
    test('autocomplete parameter names', () async {
      final parameter = IndexedVariable(
        TypeName('paramVar'),
        typeName: TypeName('String'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [parameter],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'paramVar');
    });

    test('autocomplete parameter names with prefix', () async {
      final parameter = IndexedVariable(
        TypeName('paramVar'),
        typeName: TypeName('String'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('par{cursor}'),
        index: [parameter],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'paramVar');
    });

    test('autocomplete members of a parameter typed as an interface', () async {
      final interfaceType = IndexedInterface(
        TypeName('Foo'),
        methods: [
          MethodDeclaration(TypeName('doSomething'), isStatic: false),
          MethodDeclaration(TypeName('saySomething'), isStatic: false),
        ],
      );
      final parameter = IndexedVariable(
        TypeName('paramVar'),
        typeName: TypeName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('paramVar.{cursor}'),
        index: [interfaceType, parameter],
      );

      expect(completionList.items, hasLength(2));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
      expect(
        completionList.items,
        contains(CompletionItem(label: 'saySomething')),
      );
    });

    test('autocomplete members of a parameter filtered by prefix', () async {
      final interfaceType = IndexedInterface(
        TypeName('Foo'),
        methods: [
          MethodDeclaration(TypeName('doSomething'), isStatic: false),
          MethodDeclaration(TypeName('saySomething'), isStatic: false),
        ],
      );
      final parameter = IndexedVariable(
        TypeName('paramVar'),
        typeName: TypeName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('paramVar.do{cursor}'),
        index: [interfaceType, parameter],
      );

      expect(completionList.items, hasLength(1));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
    });

    test('parameter is completed when cursor is inside method body', () async {
      // Parameter at bytes 18-32, method body spans bytes 35-60
      final parameter = IndexedVariable(
        TypeName('paramVar'),
        typeName: TypeName('String'),
        location: (18, 32),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 60),
      );
      final completionList = await complete(
        // Cursor at byte 40, inside the method body
        extractCursorPosition(
          '                  Foo paramVar  {    p{cursor}                    }',
        ),
        index: [parameter],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'paramVar');
    });

    test(
      'parameter is not completed when cursor is outside method body',
      () async {
        // Parameter at bytes 18-32, method body spans bytes 35-60
        final parameter = IndexedVariable(
          TypeName('paramVar'),
          typeName: TypeName('String'),
          location: (18, 32),
          visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 60),
        );
        final completionList = await complete(
          extractCursorPosition(
            '                  Foo paramVar  {                           }  p{cursor}',
          ),
          index: [parameter],
        );

        expect(completionList.items, isEmpty);
      },
    );

    test(
      'variable inside method body is completed at cursor inside body',
      () async {
        // Variable at bytes 40-46, method body ends at byte 50
        final variable = IndexedVariable(
          TypeName('myTest'),
          typeName: TypeName('String'),
          location: (40, 46),
          visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 50),
        );
        final completionList = await complete(
          // Cursor at byte 48, after the variable but inside the body
          extractCursorPosition(
            '                                        myTest  {cursor} }',
          ),
          index: [variable],
        );

        expect(completionList.items, hasLength(1));
        expect(completionList.items.first.label, 'myTest');
      },
    );

    test('variable inside method body is not completed outside body', () async {
      final variable = IndexedVariable(
        TypeName('myTest'),
        typeName: TypeName('String'),
        location: (40, 46),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 50),
      );
      final completionList = await complete(
        // Cursor at byte 55, after the method body
        extractCursorPosition(
          '                                        myTest     }    m{cursor}',
        ),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });
  });

  group('loop scoping', () {
    test('for loop init variable is not completed after the loop', () async {
      final variable = IndexedVariable(
        TypeName('myIndex'),
        typeName: TypeName('Integer'),
        location: (5, 12),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 30),
      );
      final completionList = await complete(
        extractCursorPosition('     myIndex              }         my{cursor}'),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });

    test('for loop init variable is completed inside the for body', () async {
      final variable = IndexedVariable(
        TypeName('myIndex'),
        typeName: TypeName('Integer'),
        location: (5, 12),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 40),
      );
      final completionList = await complete(
        extractCursorPosition(
          '     myIndex        my{cursor}                  ',
        ),
        index: [variable],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'myIndex');
    });

    test('enhanced for variable is not completed after the loop', () async {
      final variable = IndexedVariable(
        TypeName('item'),
        typeName: TypeName('String'),
        location: (16, 20),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 40),
      );
      final completionList = await complete(
        // Cursor at byte 45, after the loop
        extractCursorPosition(
          'for (String item : items) {            }    i{cursor}',
        ),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });

    test('while loop body variable is not completed after the loop', () async {
      final variable = IndexedVariable(
        TypeName('loopVar'),
        typeName: TypeName('String'),
        location: (17, 24),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 40),
      );
      final completionList = await complete(
        // Cursor at byte 45, after the while loop
        extractCursorPosition(
          'while (true) {  loopVar                         }    l{cursor}',
        ),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });

    test('nested block variable is not completed outside that block', () async {
      final innerVar = IndexedVariable(
        TypeName('innerVar'),
        typeName: TypeName('String'),
        location: (12, 20),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 30),
      );
      final outerVar = IndexedVariable(
        TypeName('outerVar'),
        typeName: TypeName('String'),
        location: (0, 8),
        visibility: VisibleBetweenDeclarationAndScopeEnd(scopeEnd: 50),
      );
      final completionList = await complete(
        // Cursor at byte 35, after inner block but inside outer scope
        extractCursorPosition(
          'outerVar  { innerVar          }    {cursor}              ',
        ),
        index: [innerVar, outerVar],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'outerVar');
    });
  });

  group('interfaces', () {
    test('autocomplete interface types at top level', () async {
      final interfaceType = IndexedInterface(
        TypeName('Foo'),
        methods: [MethodDeclaration(TypeName('doSomething'), isStatic: false)],
      );
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [interfaceType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Foo');
    });

    test('autocompletes all interface methods via type name', () async {
      final interfaceType = IndexedInterface(
        TypeName('Foo'),
        methods: [
          MethodDeclaration(TypeName('doSomething'), isStatic: false),
          MethodDeclaration(TypeName('saySomething'), isStatic: false),
        ],
      );
      final completionList = await complete(
        extractCursorPosition('Foo.{cursor}'),
        index: [interfaceType],
      );

      expect(completionList.items, hasLength(2));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
      expect(
        completionList.items,
        contains(CompletionItem(label: 'saySomething')),
      );
    });

    test('autocompletes interface methods via variable', () async {
      final interfaceType = IndexedInterface(
        TypeName('Foo'),
        methods: [
          MethodDeclaration(TypeName('doSomething'), isStatic: false),
          MethodDeclaration(TypeName('saySomething'), isStatic: false),
        ],
      );
      final variable = IndexedVariable(
        TypeName('myVar'),
        typeName: TypeName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('myVar.{cursor}'),
        index: [interfaceType, variable],
      );

      expect(completionList.items, hasLength(2));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
      expect(
        completionList.items,
        contains(CompletionItem(label: 'saySomething')),
      );
    });

    test('autocompletes interface methods filtered by prefix', () async {
      final interfaceType = IndexedInterface(
        TypeName('Foo'),
        methods: [
          MethodDeclaration(TypeName('doSomething'), isStatic: false),
          MethodDeclaration(TypeName('saySomething'), isStatic: false),
        ],
      );
      final variable = IndexedVariable(
        TypeName('myVar'),
        typeName: TypeName('Foo'),
        location: (0, 10),
      );
      final completionList = await complete(
        extractCursorPosition('myVar.do{cursor}'),
        index: [interfaceType, variable],
      );

      expect(completionList.items, hasLength(1));
      expect(
        completionList.items,
        contains(CompletionItem(label: 'doSomething')),
      );
    });
  });
}
