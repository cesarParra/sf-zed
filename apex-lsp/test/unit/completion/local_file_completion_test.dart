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
    required List<IndexedType> types,
  }) {
    return onCompletion(
      text: textWithPosition.text,
      position: textWithPosition.position,
      index: types,
    );
  }

  test('autocomplete enum types on empty file', () async {
    final enumType = IndexedEnum('Foo', values: []);
    final completionList = await complete(
      extractCursorPosition('{cursor}'),
      types: [enumType],
    );

    expect(completionList.items, hasLength(1));
    expect(completionList.items.first.label, 'Foo');
  });

  test('autocomplete enum types when typing a top level name', () async {
    final enumType = IndexedEnum('Foo', values: []);
    final completionList = await complete(
      extractCursorPosition('F{cursor}'),
      types: [enumType],
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
      types: [enumType],
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
      types: [enumType],
    );

    expect(completionList.items, hasLength(1));
    expect(completionList.items, contains(CompletionItem(label: 'Bar')));
  });
}
