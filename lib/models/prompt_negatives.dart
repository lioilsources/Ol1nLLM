/// Splitting a raw user prompt into its positive and negative halves.
///
/// The Image Studio input has no separate negative-prompt field; instead,
/// tags/words typed in ALL CAPS are treated as negative-prompt entries:
///
///     krásná žena v lese, BLURRY, BAD HANDS extra detail
///       → positive: 'krásná žena v lese, extra detail'
///       → negative: 'blurry, bad hands'
///
/// Rules:
///   • The input is split on commas into tags, tags into whitespace words.
///   • A word is negative when it contains **no lowercase letter and at least
///     two uppercase letters** — so `8K`, `I` or `A` stay positive, while
///     `BLURRY` or `ŠPATNÉ` move out. Mixed-case words (`Blurry`) stay
///     positive, including the sentence-case capitalization the keyboard
///     inserts automatically.
///   • Consecutive negative words inside one tag form a single negative tag
///     (`BAD HANDS` → `bad hands`); negatives are lowercased because tag
///     vocabularies are trained lowercase.
class PromptParts {
  final String positive;
  final String negative;
  const PromptParts(this.positive, this.negative);
}

bool _isNegativeWord(String word) {
  var uppercaseLetters = 0;
  for (final rune in word.runes) {
    final ch = String.fromCharCode(rune);
    if (ch.toLowerCase() == ch.toUpperCase()) continue; // not a letter
    if (ch != ch.toUpperCase()) return false; // lowercase letter present
    uppercaseLetters++;
  }
  return uppercaseLetters >= 2;
}

PromptParts splitPromptNegatives(String input) {
  final positives = <String>[];
  final negatives = <String>[];
  for (final segment in input.split(',')) {
    final words =
        segment.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final positiveWords = <String>[];
    var negativeRun = <String>[];
    void flushRun() {
      if (negativeRun.isEmpty) return;
      negatives.add(negativeRun.join(' ').toLowerCase());
      negativeRun = <String>[];
    }

    for (final word in words) {
      if (_isNegativeWord(word)) {
        negativeRun.add(word);
      } else {
        flushRun();
        positiveWords.add(word);
      }
    }
    flushRun();
    if (positiveWords.isNotEmpty) positives.add(positiveWords.join(' '));
  }
  return PromptParts(positives.join(', '), negatives.join(', '));
}
