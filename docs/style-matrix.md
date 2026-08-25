# Stylová matice — 10 modelů × 25 stylů × 2 flow

Měření z 2026-08-25 na `comfyui.ol1n.com`: 600 renderů, stejný seed (777),
jedna společná referenční fotka (baletka na špičce, druhá noha u hlavy,
832×1216, juggernaut-xl). Prompt = subjekt + blok stylu z `kStylePresets`.
Prohlížecí stránka se všemi obrázky:
<https://claude.ai/code/artifact/212a2997-0722-473a-8a0f-dd1c4cee9025>

## Metriky

- **refSim** — korelace šedotónového náhledu s referencí. V img2img měří únik
  zdroje, v repose spíš *kompoziční invenci* (vysoká = model nic nevymyslel
  a vykreslil tutéž postavu na prázdném pozadí).
- **rozptyl stylů** — průměrná kosinová vzdálenost barevných histogramů mezi
  25 výstupy jednoho modelu. Nízká = model blok stylu ignoruje.

| model | refSim repose | refSim img2img | rozptyl repose | rozptyl img2img |
|---|---|---|---|---|
| pony | 0.813 | 0.956 | 0.607 | **0.011** |
| noobai-xl | 0.383 | 0.926 | 0.581 | 0.056 |
| animagine-xl | 0.454 | 0.904 | 0.710 | 0.098 |
| illustrious-xl | 0.508 | 0.919 | 0.665 | 0.106 |
| wai-illustrious | 0.165 | 0.834 | 0.415 | 0.175 |
| juggernaut-xl | 0.526 | 0.932 | 0.696 | 0.230 |
| atomix-pony-anime | 0.319 | 0.835 | 0.593 | 0.279 |
| juggernaut-xl-lightning | 0.526 | 0.921 | 0.674 | 0.421 |
| flux-manga | — | 0.421 | — | 0.596 |
| sd15 | — | 0.941 | — | **0.005** |

## Závěry, které se promítly do kódu

1. **img2img při presetovém denoise (~0.72) styl skoro nepustí** — rozptyl je
   5–50× nižší než v repose. Proto `_EditStrengthChip` a
   `ComfyUIService.setEditDenoise()`: „silná" = `kStyleEditDenoise` 0.9, kde
   styl projde a pózu dál drží auto-depth ControlNet (ověřeno end-to-end).
2. **Každý model má „výchozí scénu"**, do které stáhne všechno, co neumí —
   pony přemalovanou fotku, illustrious dekorativní rám, animagine zlaté
   protisvětlo, juggernaut fotku před tematickou stěnou. To je pro výběr
   podstatnější než výčet schopností, proto `ImageModelSpec.styleNote`.
3. **„img2img" jsou tři různé mechanismy**: SDXL (VAEEncode + 0.72 +
   auto-depth), sd15 (bez depth) a flux-manga (**FLUX Kontext, denoise 1.0**)
   — poslední jako jediný pustí styl, ale pózu si přeskládá.
4. **Snížení `_reposeDepthStrength` na 0.5 je kompromis, ne vylepšení**:
   u illustrious se rozdýchají ploché styly (ukiyo-e), ale sytým vyblednou
   palety; juggernaut nereaguje, pony jde opačně. Hodnota **zůstává 0.75**.

## Co projde napříč modely

Spolehlivě styly s jasným médiem a plochou — čínská tuš, ukiyo-e, Art Nouveau,
egyptská stěna, indická a perská miniatura, aboriginal. Nejhůř popisy, které
znamenají hlavně „kamenný reliéf v zemitých tónech" (asyrský, mezopotámský,
hebrejský, předislámský arabský) — u většiny modelů z nich je jen béžová stěna.
