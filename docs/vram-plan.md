# Snížení VRAM na ComfyUI serveru — runbook

Plán pro stroj s přístupem na `comfyui.ol1n.com` (SSH na hostitele + CF creds).
Fáze jsou seřazené podle poměru zisk/riziko; každá je samostatně nasaditelná
i vratná. **Fáze 1 je hotová v repu**, ostatní čekají na přístup k serveru.

Velikosti jsou z veřejných release souborů, ne měřené na našem stroji —
proto fáze 0.

## Fáze 0 — baseline (bez ní se nedá říct, jestli něco pomohlo)

```bash
curl -s -H "CF-Access-Client-Id: $CF_ID" -H "CF-Access-Client-Secret: $CF_SECRET" \
  https://comfyui.ol1n.com/system_stats | python3 -m json.tool
# na hostiteli, během běhu:
nvidia-smi --query-gpu=memory.used,memory.total --format=csv -l 1
```

Zapsat peak VRAM pro tyhle tři grafy zvlášť — mají úplně jiný profil:

| graf | co drží naráz |
|---|---|
| `flux_manga_txt2img` | flux unet + t5xxl + clip_l + ae |
| SDXL repose s `--face-identity=both` | checkpoint + union CN + InstantID CN + InstantID + FaceID (+LoRA) + DepthAnything |
| `flux_fill_inpaint_face` | **dva** flux unety + **dva** PuLID + Redux + sigclip + t5xxl + YOLOv8 |

Ten třetí je nejtěžší graf v repu. Jestli strop láme jenom on, fáze 1–2 problém
neřeší a je potřeba jít rovnou na „Druhý průchod face inpaintu" níž.

## Fáze 1 — flux-dev fp8 v manga txt2img ✅ HOTOVO

`assets/comfyui/flux_manga_txt2img.api.json`, `weight_dtype: default` →
`fp8_e4m3fn`. Úspora ~12 GB, žádný nový soubor — `UNETLoader` kvantizuje při
načtení.

Byla to odchylka, ne záměr: tentýž `flux1-dev.safetensors` se v
`flux_fill_inpaint_face.api.json` i v `tools/facebench/bench.py:124` už načítal
jako fp8. Manga txt2img byl jediné místo v plné přesnosti.

**Ověřit po nasazení**: jeden flux-manga txt2img běh a jeden repose z labu se
stejným seedem jako před změnou. fp8 na FLUX je běžná praxe a rozdíl bývá pod
šumem seedu, ale je to jediná fáze, která už je v repu, takže potvrzení chceme.

## Fáze 2 — t5xxl fp8 (~5 GB, nízké riziko)

T5 je textový encoder, ne difuzní váhy — kvantizace se projeví míň než na unetu.
Drží ho **všech pět** flux workflow, takže úspora je napříč vším.

1. Stáhnout `t5xxl_fp8_e4m3fn.safetensors` z HF `comfyanonymous/flux_text_encoders`
   (~4,9 GB proti ~9,8 GB) do `models/text_encoders/` — u starších ComfyUI
   `models/clip/`. Správnou složku pozná podle toho, kde leží stávající
   `t5xxl_fp16.safetensors`.
2. Ověřit, že ComfyUI soubor vidí, **než** se sáhne na repo:
   ```bash
   curl -s .../object_info/DualCLIPLoader | python3 -c \
     "import json,sys; print(json.load(sys.stdin)['DualCLIPLoader']['input']['required']['clip_name1'][0])"
   ```
3. V repu přepsat `clip_name1` v pěti souborech:
   `flux_manga_txt2img`, `flux_manga_img2img`, `flux_fill_inpaint`,
   `flux_fill_inpaint_ref`, `flux_fill_inpaint_face`.
4. `flutter test` (šablony čte `test/inpaint_prepare_test.dart`), pak lab běh.

**Rollback**: vrátit jméno v JSONech, fp16 soubor nechat na disku.

## Fáze 3 — GGUF (až když fp8 nestačí; pozor na skrytou past)

Q8_0 drží kvalitu blíž fp16 než fp8 při ~12,7 GB, Q6_K ~9,8 GB, Q5_K_M ~8,4 GB
(k-quanty kvantizují po blocích podle citlivosti vrstvy).

- custom node: `github.com/city96/ComfyUI-GGUF`
- unet: HF `city96/FLUX.1-dev-gguf` → `models/unet/`
- t5: HF `city96/t5-v1_1-xxl-encoder-gguf`

### Past: dvě místa v Dartu se rozhodují podle názvu třídy loaderu

GGUF mění `UNETLoader` → `UnetLoaderGGUF` a `DualCLIPLoader` → `DualCLIPLoaderGGUF`.
Tím se **tiše** rozbijou:

1. **`_isFluxGraph()`** (`lib/services/comfyui_service.dart:1541`) — hledá
   `class_type == 'UNETLoader'`. Řídí volbu depth ControlNetu (InstantX vs
   xinsir union), jeho sílu (0.55 vs 0.75), VAE hranu a **volbu identity**
   (PuLID vs InstantID/FaceID). Když vrátí false na flux grafu, dostane flux
   xinsir union ControlNet a InstantID — nesmysl, který skončí
   `execution_error` nebo tichým blábolem.
2. **`_findModelClipSources()`** (`:1858`) — hledá `UNETLoader` + `DualCLIPLoader`
   pro LoRA injekci. Bez úpravy se LoRA na GGUF grafu tiše neaplikuje.

Obojí rozšířit na obě jména a **přidat test** (`test/controlnet_injection_test.dart`
má flux větve — stačí duplikovat fixture s GGUF třídami a ověřit, že padne do
flux cesty). Bez toho testu se to při příštím refaktoru znovu rozbije.

## Fáze 4 — cache politika ComfyUI (bez kvantizace)

Při osmi SDXL checkpointech ve střídání může default cache stát víc než rozdíl
fp16/fp8. Zkusit `--cache-lru N` (drží N modelů) nebo `--cache-none`, změřit
kompromis proti času načítání. Tohle je jediná fáze, která nemění ani jeden
soubor v repu.

## Co nekvantizovat

- **VAE** (`ae.safetensors`, ~335 MB) — projeví se na barvách a detailu, úspora nula.
- **SDXL checkpointy** — fp16 je ~6,5–7 GB, fp8 ušetří ~3,5 GB, ale SDXL na fp8
  degraduje znatelně víc než FLUX (ten byl fp8 testovaný od začátku). A SDXL
  grafy nejsou to, co láme strop.
- **ControlNety, InstantID, IP-Adapter, PuLID** — adaptéry pracují s embeddingy,
  kde kvantizace bolí neúměrně, a jsou malé.
- **InsightFace** — běží na CPU (`_faceAnalysisProvider = 'CPU'`), VRAM nebere.

## Druhý průchod face inpaintu (jen když fáze 0 ukáže, že strop láme on)

`flux_fill_inpaint_face` drží dva flux unety naráz. Druhý průchod by mohl jet na
`flux1-fill-dev-fp8` místo `flux1-dev` a jeden unet by odpadl — **ale** tím padá
předpoklad, na kterém stojí naměřených 0.72 v `tools/facebench` (PuLID je
trénovaný na dev, ne na Fill; jeden průchod dal 0.48). Nesahat bez přeměření
benchmarkem.

Dva PuLID loadery jsou tam schválně — sdílené s prvním průchodem skončí po
samplingu offloadnuté na CPU a `ApplyPulidFlux` spadne na cuda/cpu mismatch.
Nesjednocovat.

## Akceptační kritérium

Na tohle máme nástroj — lab. Před každou fází a po ní stejný běh, **stejný seed**,
a porovnat obrázky vedle sebe:

```bash
make lab   # 127.0.0.1:8765
# nebo: lab run --models flux-manga --flow txt2img,repose --seed 777
```

Metriky labu měří barvu, ne kvalitu, takže slouží k předvýběru — rozhodnout musí
pohled. U face inpaintu navíc `tools/facebench` (baseline 0.72, žádný výsledek
pod 0.67).

## Drobnost k ověření mimochodem

`flux_manga_img2img.api.json` načítá `flux1-dev-kontext_fp8_scaled.safetensors`
s `weight_dtype: fp8_e4m3fn`, zatímco `tools/facebench/bench.py:161` tentýž
soubor načítá s `default`. „Scaled" fp8 soubory nesou vlastní scale tenzory a
načtení přes explicitní `fp8_e4m3fn` je může zahodit. Není to úspora paměti,
možná je to ale kvalita zadarmo. Ověřit srovnáním se stejným seedem.
