import 'package:flutter/material.dart';

import '../models/hairstyle_preset.dart';
import '../core/constants/theme.dart';

/// What the Kadeřník sheet picked: a hairstyle id (null = keep the cut) and a
/// colour id (null = keep the colour). Never both null.
typedef HairChoice = ({String? style, String? colour});

/// Kadeřník picker: colour chips, Ženy / Muži, sections, search without
/// diacritics. Tapping a hairstyle pops it with the chosen colour; "Jen barva"
/// pops the colour alone.
class HairSheet extends StatefulWidget {
  const HairSheet({
    super.key,
    this.catalog = kHairstyles,
    this.colours = kHairColours,
  });

  /// Injectable for tests.
  final List<HairstylePreset> catalog;
  final List<HairColourPreset> colours;

  static Future<HairChoice?> show(BuildContext context) =>
      showModalBottomSheet<HairChoice>(
        context: context,
        backgroundColor: AppTheme.surface,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const HairSheet(),
      );

  @override
  State<HairSheet> createState() => _HairSheetState();
}

class _HairSheetState extends State<HairSheet> {
  String _group = kHairGroupWomen;
  String _query = '';
  String? _colour;

  @override
  Widget build(BuildContext context) {
    final groups = kHairGroups
        .where((g) => widget.catalog.any((s) => s.group == g))
        .toList();
    if (groups.isNotEmpty && !groups.contains(_group)) _group = groups.first;
    final shown = widget.catalog
        .where((s) => s.group == _group && hairstyleMatchesQuery(s, _query))
        .toList();
    final sections = <String>[];
    for (final s in shown) {
      if (!sections.contains(s.section)) sections.add(s.section);
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                'Kadeřník',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 17),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Tvář zůstane; barva vlasů taky, pokud nevybereš novou. '
                'Nejlíp funguje čelní portrét s celými vlasy, bez čepice.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
              ),
            ),
            if (widget.colours.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final c in [null, ...widget.colours])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(c?.label ?? 'Barva beze změny'),
                                  selected: _colour == c?.id,
                                  onSelected: (_) =>
                                      setState(() => _colour = c?.id),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _colour == null
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop((style: null, colour: _colour)),
                      child: const Text('Jen barva'),
                    ),
                  ],
                ),
              ),
            if (widget.catalog.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Zatím žádné účesy.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              )
            else ...[
              if (groups.length > 1)
                SegmentedButton<String>(
                  segments: [
                    for (final g in groups)
                      ButtonSegment(value: g, label: Text(g)),
                  ],
                  selected: {_group},
                  onSelectionChanged: (v) => setState(() => _group = v.first),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Hledat účes',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    for (final section in sections) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text(
                          section,
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      for (final s in shown.where((s) => s.section == section))
                        ListTile(
                          leading: const Icon(
                            Icons.content_cut,
                            color: AppTheme.accent,
                          ),
                          title: Text(
                            s.label,
                            style: const TextStyle(color: AppTheme.textPrimary),
                          ),
                          subtitle: Text(
                            s.block,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              height: 1.3,
                            ),
                          ),
                          onTap: () => Navigator.of(
                            context,
                          ).pop((style: s.id, colour: _colour)),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
