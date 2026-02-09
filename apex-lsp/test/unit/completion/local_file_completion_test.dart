// Contains tests related to autocompleting from types and
// members declared on the file itself. Use cases include
// Anon-apex, where there can be multiple types and variables
// declared at the root of the same file, or a completing
// members from a single class.

import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/indexing/revamped.dart';
import 'package:apex_lsp/message.dart';
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
      final enumType = IndexedEnum('Foo', values: []);
      final completionList = await complete(
        extractCursorPosition('{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Foo');
    });

    test('autocomplete enum types when typing a top level name', () async {
      final enumType = IndexedEnum('Foo', values: []);
      final completionList = await complete(
        extractCursorPosition('F{cursor}'),
        index: [enumType],
      );

      expect(completionList.items, hasLength(1));
      expect(completionList.items.first.label, 'Foo');
    });

    test('autocompletes all enum values', () async {
      final enumType = IndexedEnum(
        'Foo',
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
        'Foo',
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
        'myVar',
        typeName: 'String',
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
        'myVar',
        typeName: 'String',
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
      final enumType = IndexedEnum('Foo', values: []);
      final variable = IndexedVariable(
        'fooInstance',
        typeName: 'Foo',
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
        'laterVar',
        typeName: 'String',
        location: (20, 40),
      );
      final completionList = await complete(
        extractCursorPosition('l{cursor}                                     '),
        index: [variable],
      );

      expect(completionList.items, isEmpty);
    });
  });

  group('interfaces', () {
    test('autocomplete interface types at top level', () async {
      final interfaceType = IndexedInterface(
        'Foo',
        methods: [MethodMember('doSomething', isStatic: false)],
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
        'Foo',
        methods: [
          MethodMember('doSomething', isStatic: false),
          MethodMember('saySomething', isStatic: false),
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
        'Foo',
        methods: [
          MethodMember('doSomething', isStatic: false),
          MethodMember('saySomething', isStatic: false),
        ],
      );
      final variable = IndexedVariable(
        'myVar',
        typeName: 'Foo',
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
        'Foo',
        methods: [
          MethodMember('doSomething', isStatic: false),
          MethodMember('saySomething', isStatic: false),
        ],
      );
      final variable = IndexedVariable(
        'myVar',
        typeName: 'Foo',
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
