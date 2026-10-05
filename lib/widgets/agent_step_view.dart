import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:share_plus/share_plus.dart';
import '../core/constants/theme.dart';
import '../models/agent_step.dart';

/// Sends a user turn from inside an agent answer: the readable [text] goes
/// into the bubble, [answers] ride on the message to `/agent/chat`.
typedef AgentSend = void Function(String text, List<AgentAnswer> answers);

/// The structured part of a Právník contract-agent answer, under its text:
/// intake progress, question card, refused answers, broken statutory limits
/// and — at the end — the finished document with checklist and warnings.
///
/// The card is interactive only on the live tip of the thread ([active]);
/// older steps show what was asked, read-only, so scrolling back does not
/// offer a second way to answer a question the server has moved past.
class AgentStepView extends StatelessWidget {
  final AgentStep step;
  final bool active;
  final AgentSend? onSend;

  const AgentStepView({
    super.key,
    required this.step,
    this.active = false,
    this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final intake = step.intake;
    final canAct = active && onSend != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (intake != null && !step.hasDocument) _Progress(intake: intake),
        if (step.rejected.isNotEmpty) _Rejected(step.rejected),
        if (intake != null && intake.limits.isNotEmpty && !step.hasDocument)
          _Limits(intake.limits),
        if (step.questions.isNotEmpty)
          canAct
              ? AgentQuestionCard(
                  key: ValueKey(step.questions.map((q) => q.id).join('|')),
                  questions: step.questions,
                  onSubmit: onSend!,
                )
              : _AskedReadOnly(step.questions),
        if (canAct &&
            intake != null &&
            intake.readyToRender &&
            !step.hasDocument &&
            step.questions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FilledButton.icon(
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Sestavit dokument'),
              onPressed: () =>
                  onSend!('Všechno je vyplněné, sestav prosím dokument.', []),
            ),
          ),
        if (step.hasDocument) AgentDocumentCard(step: step),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  final AgentIntake intake;
  const _Progress({required this.intake});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📄 ${intake.title} · ${intake.requiredFilled}/${intake.required}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: intake.progress,
              minHeight: 3,
              backgroundColor: Colors.white10,
              color: AppTheme.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Rejected extends StatelessWidget {
  final List<({String id, String reason})> items;
  const _Rejected(this.items);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in items)
            Text(
              '↺ ${r.reason}',
              style: TextStyle(color: Colors.amber[300], fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _Limits extends StatelessWidget {
  final List<AgentLimit> limits;
  const _Limits(this.limits);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in limits)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '⚠️ ${l.message}${l.basis != null ? ' (${l.basis})' : ''}',
                style: TextStyle(color: Colors.orange[300], fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _AskedReadOnly extends StatelessWidget {
  final List<AgentQuestion> questions;
  const _AskedReadOnly(this.questions);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final q in questions)
            Text(
              '• ${q.question}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }
}

/// Up to three questions as one card with an input per question. Inputs
/// follow the template variable type; the server converts the value, so the
/// card only has to collect something sensible ("16 500", "1. 10. 2026").
class AgentQuestionCard extends StatefulWidget {
  final List<AgentQuestion> questions;
  final AgentSend onSubmit;

  const AgentQuestionCard({
    super.key,
    required this.questions,
    required this.onSubmit,
  });

  @override
  State<AgentQuestionCard> createState() => _AgentQuestionCardState();
}

class _AgentQuestionCardState extends State<AgentQuestionCard> {
  late final Map<String, TextEditingController> _text = {
    for (final q in widget.questions)
      if (!_isChoice(q)) q.id: TextEditingController(text: q.current ?? ''),
  };
  late final Map<String, String?> _choice = {
    for (final q in widget.questions)
      if (_isChoice(q)) q.id: q.current,
  };

  static bool _isChoice(AgentQuestion q) =>
      q.type == 'bool' || (q.type == 'enum' && q.options.isNotEmpty);

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _value(AgentQuestion q) =>
      (_isChoice(q) ? _choice[q.id] : _text[q.id]?.text)?.trim() ?? '';

  bool get _anyFilled => widget.questions.any((q) => _value(q).isNotEmpty);

  void _submit() {
    final answers = [
      for (final q in widget.questions)
        if (_value(q).isNotEmpty)
          AgentAnswer(id: q.id, question: q.question, value: _value(q)),
    ];
    if (answers.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final text = answers.map((a) => '${a.question} ${_display(a)}').join('\n');
    widget.onSubmit(text, answers);
  }

  String _display(AgentAnswer a) => switch (a.value) {
    'true' => 'ano',
    'false' => 'ne',
    _ => a.value,
  };

  Future<void> _pickDate(AgentQuestion q) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 30),
    );
    if (picked != null) {
      setState(
        () => _text[q.id]!.text =
            '${picked.day}. ${picked.month}. ${picked.year}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final q in widget.questions) ...[
            Text(
              q.question,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (q.hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  q.hint!,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            _input(q),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _anyFilled ? _submit : null,
              child: const Text('Odeslat odpovědi'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(AgentQuestion q) {
    if (_isChoice(q)) {
      final options = q.type == 'bool'
          ? const [('true', 'ano'), ('false', 'ne')]
          : [for (final o in q.options) (o, _enumLabel(o))];
      return Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final (value, label) in options)
            ChoiceChip(
              label: Text(label),
              selected: _choice[q.id] == value,
              onSelected: (on) =>
                  setState(() => _choice[q.id] = on ? value : null),
            ),
        ],
      );
    }
    final controller = _text[q.id]!;
    final numeric = q.type == 'money' || q.type == 'int';
    return TextField(
      key: ValueKey('agent-input-${q.id}'),
      controller: controller,
      onChanged: (_) => setState(() {}),
      minLines: 1,
      maxLines: q.type == 'text' ? 4 : 1,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : (q.type == 'text' ? TextInputType.multiline : TextInputType.text),
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: switch (q.type) {
          'date' => 'např. 1. 10. 2026',
          'money' => 'částka v Kč',
          'int' => 'číslo',
          _ => null,
        },
        suffixText: q.type == 'money' ? 'Kč' : null,
        suffixIcon: q.type == 'date'
            ? IconButton(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                tooltip: 'Vybrat datum',
                onPressed: () => _pickDate(q),
              )
            : null,
      ),
    );
  }

  /// Template enum values are ids (`neurcita`, `urcita`); show them readable.
  static String _enumLabel(String v) => switch (v) {
    'neurcita' => 'na dobu neurčitou',
    'urcita' => 'na dobu určitou',
    _ => v.replaceAll('_', ' '),
  };
}

/// The finished document: a preview, open/copy/share, then the checklist and
/// the warnings. Copy and share take [AgentStep.shareText] — the document
/// *with* checklist and warnings, so the draft never travels without them.
class AgentDocumentCard extends StatelessWidget {
  final AgentStep step;
  const AgentDocumentCard({super.key, required this.step});

  String get _title => step.intake?.title ?? 'Dokument';

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: step.shareText));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Dokument zkopírován do schránky'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _share() => SharePlus.instance.share(
    ShareParams(text: step.shareText, subject: _title),
  );

  void _open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AgentDocumentScreen(step: step, title: _title),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📄 $_title',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _open(context),
                child: Text(
                  _preview(step.document!),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_full, size: 16),
                    label: const Text('Otevřít'),
                    onPressed: () => _open(context),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Kopírovat'),
                    onPressed: () => _copy(context),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.ios_share, size: 16),
                    label: const Text('Sdílet'),
                    onPressed: _share,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (step.checklist.isNotEmpty) ...[
          const SizedBox(height: 10),
          const _SectionTitle('Kontrolní seznam'),
          for (final c in step.checklist)
            _Line(icon: '☐', text: c, color: AppTheme.textPrimary),
        ],
        if (step.warnings.isNotEmpty) ...[
          const SizedBox(height: 10),
          const _SectionTitle('Upozornění'),
          for (final w in step.warnings)
            _Line(icon: '⚠️', text: w, color: Colors.orange[200]!),
        ],
      ],
    );
  }

  /// Markdown → plain lines for the preview (no `#`, `*`, `_`).
  static String _preview(String md) => md
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'^#+\s*|[*_]'), '').trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Line extends StatelessWidget {
  final String icon;
  final String text;
  final Color color;
  const _Line({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 13, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

/// Full-screen reading of the document. Selectable here (unlike chat
/// bubbles, there is no long-press-to-copy gesture to protect).
class AgentDocumentScreen extends StatelessWidget {
  final AgentStep step;
  final String title;
  const AgentDocumentScreen({
    super.key,
    required this.step,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Kopírovat',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: step.shareText));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Dokument zkopírován do schránky'),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Sdílet',
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: step.shareText, subject: title),
            ),
          ),
        ],
      ),
      body: Markdown(
        data: step.shareText,
        selectable: true,
        styleSheet: AppTheme.markdownStyle(context),
        padding: const EdgeInsets.all(16),
      ),
    );
  }
}
