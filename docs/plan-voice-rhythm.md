# Plán: Rytmus a frázování ve Voice Studiu (článek, který Eminem odrapuje)

Plán pro Claude Code (Opus). Dvě repa: engine a post-processing v **AiStack**
(`services/audio`, na SPARKu `~/deploy/AiStack`), appka v **Ol1nLLM** (tohle
repo). Cíl: ve Voice Studiu přibude volba **tempa (BPM)** a **stylu
frázování**, takže klonovaný hlas přečte libovolný text v daném rytmu —
od „zprávy" po rap. Zadání uživatele (2026-10-10): *„aby mi přečetl článek
například Eminem ve svém BPM a svým hlasem."*

Sepsáno 2026-10-10 po průzkumu obou rep a měření z 6. 10. Co je ověřené
proti kódu nebo serveru, nese **[V]**; co je jen z popisu třetí strany,
**[S]**; odhad **[I]**.

## 0. Co jde a co nejde — řekni to uživateli dřív, než se začne stavět

Žádný engine na serveru **neumí „flow"**: ani XTTS, ani Chatterbox nemají
vstup pro tempo, takt nebo přízvuk; Chatterbox ignoruje i `speed` **[V]**
(`services/audio/README.md`, pasti). Prozódii bere z reference — klon
Eminema má jeho barvu a trochu jeho dikce, ale prózu čte jako prózu.
„Eminem ve svém BPM" tedy vzniká jen dvěma cestami, a každá něco obětuje:

| cesta | co dá | co nedá | kde stojí |
|---|---|---|---|
| **A — mřížka** (TTS klon + zarovnání na takty) | hlas klonu, text doslova, pevné BPM, pauzy na koncích taktů | rapový flow (přízvuky na dobách, protažené slabiky); zní jako metronomická mluva | server umí 90 % — chybí jen zarovnání |
| **B — hudba** (ACE-Step s `lyrics` + `bpm` + prompt „rap") | skutečný rap, flow, beat pod ním | **hlas klonu** — zpívá, koho si ACE-Step vymyslí; text se smí zkrátit/přeskočit | server umí 100 % API, appka to **zakazuje** (`instrumental: true` napevno) |

Obě cesty se dají **složit**: beat z B (instrumentál na daném BPM, to
MusicStudio umí dnes) + hlas z A na jeho mřížce. To je realistický cíl
„Eminem čte článek": jeho hlas, jeho tempo, jeho beat, bez jeho flow.
Flow by vyžadovalo buď LoRA pro ACE-Step natrénovanou na acapellách
(ACE-Step LoRA trénink existuje **[S]**, identita zpěváka přes LoRA je
nezměřená), nebo konverzi hlasu (RVC) přes výstup B — nic z toho na serveru
není, obojí je samostatný projekt. **Neslibuj flow.**

K právům: server u každého klonu vyžaduje `rights ∈ own | consented |
licensed | synthetic` **[V]** (`tts/voicestore.py`). Pro hlas cizího umělce
žádná z hodnot neplatí; to je záměr návrhu serveru, ne díra. Appka na tom nic
nemění — rozhodnutí, co si uživatel nahraje do soukromé instance, je jeho.

## 1. Fáze 0 — změřit, než se postaví UI (den)

Repo má kulturu „měřit, ne odhadovat" (`docs/style-matrix.md`). Tři pokusy
přes `curl`/skript proti SPARKu, výstupy do `docs/voice-rhythm-bench.md`:

1. **Kolik snese time-stretch.** Vezmi větu z klonu (`chatterbox-cs`,
   `custom:smoke-ref` nebo lepší klon), protáhni/zkrať ffmpegem `atempo`
   na 0,8 / 0,9 / 1,1 / 1,25 / 1,5 a poslechni; totéž `rubberband`
   (`-af rubberband=tempo=`), pokud je ve ffmpeg image (`ffmpeg -filters |
   grep rubberband` **[I]**, pravděpodobně není → pip `pyrubberband` +
   binárka, nebo zůstat u atempo). Hledáš práh, pod kterým to nezní jako
   robot. Odhad **[I]**: ±15 % atempo projde, ±30 % ne. Práh je pak
   konstanta `MAX_STRETCH` a rozhoduje, kolik slabik smí být v taktu.
2. **Jak Chatterbox reaguje na tvar textu.** Tentýž odstavec (a) jako
   próza, (b) rozsekaný na řádky po ~8 slabikách s čárkou na konci, (c) s
   `exaggeration` 0,3 / 0,7 / 1,2 a `cfg_weight` 0,3 / 0,5. Měř délku
   výstupu (`duration`) a poslechni, jestli řádky vytvoří pauzy. Hypotéza
   **[I]**: čárky a konce řádků dělají pauzy (T3 čte interpunkci), takže
   „frázování" se dá z velké části napsat **do textu** dřív, než se sáhne na
   audio. Pokud ano, cesta A je hlavně textová transformace + lehké
   dorovnání.
3. **Umí ACE-Step odrapovat český text.** `POST /v1/audio/music
   {prompt: "hip hop, rap, male rapper, aggressive flow", lyrics: "[verse]\n…",
   bpm: 90, instrumental: false, duration_s: 40}` s jedním odstavcem
   česky a jedním anglicky; pak totéž přes `/vibe/generate mode=vibe` s
   referencí (rapová ukázka) — vibe drží barvu a tempo předlohy **[V]**
   (`NOTES.md`). Otázky: je text srozumitelný, drží se ho, je čeština vůbec
   podporovaná (ACE-Step uvádí 19 jazyků **[S]**, čeština v seznamu
   nejistá — ověř v `NOTES.md` / model card). Když čeština padne, cesta B
   je jen pro angličtinu a plán to má říct.

Teprve podle výsledků se rozhodne, kolik z §2 a §3 se staví. Když (2)
ukáže, že text sám dá 80 % efektu, §2.2 (zarovnání) může být druhá iterace.

## 2. Cesta A — mřížka (AiStack `services/audio`)

### 2.1 Kontrakt

Rozšíření `TtsRequest` **[V]** (`app/schemas.py`) o volitelné pole:

```
rhythm: {
  bpm: int (40–220),
  beats_per_bar: int = 4,
  style: "spoken" | "news" | "slam" | "rap" | "preacher",   # preset frázování
  beat: bool = false,          # podložit klikem / instrumentálem
  beat_sample_id?: str,        # instrumentál z MusicStudia (vibe sample) místo kliku
}
```

Bez `rhythm` se nic nemění (`null` = dnešní chování, stávající testy
`tests/test_tts.py` zůstávají). Odpověď jobu nese v `result` navíc
`rhythm: {bpm, bars, stretched_max, syllables_per_bar}` — appka to ukáže
jako „24 taktů, nejvíc protaženo 12 %".

Styl je **preset**, ne volné parametry (`app/tts/presets.py` má stejný
vzor pro hlasy):

| style | slabik/doba | pauza na konci taktu | Chatterbox `exaggeration` / `cfg_weight` | poznámka |
|---|---|---|---|---|
| spoken | 1,5 | 1 doba | 0,5 / 0,5 | výchozí, „čtení s tempem" |
| news | 2 | ½ doby | 0,3 / 0,6 | rovné, bez dramatu |
| slam | 1 | 1–2 doby | 0,9 / 0,4 | pomalé, dlouhé pauzy |
| rap | 2,5 | ½ doby | 1,0 / 0,3 | hustý text, krátké pauzy |
| preacher | 1,2 | 2 doby | 1,2 / 0,3 | pomalé, přehrané |

Čísla jsou **výchozí odhad [I]** — Fáze 0 (2) je kalibruje; tabulka musí
mít u každého řádku datum měření, jinak je to tabulka přání.

### 2.2 Zpracování (orchestrátor `app/main.py` + `app/postproc.py`)

Orchestrátor, ne GPU server: ffmpeg řetěz už je v `postproc.py` **[V]**
(trim, loudnorm, encode), GPU server má jen model.

1. **Slabiky.** `app/tts/syllables.py`: čeština = skupiny samohlásek +
   dvojhlásky `ou/au/eu` + slabikotvorné `r/l` mezi souhláskami (heuristika
   stačí, čeština je pravidelná); angličtina přes `pyphen` (hyphenace,
   ±10 %) nebo CMUdict, pokud se vejde do image. Test nad 50 slovy s ručně
   spočítanými slabikami v obou jazycích.
2. **Řez na takty.** Text → věty (stávající `_split_text` v GPU serveru je
   po znacích **[V]**, tohle je nový řez po slabikách) → takty tak, aby
   slabik na takt ≈ `slabik/doba × beats_per_bar`; řez na konci věty má
   přednost, pak čárka, pak slovo. Takt nikdy nekončí uprostřed slova.
3. **Syntéza po taktech.** Každý takt jeden request na engine (jako dnes
   `variations`), s presetovými `params`. Chatterbox načte model jednou,
   takt trvá ~1–2 s **[I]** (věta o 100 znacích 7–9 s **[V]**, takt má
   ~30 znaků).
4. **Zarovnání.** Cílová délka taktu `60/bpm × beats_per_bar` minus pauza
   presetu. `atempo = natural / target`, ořez na `[1/MAX_STRETCH,
   MAX_STRETCH]`; co se nevejde, se **neprotahuje víc**, ale přeteče do
   pauzy (lepší zkrácená pauza než robot). Výstup každého taktu doplnit
   tichem přesně na mřížku (`apad=whole_dur=`), spojit `concat`.
5. **Beat.** `beat: true` bez `beat_sample_id` = syntetický klik
   (`aevalsrc` nebo krátký sample, přízvuk na 1. dobu, −20 dB pod hlasem).
   S `beat_sample_id` = instrumentál z MusicStudia zarovnaný na stejné BPM
   (sample už prošel analýzou, jeho BPM je známé **[V]**); pokud BPM
   nesedí, `atempo` instrumentálu v mezích ±8 %, jinak 422 s větou.
   Mix `amix` s hlasem napřed, loudnorm až na mix.
6. Zbytek řetězu jako dnes (loudnorm −16 LUFS, 48 kHz, formát).

Pasti, které jsou už známé: TTS job má `AUDIO_TTS_TIMEOUT_S=600` **[V]** —
článek o 2 700 znacích = ~90 taktů × 2 s = 3 min, OK, ale delší text ořízni
na serveru (422 nad N taktů) místo timeoutu. Chatterbox má strop 1000
tokenů na request **[V]** — takt je hluboko pod ním.

### 2.3 Testy

`tests/test_tts.py` vzor: slabiky (cs/en), řez na takty (žádný takt přes
limit, věty neřezané uprostřed slova, prázdný text = 422), výpočet atempo
s ořezem, a jeden integrační test s fake enginem, který vrací ticho známé
délky — ověří, že výstup má přesně `bars × bar_s` sekund (±5 ms).

## 3. Cesta B — rap přes ACE-Step (jen pokud Fáze 0 (3) projde)

- Appka: `MusicDraft.toRequest` nastavuje `instrumental: true` napevno
  **[V]** (`lib/models/music_project.dart`) s dobrým důvodem (LM by opsal
  text předlohy). Nový režim je **jiná obrazovka/akce, ne přepínač
  v MusicStudiu**: ve Voice Studiu „Odrapovat" → `POST /v1/audio/music`
  s `lyrics` = text po odstavcích (`[verse]` tagy), `bpm` z chipu,
  `prompt` ze stylu („rap, hip hop, male vocal" / „spoken word, poetry")
  a volitelně `/vibe/generate` s referencí pro barvu.
- Délka: ACE-Step do 600 s **[V]** (`duration_s le=600`), ale LM drží text
  jen do jisté délky **[I]** — řezat po ~600 znacích na samostatné tracky a
  přehrát za sebou (`SpeechPlayer` už umí sekvenci souborů **[V]**).
- Identita: řekni v UI, že hlas je syntetický zpěvák, ne klon. Pokud
  uživatel bude chtít identitu, je to follow-up: LoRA pro ACE-Step
  (trénink na SPARKu v rag okně, dataset = acapelly) — samostatný plán.

## 4. Appka (Ol1nLLM)

### 4.1 Model a request

- `lib/models/voice.dart`: `enum PhrasingStyle {spoken, news, slam, rap,
  preacher}` s labelem a jednou větou popisu; `class SpeechRhythm {bpm,
  style, beat}`; `speechRequest(…, rhythm:)` přidá `rhythm` do body jen
  když není null. `speechFileName` **musí** zahrnout rytmus (jinak cache
  vrátí prozaickou verzi) — hash z `(voiceId, language, text, rhythm)`.
- `speechChunks` **[V]** řeže po větách na 120/400 znaků; s rytmem server
  zarovnává každý kus zvlášť, takže kus musí končit na konci taktu, aby
  navazování hrálo v tempu. Nejjednodušší: s `rhythm` posílat **celý text
  jedním requestem** (žádné kusy) a smířit se s čekáním, nebo kusy po
  odstavcích (server vždy dopadne na konec taktu). První iterace: jeden
  request + progress; kusy až podle pocitu. Mezera mezi soubory
  v `video_player` (viz CLAUDE.md, „navazování kusů") by v rytmu byla
  slyšet víc než v próze.

### 4.2 UI (`voice_studio_screen.dart`)

Sekce **„Rytmus"** mezi kartou zkoušky a „Moje hlasy":

- chip **Tempo**: vypnuto / BPM; bottom sheet se slidrem 60–180, polem a
  **tap-tempo** tlačítkem (průměr posledních 4 klepnutí — na telefonu
  přirozenější než číslo). „Z předlohy": pokud má uživatel v MusicStudiu
  analyzovanou ukázku (`MusicStudioState.projects` s `analysis.bpm`
  **[V]**), nabídnout její BPM jedním klepnutím — to je ta cesta
  k „Eminemovu BPM": nahrát jeho track do MusicStudia, nechat změřit.
- chip **Frázování**: preset; vedle něj jedna věta z presetu.
- chip **Beat**: vypnuto / klik / instrumentál z MusicStudia (výběr
  z projektů se staženým výstupem; posílá `beat_sample_id`).
- Nastavení je **session** (jako styl v Image Studiu), persistuje se v
  Hive boxu `voice_studio` vedle `persona_voices`; **nepatří k personě** —
  Dědeček nemá rapovat pokaždé. Reproduktor v chatu bere aktuální rytmus
  Voice Studia; pokud je zapnutý, ikona dostane tečku, aby bylo vidět, že
  čtení nebude obyčejné.
- Tlačítko „Odrapovat (ACE-Step)" jen když Fáze 0 (3) prošla; jinak
  vůbec nestavět.

Klávesnici schovávat u všeho, co není psaní (pravidlo repa, CLAUDE.md).

### 4.3 Testy

`test/voice_test.dart` rozšířit: `speechRequest` s rytmem a bez, cache
název se liší podle rytmu, `SpeechRhythm` round-trip JSON, widget test
sekce Rytmus na 375 pt. Fixture: zachycená odpověď jobu s `result.rhythm`
ze SPARKu (ne vymyšlená).

## 5. Pořadí a odhad

| krok | kde | odhad | závisí na |
|---|---|---|---|
| Fáze 0 (tři měření + zápis) | SPARK, curl | ½–1 den | enginy nahoře (okno comfy/llm) |
| §2.1–2.3 mřížka na serveru | AiStack | 1–2 dny | Fáze 0 (1), (2) |
| §4 appka (chipy, request, cache) | Ol1nLLM | 1 den | §2.1 kontrakt |
| beat z MusicStudia (§2.2 bod 5, §4.2) | obojí | ½ dne | mřížka |
| §3 rap přes ACE-Step | obojí | 1 den | Fáze 0 (3) — **jen pokud projde** |

Nasazení serveru jen v bezpečném okně (`PLAN-spark-scheduler.md` §3b),
GPU TTS běží v comfy a llm **[V]** (rag-schedule 2026-10-06), v rag ne.

## 6. Co plán záměrně nedělá

- **Přenos flow z reference** (rytmický vzor Eminema na nový text) — není
  model, který by to na serveru uměl; nejblíž je LoRA pro ACE-Step, a i ta
  dá styl, ne přesný flow. Zapsat jako follow-up, až bude cesta B změřená.
- **Přebásnění textu LLM** (rýmy, zkrácení) — uživatel chtěl *přečíst
  článek*, ne jeho verzi. Dá se přidat jako přepínač „přebásnit" přes
  qwen36 (alias `openclaw-default`, večer), ale je to jiná funkce.
- **SSML / přízvuky uvnitř slova** — Chatterbox ani XTTS je nečtou **[V]**.
