import 'package:flutter_test/flutter_test.dart';
import 'package:ol1n_llm/models/prompt_negatives.dart';

void main() {
  group('splitPromptNegatives', () {
    test('plain prompt stays positive, negative empty', () {
      final p = splitPromptNegatives('krásná žena v lese, západ slunce');
      expect(p.positive, 'krásná žena v lese, západ slunce');
      expect(p.negative, '');
    });

    test('ALL-CAPS tags move to negative, lowercased', () {
      final p = splitPromptNegatives('portrét ženy, BLURRY, WATERMARK');
      expect(p.positive, 'portrét ženy');
      expect(p.negative, 'blurry, watermark');
    });

    test('multi-word ALL-CAPS tag stays one negative tag', () {
      final p = splitPromptNegatives('cat on a roof, BAD HANDS');
      expect(p.positive, 'cat on a roof');
      expect(p.negative, 'bad hands');
    });

    test('ALL-CAPS words inside a mixed tag are extracted', () {
      final p = splitPromptNegatives('cat BLURRY on a roof UGLY TEETH');
      expect(p.positive, 'cat on a roof');
      expect(p.negative, 'blurry, ugly teeth');
    });

    test('sentence-case and mixed-case words stay positive', () {
      final p = splitPromptNegatives('Krásná žena, McDonald sign');
      expect(p.positive, 'Krásná žena, McDonald sign');
      expect(p.negative, '');
    });

    test('single-letter and single-uppercase tokens stay positive', () {
      final p = splitPromptNegatives('a cat in 8K, I love it');
      expect(p.positive, 'a cat in 8K, I love it');
      expect(p.negative, '');
    });

    test('czech diacritics count as uppercase', () {
      final p = splitPromptNegatives('portrét, ŠPATNÉ RUCE');
      expect(p.positive, 'portrét');
      expect(p.negative, 'špatné ruce');
    });

    test('all-negative input leaves positive empty', () {
      final p = splitPromptNegatives('BLURRY, UGLY');
      expect(p.positive, '');
      expect(p.negative, 'blurry, ugly');
    });

    test('empty and whitespace-only input', () {
      expect(splitPromptNegatives('').positive, '');
      expect(splitPromptNegatives('   ').negative, '');
    });
  });
}
