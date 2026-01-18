import 'package:apex_lsp/completion/levenshtein_distance.dart';

typedef Rank = List<String> Function(List<String> labels, String prefix);

List<String> rankCandidates(List<String> labels, String prefix) {
  if (prefix.isEmpty) return List<String>.from(labels);
  final lowerPrefix = prefix.toLowerCase();

  final scored =
      labels
          .where((name) => name.toLowerCase().startsWith(lowerPrefix))
          .map(
            (name) => (
              name: name,
              length: name.length,
              distance: levenshteinDistance(lowerPrefix, name.toLowerCase()),
            ),
          )
          .toList()
        ..sort((a, b) {
          final byDistance = a.distance.compareTo(b.distance);
          if (byDistance != 0) return byDistance;

          final byLength = a.length.compareTo(b.length);
          if (byLength != 0) return byLength;

          return a.name.compareTo(b.name);
        });

  return scored.map((c) => c.name).toList();
}
