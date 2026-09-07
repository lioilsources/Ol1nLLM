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

- **Snapshot 2026-09-07 · 2796 obrázků, z toho 4 hodnocené · 0 rozhodnutí,
  6 fallbacků.** Chování appky je proti minulému releasu **nezměněné** —
  nerozhodlo se nic, takže platí všechny dosavadní konstanty.

  Není to porucha, je to stav korpusu: 2792 z 2796 obrázků nikdo nehodnotil.
  Generovaný soubor to říká nahlas („žádné rameno nedosáhlo min=10") a
  vyjmenovává ramena i s jejich `n`, takže je vidět, čeho je potřeba víc.
  Tři LoRA mají po dvou ramenech síly a **nula** hodnocení na obou — tam
  stačí odhodnotit, nic negenerovat.

  Příští release bude chytřejší přesně o to, co se mezitím ohodnotí.
