import 'package:apex_lsp/completion/completion.dart';
import 'package:apex_lsp/completion/levenshtein_distance.dart';

typedef Rank =
    Iterable<CompletionCandidate> Function(
      Iterable<CompletionCandidate>,
      String prefix,
    );

Iterable<CompletionCandidate> rankCandidates(
  Iterable<CompletionCandidate> candidates,
  String prefix,
) {
  if (prefix.isEmpty) return candidates;
  final lowerPrefix = prefix.toLowerCase();

  final scored =
      candidates
          .map(
            (candidate) => (
              candidate: candidate,
              length: candidate.name.length,
              distance: levenshteinDistance(
                lowerPrefix,
                candidate.name.toLowerCase(),
              ),
            ),
          )
          .toList()
        ..sort((a, b) {
          final byDistance = a.distance.compareTo(b.distance);
          if (byDistance != 0) return byDistance;

          final byLength = a.length.compareTo(b.length);
          if (byLength != 0) return byLength;

          return a.candidate.name.compareTo(b.candidate.name);
        });

  return scored.map((c) => c.candidate).toList();
}
