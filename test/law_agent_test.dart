import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ol1n_llm/models/agent_step.dart';
import 'package:ol1n_llm/models/message.dart';
import 'package:ol1n_llm/models/persona.dart';
import 'package:ol1n_llm/services/chat_backend.dart';
import 'package:ol1n_llm/services/law_agent_service.dart';
import 'package:ol1n_llm/widgets/agent_step_view.dart';

/// Právník – smlouvy 📝 (`backend: "law-agent"`) talks to `POST /agent/chat`.
///
/// `test/fixtures/law_agent_step{1,2,6,7}_*.json` are **real responses**:
/// a run of the agent against qwen36 on SPARK (LiteLLM alias `pravnik-agent`
/// → `openclaw-default`, gateway :8080) on 2026-10-05 ~22:50, drafting a flat
/// lease (`najemni_smlouva_byt`) in seven steps — start, six cards of
/// answers, render. They were produced by the server code from the
/// WorldLibraryProject branch `pravnik-agent-app` (`agent/klient.py`
/// `krok_pro_klienta`, i.e. exactly what `/agent/chat` returns) run on the
/// Mac against the live model, PG and law index, **not by the deployed
/// :8098**, which still had the old contract at capture time. Party data are
/// the fictional ones from the server's template fixtures.
///
/// `test/fixtures/law_agent_503.json` is **not captured** (the model was up
/// during the run): it is the body the server builds from
/// `agent/klient.py` `hlaska_modelu()` outside the 19–01 window.
Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/fixtures/law_agent_$name.json').readAsStringSync())
            as Map)
        .cast<String, dynamic>();

Message _user(String text, {List<AgentAnswer> answers = const []}) => Message(
  id: 'u1',
  role: MessageRole.user,
  content: text,
  createdAt: DateTime(2026, 10, 5),
  agentAnswers: answers,
);

void main() {
  group('routing', () {
    late Persona smlouvy;

    setUpAll(() {
      final raw = File('assets/personas/index.json').readAsStringSync();
      final all = ((jsonDecode(raw) as Map)['personas'] as List)
          .cast<Map<String, dynamic>>()
          .map(Persona.fromJson)
          .toList();
      smlouvy = all.firstWhere((p) => p.id == 'pravnik_smlouvy');
    });

    test('Právník – smlouvy routes to the agent, not the law RAG stream', () {
      expect(smlouvy.backend, kChatBackendLawAgent);
      expect(smlouvy.emoji, '📝');
      expect(smlouvy.file, isNull);
      expect(chatBackendIdFor(smlouvy), 'law-agent');
      // Different backend id ⇒ picking it from a law chat starts a new
      // conversation (chat_input_bar compares Persona.backend).
      expect(smlouvy.backend, isNot(kChatBackendLaw));
    });

    test('service id matches the routing id', () {
      final s = LawAgentService();
      addTearDown(s.dispose);
      expect(s.id, kChatBackendLawAgent);
    });
  });

  group('captured steps parse', () {
    test('step 1: template picked, cards from the template, progress 0/15', () {
      final step = AgentStep.fromJson(_fixture('step1_start'));
      expect(step.mode, 'draft');
      expect(step.questions.map((q) => q.id), [
        'pronajimatel_jmeno',
        'pronajimatel_identifikace',
        'pronajimatel_adresa',
      ]);
      expect(step.intake!.template, 'najemni_smlouva_byt');
      expect(step.intake!.title, 'Nájemní smlouva (byt)');
      expect(step.intake!.required, 15);
      expect(step.intake!.requiredFilled, 0);
      expect(step.hasDocument, isFalse);
    });

    test('step 2: answers saved server-side, next card', () {
      final json = _fixture('step2_answers');
      final step = AgentStep.fromJson(json);
      expect(step.intake!.requiredFilled, 3);
      expect(step.rejected, isEmpty);
      expect(step.questions.first.id, 'najemce_jmeno');
      expect(json['session_id'], _fixture('step1_start')['session_id']);
    });

    test('step 6: conditionally required date comes as a typed card', () {
      final step = AgentStep.fromJson(_fixture('step6_limit'));
      final q = step.questions.single;
      expect(q.id, 'doba_do');
      expect(q.type, 'date');
      expect(q.hint, contains('určitou'));
      expect(step.intake!.requiredFilled, step.intake!.required);
      expect(step.intake!.readyToRender, isFalse);
      expect(step.intake!.limits, isNotEmpty);
    });

    test('step 7: document with checklist and warnings, no cards', () {
      final step = AgentStep.fromJson(_fixture('step7_document'));
      expect(step.hasDocument, isTrue);
      expect(step.document, contains('NÁJEMNÍ SMLOUVA'));
      expect(step.checklist, isNotEmpty);
      expect(step.warnings, isNotEmpty);
      expect(step.questions, isEmpty);
      expect(step.intake!.status, 'hotovo');

      final share = step.shareText;
      expect(share, startsWith('# NÁJEMNÍ SMLOUVA'));
      expect(share, contains('## Kontrolní seznam'));
      expect(share, contains('- [ ] ${step.checklist.first}'));
      expect(share, contains('## Upozornění'));
    });
  });

  group('wire', () {
    test('request carries session, draft mode and card answers', () {
      final body = LawAgentService.requestBody(
        _user(
          'Nájemné? 16 500',
          answers: const [
            AgentAnswer(id: 'najemne', question: 'Nájemné?', value: '16 500'),
          ],
        ),
        remoteSessionId: 's-1',
      );
      expect(body['message'], 'Nájemné? 16 500');
      expect(body['session_id'], 's-1');
      expect(body['mode'], 'draft');
      expect(body['odpovedi'], [
        {'id': 'najemne', 'otazka': 'Nájemné?', 'hodnota': '16 500'},
      ]);
    });

    test('first turn sends no session id and no answers', () {
      final body = LawAgentService.requestBody(_user('Chci nájemní smlouvu'));
      expect(body.containsKey('session_id'), isFalse);
      expect(body.containsKey('odpovedi'), isFalse);
    });

    test('503 outside the window shows the server sentence verbatim', () {
      final text = LawAgentService.errorText(
        503,
        jsonEncode(_fixture('503')),
        const {},
      );
      expect(text, startsWith('[právník] Právník teď smlouvy nesepisuje'));
      expect(text, contains('19:00'));
      expect(text, isNot(contains('systemctl')));
      expect(text, isNot(contains('HTTP')));
    });

    test('502 from the tunnel points at the unit', () {
      final text = LawAgentService.errorText(502, 'Bad gateway', const {});
      expect(text, contains('law-chat'));
    });

    test('empty reply text falls back to something readable', () {
      const doc = AgentStep(document: '# X');
      expect(LawAgentService.replyText({'odpoved': ''}, doc), isNotEmpty);
      const ask = AgentStep(
        questions: [AgentQuestion(id: 'a', question: 'A?')],
      );
      expect(LawAgentService.replyText({}, ask), 'Doplň prosím:');
    });

    test('chat(): one delta plus a done carrying the step', () async {
      final fixture = _fixture('step7_document');
      late Map<String, dynamic> sent;
      final client = MockClient((req) async {
        expect(req.url.path, '/agent/chat');
        sent = (jsonDecode(req.body) as Map).cast();
        return http.Response.bytes(
          utf8.encode(jsonEncode(fixture)),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final s = LawAgentService(client: client);
      final events = await s.chat([
        _user('Sestav dokument'),
      ], remoteSessionId: 'sid').toList();

      expect(sent['session_id'], 'sid');
      expect(events, hasLength(2));
      expect((events[0] as ChatDelta).content, fixture['odpoved']);
      final done = events[1] as ChatDone;
      expect(done.remoteSessionId, fixture['session_id']);
      expect(done.agentStep!.hasDocument, isTrue);
      expect(done.sources, isEmpty);
    });

    test('chat(): 503 surfaces as an exception with the human sentence', () {
      final client = MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode(_fixture('503'))),
          503,
          headers: {'content-type': 'application/json'},
        ),
      );
      final s = LawAgentService(client: client);
      expect(
        s.chat([_user('Chci smlouvu')]).toList(),
        throwsA(predicate((e) => '$e'.contains('jen večer od 19:00 do 01:00'))),
      );
    });
  });

  group('persistence', () {
    test('agent step and answers survive the Hive JSON round trip', () {
      final step = AgentStep.fromJson(_fixture('step6_limit'));
      final m = Message(
        id: 'a1',
        role: MessageRole.assistant,
        content: 'Do kdy?',
        createdAt: DateTime(2026, 10, 5),
        agentStep: step,
      );
      final back = Message.fromJson(
        (jsonDecode(jsonEncode(m.toJson())) as Map).cast(),
      );
      expect(back.agentStep!.questions.single.id, 'doba_do');
      expect(back.agentStep!.questions.single.type, 'date');
      expect(back.agentStep!.intake!.limits, isNotEmpty);

      final u = _user(
        'x',
        answers: const [
          AgentAnswer(id: 'doba_do', question: 'Do kdy?', value: '30. 9. 2027'),
        ],
      );
      final ub = Message.fromJson(
        (jsonDecode(jsonEncode(u.toJson())) as Map).cast(),
      );
      expect(ub.agentAnswers.single.value, '30. 9. 2027');
    });

    test('old messages without agent fields still load', () {
      final m = Message.fromJson({
        'id': 'x',
        'role': 'assistant',
        'content': 'ahoj',
        'createdAt': '2026-10-05T10:00:00.000',
      });
      expect(m.agentStep, isNull);
      expect(m.agentAnswers, isEmpty);
    });
  });

  group('AgentStepView', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

    testWidgets('active card collects answers and sends them with ids', (
      tester,
    ) async {
      final step = AgentStep.fromJson(_fixture('step1_start'));
      String? text;
      List<AgentAnswer>? answers;
      await tester.pumpWidget(
        host(
          AgentStepView(
            step: step,
            active: true,
            onSend: (t, a) {
              text = t;
              answers = a;
            },
          ),
        ),
      );

      expect(find.byType(TextField), findsNWidgets(3));
      final send = find.widgetWithText(FilledButton, 'Odeslat odpovědi');
      expect(tester.widget<FilledButton>(send).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('agent-input-pronajimatel_jmeno')),
        'Jana Dvořáková',
      );
      await tester.enterText(
        find.byKey(const ValueKey('agent-input-pronajimatel_adresa')),
        'Krátká 12, Brno',
      );
      await tester.pump();
      await tester.tap(send);

      expect(answers!.map((a) => a.id), [
        'pronajimatel_jmeno',
        'pronajimatel_adresa',
      ]);
      expect(text, contains('Jana Dvořáková'));
    });

    testWidgets('inactive step lists the questions without inputs', (
      tester,
    ) async {
      final step = AgentStep.fromJson(_fixture('step1_start'));
      await tester.pumpWidget(
        host(AgentStepView(step: step, onSend: (_, _) {})),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('•'), findsNWidgets(3));
    });

    testWidgets('enum question renders as choices', (tester) async {
      const step = AgentStep(
        questions: [
          AgentQuestion(
            id: 'doba',
            question: 'Na dobu neurčitou, nebo určitou?',
            type: 'enum',
            options: ['neurcita', 'urcita'],
          ),
        ],
      );
      List<AgentAnswer>? answers;
      await tester.pumpWidget(
        host(
          AgentStepView(
            step: step,
            active: true,
            onSend: (_, a) => answers = a,
          ),
        ),
      );
      await tester.tap(find.text('na dobu určitou'));
      await tester.pump();
      await tester.tap(find.text('Odeslat odpovědi'));
      expect(answers!.single.value, 'urcita');
    });

    testWidgets('finished document offers open, copy and share', (
      tester,
    ) async {
      final step = AgentStep.fromJson(_fixture('step7_document'));
      await tester.pumpWidget(
        host(AgentStepView(step: step, active: true, onSend: (_, _) {})),
      );
      expect(find.text('📄 Nájemní smlouva (byt)'), findsOneWidget);
      expect(find.text('Otevřít'), findsOneWidget);
      expect(find.text('Kopírovat'), findsOneWidget);
      expect(find.text('Sdílet'), findsOneWidget);
      expect(find.text('Kontrolní seznam'), findsOneWidget);
      expect(find.text('Upozornění'), findsOneWidget);
      expect(find.text('Odeslat odpovědi'), findsNothing);
    });

    testWidgets('ready intake without a document offers to render', (
      tester,
    ) async {
      const step = AgentStep(
        intake: AgentIntake(
          template: 'nda',
          title: 'NDA',
          required: 10,
          requiredFilled: 10,
          readyToRender: true,
        ),
      );
      String? sent;
      await tester.pumpWidget(
        host(
          AgentStepView(step: step, active: true, onSend: (t, _) => sent = t),
        ),
      );
      await tester.tap(find.text('Sestavit dokument'));
      expect(sent, contains('sestav'));
    });
  });
}
