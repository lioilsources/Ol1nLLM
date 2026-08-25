# Stylová matice

Jak každý nainstalovaný model vykreslí každý styl z `kStylePresets` — a jak se
liší flow „zachovej pózu" (repose) od img2img. Workflow **staví kód appky**
(`ComfyUIService.prepareForTest` → `_prepare`), takže matice měří to, co appka
opravdu posílá, ne jeho napodobeninu.

```bash
# všechno: reference z promptu → dump → generování → skóre → archy
./scripts/style_matrix/run.sh --ref-prompt "photo of a dancer, full body, plain background"

# vlastní reference, jen jedna flow a dva modely
./scripts/style_matrix/run.sh --ref foto.png --flows repose --models pony,juggernaut-xl

# ověřit sílu úpravy: img2img se zvýšeným denoise
./scripts/style_matrix/run.sh --ref foto.png --flows img2img --edit-denoise 0.9
```

Výstup jde do `build/style-matrix/<timestamp>/`: `wf/` (workflow), `img/`
(výsledky), `sheets/` (kontaktní archy), `score.json`.

## Přepínače

| přepínač | výchozí | co dělá |
|---|---|---|
| `--ref` / `--ref-prompt` | — | zdrojový obrázek, nebo prompt pro jeho vygenerování |
| `--subject` | baletka v extrémní póze | text, ke kterému se lepí bloky stylů |
| `--flows` | `repose,img2img` | i `txt2img` (bez reference) |
| `--models` | všechny nainstalované | čárkou oddělená id z `kImageModels` |
| `--styles` | všech 40 | čárkou oddělená id z `kStylePresets` |
| `--edit-denoise` | preset modelu | přebije `img2imgDenoise` (0.9 = „silná") |
| `--seed` | 777 | stejný pro celou matici, jinak se srovnává šum |
| `--step` | `all` | `dump` / `run` / `score` / `sheets` zvlášť |

Generování je **resumovatelné** — hotové obrázky se přeskakují, takže po
přerušení stačí `--step run --out <stejný adresář>`.

## Jak číst skóre

`score.json` a výpis dávají dvě čísla na dvojici flow × model:

- **spread** — průměrná vzdálenost barevných histogramů mezi styly. Nízká =
  model bloky stylů ignoruje. Kalibrace z měření 2026-08-25: repose vychází
  0.42–0.71, img2img 0.005–0.42.
- **reaction** — vzdálenost od `__baseline` (týž prompt bez bloku stylu, který
  se dumpuje automaticky). Tím se pozná „model na tenhle styl reaguje" od
  „model tohle maluje vždycky".

Pozor: obě metriky měří **barvu**, ne převzetí stylu. Slouží k předvýběru;
u plochých černobílých stylů falešně poplaší a rozhodnout musí pohled na
kontaktní arch. Postup i verdikty z posledního běhu jsou v
`docs/style-matrix.md`.
