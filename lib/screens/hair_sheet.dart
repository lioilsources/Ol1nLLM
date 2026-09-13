import 'package:flutter/material.dart';

import '../models/hairstyle_preset.dart';
import '../core/constants/theme.dart';

/// Kadeřník picker: Ženy / Muži, sections, search without diacritics.
/// Pops with the chosen hairstyle id.
class HairSheet extends StatefulWidget {
  const HairSheet({super.key, this.catalog = kHairstyles});

  /// Injectable for tests.
  final List<HairstylePreset> catalog;

  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
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
                'Tvář a barva vlasů zůstanou, střih se změní. Nejlíp funguje '
                'čelní portrét s celými vlasy, bez čepice.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
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
                          onTap: () => Navigator.of(context).pop(s.id),
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
