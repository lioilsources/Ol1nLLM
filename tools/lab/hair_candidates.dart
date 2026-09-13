// Hairstyle candidates for the lab, from the Tsumiki bench JSON
// (MangaPrompts tgbot/tools/bench/candidates/hairstyles.json, copied to
// candidates/hairstyles.json). Czech label from `cs`, like the app catalog.

import 'package:ol1n_llm/models/hair_mask.dart';
import 'package:ol1n_llm/models/hairstyle_preset.dart';

List<HairstylePreset> parseHairCandidates(List<dynamic> raw) => [
  for (final e in raw.cast<Map<String, dynamic>>())
    HairstylePreset(
      id: e['id'] as String,
      label: (e['cs'] as String?) ?? (e['label'] as String),
      group: e['group'] == 'Men' ? kHairGroupMen : kHairGroupWomen,
      section: e['section'] as String,
      block: e['block'] as String,
      shape: HairShape(
        length: HairLength.values.byName(
          (e['shape'] as Map)['length'] as String,
        ),
        bangs: HairBangs.values.byName((e['shape'] as Map)['bangs'] as String),
        updo: (e['shape'] as Map)['updo'] as bool,
      ),
    ),
];
