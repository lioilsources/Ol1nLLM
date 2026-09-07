# Changelog

Začíná u verze, ve které vzniklo učení z evalu. Starší releasy jsou jen
v git logu (`git log --oneline --grep '^Release'`) — dopisovat je zpětně by
znamenalo vymýšlet si, co v nich bylo.

Každý release od téhle chvíle uvádí **snapshot znalosti** a co se změnilo
v `lib/generated/learned.dart`. To je ta věta, kvůli které je release
chytřejší než minulý — a když ji nejde napsat z generovaného souboru, chybí
proveniences (viz I3 v `CLAUDE.md`).

## Nevydáno

### Přidáno

- **Učení z evalu** (`make learn`). `lab learn` čte `/api/eval` ve FINETUNE
  gallery, pustí na něj čistá pravidla (`tools/lab/decide.go`) a vygeneruje
  `lib/generated/learned.dart`. Appka z něj bere sílu LoRA, výchozí model pro
  „zachovej pózu", naměřená čísla v pickeru modelů a příznaky stylů —
  vždycky s fallbackem na dosavadní konstanty a vždycky s důvodem, který jde
  ukázat uživateli.
- **Osa medium** (`_MediumChip`, `lib/models/medium_preset.dart`). Šest bloků
  o tom, čím je obraz vykreslený, stavěných **před** prompt. Zatím
  experiment: appka nic nepředvolí, rozhodne A/B v galerii
  (`?group=medium`).
- `make check-learned` varuje, když je znalost starší než 30 dní; visí na něm
  `build-ios` i `build-android`. V draweru totéž jako řádka „Znalost: …".

### Znalost

- **Snapshot: žádný.** `lib/generated/learned.dart` je zatím prázdný overlay —
  appka jede na dosavadních konstantách a chová se bit-identicky jako předtím.
  Nasazená galerie je starší než eval harness, takže `lab learn` zatím nemá
  co číst; po nasazení (`git pull && docker compose up -d --build` na NAS)
  bude tenhle oddíl uvádět snapshot, počet hodnocení a co se v overlay hnulo.
