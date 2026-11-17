# Voice Studio (hlasy person, klonování)

Přesunuto z `CLAUDE.md`.


Ikona mluvící hlavy v Chatu. Tři věci na jedné obrazovce: **vyzkoušet** hlas
na větě, **naklonovat** hlas z krátké nahrávky (mikrofon nebo soubor) a určit,
**kterým hlasem mluví která persona**. Pod každou hotovou odpovědí v chatu je
pak reproduktor (`SpeakButton`), který ji přečte hlasem persony, jež ji dala
(`message.personaId ?? personaId` konverzace). Server je tentýž orchestrátor
jako u MusicStudia (AiStack `services/audio`, sekce TTS v jeho README),
`AUDIO_URL` ho přepíná stejně.

- **Hlasy žijí na serveru**, ne v telefonu — sdílí je všechno, co s audio
  službou mluví (MemeShorts). Appka drží jen mapu persona → hlas (Hive box
  `voice_studio`, klíč `persona_voices`) a cache už řečeného. Smazání hlasu
  ho proto smaže všem; dialog to říká. Persona bez přiřazení mluví
  `kDefaultVoiceId` (Piper Kasandra): jediný český hlas, který jede na CPU
  (běží, kdykoli běží služba) a má čistou licenci.
- **Klon je v seznamu jednou za každý klonující model** (stejné id
  `custom:…`, jiný engine) — `Voice.fromRows` řádky slučuje podle id a modely
  drží vedle sebe. Jméno, práva a délku seznam nenese; na ty je
  `GET /voices/{id}` zvlášť pro každý klon (`VoiceStudioState.stored`).
- **`commercial_only: false` je záměr** (`speechRequest()`): česky klonují jen
  XTTS-v2 (nekomerční) a chatterbox-cs (licence neověřená), takže s výchozím
  `true` by každý klon v jazyce person skončil 403. Appka je soukromý nástroj;
  licenci místo zákazu ukazuje u každého hlasu (`VoiceModel.licenseLabel`,
  u klonu všechny modely, které umí česky — který z nich server vybere, se
  rozhoduje per request).
- **Jazyk** (`speechLanguage()`): čeština, pokud ji hlas umí, jinak jazyk
  hlasu — anglický Kokoro přečte českou odpověď anglickými fonémy, což je
  pořád lepší než 422. Proto `speak()` bez načteného katalogu nejdřív načte
  katalog. Picker hlasu pro personu nabízí jen klony a hlasy, co česky umí.
- **Čte se text, ne markdown** (`speakableText()`): kód, odkazy, URL, oddělovač
  tabulky a značky pryč, konec řádku bez interpunkce je tečka, strop 5000
  znaků (limit serveru) se řeže na konci věty.
- **Čte se po částech** (`speechChunks()` → `SpeechPlayer`,
  `lib/providers/speech_player.dart`). Klonující engine generuje o něco
  pomaleji než reálný čas: odpověď Knihovníka o 2 736 znacích dala 192 s
  zvuku za 214 s (chatterbox-cs, 2026-10-06; Kasandra tutéž za 8 s), takže
  čekat na celý soubor znamenalo tři a půl minuty ticha. Text se proto řeže
  na koncích vět — první kus do 120 znaků, aby zvuk začal za pár vteřin,
  další do 400 — kusy se syntetizují **po jednom a v pořadí** (engine frontu
  stejně bere popořadě a zrušení pak zahodí nejvýš jeden kus) a každý hraje,
  jakmile je hotový a předchozí dohrál. Model dál nestíhá reálný čas, takže
  u dlouhé odpovědi jsou mezi kusy krátké pauzy (tlačítko ukazuje kolečko);
  padají na konec věty. Klepnutí při hraní pozastaví, při čekání zruší.
  Sekvenci řídí `SpeechPlayer` nad rozhraním `AudioOutput` (to z
  `MusicPlayback` potřebuje: `path`, `isPlaying`, `isCompleted`, `toggle`,
  `stop`), aby šla testovat bez nativního přehrávače; když přehrávač
  převezme hudba, čtení skončí a hudbu nechá být.
- **Jeden kus = jedno volání, žádný resume**: `VoiceService.speak()` odešle
  job, dopolluje ho přes `MusicService.follow()` a stáhne mp3 — persistovat
  jobId jako u hudby by byl kód bez užitku. Job, který server **přijal a pak
  spadl**, se po 15 s zkusí jednou znovu: tak vypadá restart kontejneru
  enginu uprostřed věty (2026-10-06, „varianta 0: chatterbox nedostupný:
  Server disconnected…"). Ta hláška je orchestrátor mluvící sám se sebou,
  proto ji appka nahrazuje větou „Hlas se nepodařilo přečíst, zkus to znovu."
  a originál nechává v logu (`VoiceServiceException.detail`). **Odmítnutí**
  (503, 403) se neopakuje — server v něm říká větou, proč hlas neběží, a
  čekání by tu odpověď jen zdrželo.
- **Cache**: soubor `applicationSupport/voice_studio/<sha1(hlas, jazyk, text)>.mp3`,
  zapisuje se přes `.part` + rename. Stejná věta stejným hlasem se syntetizuje
  jednou; souběžná klepnutí sdílí jeden request (`_inFlight`).
- **Nahrávka hlasu**: `SampleRecorderSheet` s vlastními mezemi 5–30 s
  (server chce 3 s řeči *po* ořezu ticha a bere nejvýš 30 s) a textem;
  hlasové zpracování zůstává vypnuté i tady — potlačení šumu a AGC mění
  barvu hlasu, kterou má klon převzít. `rights` + `source` jsou povinné
  (server je zapíše k hlasu a do manifestu každého jobu). Id hlasu na serveru
  je `voiceIdFor(jméno)`; obsazené jméno vrátí 409 a formulář chybu ukáže
  sám (snackbar by byl schovaný za sheetem, proto `createVoice()` hází).
- **Rytmus** (sekce „Rytmus", `SpeechRhythm` v `voice.dart`): tempo v BPM,
  styl frázování (`PhrasingStyle` — jména hodnot jsou id presetů serveru)
  a klik. Server pak text rozdělí na fráze a každou zarovná na doby
  (`rhythm` v `/v1/audio/tts`, AiStack `app/tts/rhythm.py`). **Není to
  flow** — zarovnává se začátek a délka fráze, ne slabiky, a UI to říká.
  Proč jen tohle (ACE-Step text nepřečte, tvar textu rytmus neudělá):
  stavový blok v `docs/plan-voice-rhythm.md`. Rytmus je **nastavení studia**
  (Hive `voice_studio`, klíč `rhythm`), ne persony ani hlasu, a platí pro
  každé čtení včetně reproduktoru v chatu — ten má pak ikonu ekvalizéru
  místo reproduktoru. Je součástí názvu souboru v cache (`speechFileName`)
  i klíče čtení (`SpeechPlayer.keyOf(…, variant)`), jinak by cache vrátila
  obyčejnou verzi. Tempo jde vyťukat (`tapTempo`: průměr posledních klepnutí,
  pauza přes 2,5 s začíná znovu) nebo převzít z ukázky změřené v Music
  Studiu — to je cesta k „jeho BPM". Kusy (`speechChunks`) zůstávají: každý
  končí na konci frázového slotu, takže další začne zase na době; mezera
  mezi soubory v přehrávači ale mřížku mezi kusy o zlomek doby posune.
  Starší server pole `rhythm` tiše ignoruje a přečte text obyčejně.
- **GPU enginy běží jen někdy.** Kokoro a Piper jsou CPU a jedou pořád; XTTS
  a Chatterbox nejsou v rozvrhu SPARKu (AiStack `CLAUDE.md`, sekce TTS). Když
  neběží, server odmítne `/tts` hned `503` s větou pro člověka a appka ji
  ukáže doslova (stejná cesta jako u MusicStudia, `MusicService.errorSnippet`).
- Přehrává sdílený `MusicPlayback`, takže řeč zastaví hudbu a naopak; čte
  vždy nejvýš jedna odpověď (`speechPlayerProvider`).
- Testy `test/voice_test.dart` nad `test/fixtures/audio_voices.json`,
  `audio_voice_stored.json`, `audio_tts_job.json` — odpovědi zachycené ze
  SPARKu 2026-10-06; text 403 i chyba spadlého jobu jsou doslova ze serveru,
  503 je vymyšlený (engine v tu chvíli běžel).
