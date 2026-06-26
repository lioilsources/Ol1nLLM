/// Pick the single most representative word from a message, used as a compact
/// label for a node in the chat branch tree.
///
/// Heuristic (no NLP): drop punctuation, lowercase-compare against a small
/// Czech/English stopword set, then take the longest remaining token (ties →
/// the earliest). Falls back to the first word, or '…' when there's nothing.
library;

final _stopwords = <String>[
  // Czech
  'a', 'aby', 'ale', 'ani', 'ano', 'asi', 'až', 'bez', 'bude', 'budou', 'by',
  'být', 'co', 'což', 'či', 'dnes', 'do', 'jak', 'jako', 'je', 'jeho', 'její',
  'jen', 'ještě', 'již', 'jsem', 'jsi', 'jsme', 'jsou', 'k', 'kde', 'když',
  'ke', 'která', 'které', 'kteří', 'který', 'ma', 'má', 'mě', 'mi', 'mít',
  'mně', 'mnou', 'můj', 'na', 'nad', 'nám', 'náš', 'ne', 'něj', 'nejsou',
  'není', 'než', 'nic', 'o', 'od', 'pak', 'po', 'pod', 'pro', 'proč', 'před',
  'při', 's', 'se', 'si', 'sice', 'své', 'svůj', 'ta', 'tak', 'také', 'te',
  'tě', 'ten', 'to', 'tom', 'tu', 'ty', 'u', 'už', 'v', 've', 'více', 'však',
  'z', 'za', 'ze', 'že',
  // English
  'an', 'and', 'are', 'as', 'at', 'be', 'but', 'can', 'for',
  'from', 'give', 'how', 'i', 'in', 'is', 'it', 'me', 'my', 'of', 'on', 'or',
  'please', 'so', 'tell', 'that', 'the', 'this', 'us', 'want', 'was',
  'we', 'what', 'when', 'why', 'will', 'with', 'you', 'your',
].toSet();

final _wordSplit = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String keywordOf(String text, {int maxLen = 14}) {
  final raw = text.trim();
  if (raw.isEmpty) return '…';

  final tokens = raw
      .split(_wordSplit)
      .where((t) => t.isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) return '…';

  String? best;
  for (final t in tokens) {
    if (_stopwords.contains(t.toLowerCase())) continue;
    if (best == null || t.length > best.length) best = t;
  }
  best ??= tokens.first;
  return best.length > maxLen ? '${best.substring(0, maxLen - 1)}…' : best;
}
