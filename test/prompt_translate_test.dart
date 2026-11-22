import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ol1n_llm/models/gen_node.dart';
import 'package:ol1n_llm/models/image_model.dart';
import 'package:ol1n_llm/models/style_preset.dart';
import 'package:ol1n_llm/services/finetune_translate_service.dart';

/// Prompt translation for the booru checkpoints. The HTTP paths, the cache and
/// the vocabulary filter live in the FINETUNE gallery and are tested there
/// (server/translate_test.go); what this side owns is the fail-open contract
/// and the two node fields the gallery rates each picture against.
void main() {
  group('FinetuneTranslateService — fail open', () {
    test('no credentials → null, and the network is never asked', () async {
      // The test binary has no CF Access credentials — exactly the state of a
      // misconfigured build, which must send prose rather than error.
      var calls = 0;
      final svc = FinetuneTranslateService(
        client: MockClient((req) async {
          calls++;
          return http.Response(
            jsonEncode({'text': '1girl', 'translator': 'prompt-tags@v1'}),
            200,
          );
        }),
      );
      expect(await svc.translate('a ballerina on pointe'), isNull);
      expect(calls, 0);
    });

    test('empty text is nothing to translate', () async {
      final svc = FinetuneTranslateService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await svc.translate('   '), isNull);
    });
  });

  group('GenNode.promptSent / translator', () {
    test('round-trip, and both omitted when unset', () {
      final json = GenNode.create(
        prompt: 'a ballerina',
        promptSent: '1girl, ballerina',
        translator: 'prompt-tags@v1',
      ).toJson();
      expect(json['promptSent'], '1girl, ballerina');
      expect(json['translator'], 'prompt-tags@v1');
      final back = GenNode.fromJson(json);
      expect(back.promptSent, '1girl, ballerina');
      expect(back.translator, 'prompt-tags@v1');
      // Omitted, not null: the gallery reads a missing translator as the
      // as-written control arm of the translation A/B.
      final bare = GenNode.create(prompt: 'x').toJson();
      expect(bare.containsKey('promptSent'), isFalse);
      expect(bare.containsKey('translator'), isFalse);
    });

    test(
      'copyWith sets them after creation and keeps them on status changes',
      () {
        // The node exists before its prompt is composed, so these are the fields
        // copyWith must be able to set — and must not wipe on the status
        // updates every round makes afterwards.
        final n = GenNode.create(prompt: 'x')
            .copyWith(promptSent: '1girl', translator: 'prompt-tags@v1')
            .copyWith(status: GenStatus.ready);
        expect(n.promptSent, '1girl');
        expect(n.translator, 'prompt-tags@v1');
      },
    );

    test('a retry that fails open clears the old translator', () {
      // Retry on a node translated last time, translator down this time: the
      // prose that went out must not be credited to the translator.
      final n = GenNode.create(prompt: 'x')
          .copyWith(promptSent: '1girl', translator: 'prompt-tags@v1')
          .copyWith(promptSent: 'x', clearTranslator: true);
      expect(n.promptSent, 'x');
      expect(n.translator, isNull);
    });

    test('the export carries both fields to the gallery', () {
      // FinetuneExportService sends node.toJson() minus runtime keys; the
      // gallery's ingest reads promptSent and translator from it.
      final json =
          GenNode.create(
              prompt: 'x',
              promptSent: 'y',
              translator: 'prompt-tags@v1',
            ).toJson()
            ..remove('images')
            ..remove('status')
            ..remove('error')
            ..remove('jobId');
      expect(json['promptSent'], 'y');
      expect(json['translator'], 'prompt-tags@v1');
    });
  });

  group('who gets translated', () {
    test('only booru-dialect models — the rest read prose', () {
      final booru = kImageModels
          .where((m) => m.promptDialect == PromptDialect.booru)
          .map((m) => m.id)
          .toSet();
      // The tag-trained lineages; a FLUX or a photoreal SDXL here would get
      // tags it cannot read.
      expect(booru, isNotEmpty);
      for (final m in kImageModels) {
        if (m.id.startsWith('flux') || m.id.startsWith('juggernaut')) {
          expect(booru.contains(m.id), isFalse, reason: m.id);
        }
      }
    });
  });
}
