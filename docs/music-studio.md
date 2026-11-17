# MusicStudio (vibe z předlohy)

Přesunuto z `CLAUDE.md`.


Ikona noty v Chatu. Uživatel vybere hudební ukázku (mp3/wav/m4a/…, i video —
server čte zvukovou stopu přes ffmpeg), server ji „poslechne" a appka ukáže,
co slyšel: caption (anglická próza, tvar, na kterém se DiT učil), žánr,
tempo, tóninu, takt. Uživatel to opraví, připíše přání a nechá složit 1–4
varianty. Server je AiStack `services/audio` (orchestrátor :8093 →
ACE-Step 1.5 turbo v kontejneru `audio-music`), měření a pasti jsou
v `AiStack/services/audio/NOTES.md`.

- **Dva režimy**: `vibe` = text2music s předlohou jako referencí (nová
  melodie, stejná barva a tempo), `groove` = cover předlohy (drží rytmus
  a formu, mění kabát; síla 0.5 — pod ní cover rytmus drží jen někdy, nad ní
  už nepřibývá, měřeno).
- **Dvoufázově a obojí job**: `POST /vibe/samples` (upload, sync) →
  `/vibe/analyze` → poll → `/vibe/generate` → poll → stáhnout `outputs`
  (mp3). Analýza je job, ne sync volání, protože sdílí frontu GPU a první
  požadavek po startu modelu čeká na váhy — přes Cloudflare by spadl na
  100 s. `sample_id` je hash bajtů, takže stejný soubor podruhé vrátí
  i hotovou analýzu.
- **Vždy instrumentál** (`MusicDraft.toRequest`): LM z předlohy přepíše i text
  písně a jeho zpívání by kopírovalo originál.
- **`lm_plan`** (přepínač „Rozvrhnout skladbu přes LM", výchozí vypnuto):
  5Hz LM naplánuje strukturu, ale varianta trvá ~4× déle a stejný seed pak
  dá pokaždé jinou skladbu (nano-vllm seed ignoruje).
- **Persistence**: Hive box `music_projects`, jeden klíč `all` (vzor
  `conversations`). Soubory v `applicationSupport/music_studio/`, v Hive
  jen relativní jména (`MusicFiles.baseDir`, stejný důvod jako
  `GenImage.baseDir`). Předloha se kopíruje — dočasný soubor pickeru zmizí.
- **Resume**: joby žijí v SQLite serveru (ne TTL jako gen-queue), takže
  `jobId` přežije i hodiny v pozadí; `_resume()` se napojí při startu,
  návratu do popředí i 5 s po výpadku sítě. Návrat z file pickeru na iOS
  taky hlásí `resumed` — `_starting` brání druhému uploadu téže předlohy.
  Server předlohu nezná (404) → appka ji nahraje znovu z lokální kopie.
- **Přehrávání** přes `video_player` (AVPlayer/ExoPlayer umí mp3), jedna
  sdílená instance `MusicPlayback` — druhá nativní audio knihovna by byla
  navíc. Výběr souboru `file_picker` ⇒ **iOS target 14.0**.
- **Nahrát z okolí** (`SampleRecorderSheet`, balíček `record`): místo
  souboru nahraje mikrofonem, co hraje kolem (rádio, repro), a pošle to
  stejnou cestou jako vybraný soubor (`addSample`, `.m4a` AAC 192k mono).
  Hlasové zpracování (AGC, echo cancel, potlačení šumu) je **vypnuté** —
  u hudby by pumpovalo hlasitost a sežralo nástroje. Zastavit jde až po 5 s
  a po 60 s se zastaví samo: to jsou meze serveru (`MIN_SOURCE_SECONDS`,
  `MAX_SRC_SECONDS` v `vibe/sample.py` — delší nahrávku stejně ořízne na
  nejhlasitější minutu). Před nahráváním se zastaví přehrávání, jinak by
  mikrofon slyšel vlastní výstup.
- **Chybová těla čte jako UTF-8** (`MusicService._text`): FastAPI posílá
  `application/json` bez charsetu a `Response.body` by dekódoval Latin-1 —
  české hlášky serveru by se rozsypaly.
- **Model běží jen přes den.** `audio-music` zvedá a shazuje plánovač režimů
  SPARKu (`rag-schedule.sh`: nahoře jen v profilu comfy, okna v AiStack
  `PLAN-spark-scheduler.md` §3). Mimo to server vibe
  analýzu i skládání odmítne hned `503` s větou pro člověka (upload projde)
  a appka ji ukáže bez `HTTP 503:` — analýza pak zůstane ve stavu chyby
  s „Znovu". Analýzu bez popisu od LM (LM odpověděl chybou) si server
  k předloze **neukládá**, jinak by ji upload téhož souboru vracel pořád;
  appka u ní nabídne „Poslechnout znovu".

`AUDIO_URL` přepne server (výchozí `https://llm.ol1n.com`; LAN
`http://SPARK_HOST:8093` jen s `make debug`, CF hlavičky jsou pak
volitelné). Veřejně jde `llm.ol1n.com/v1/audio/*` přes AiStack Go gateway
(`AUDIO_API_URL=http://audio:8093`), takže orchestrátor musí běžet z compose
(`make up-audio`) — ručně spuštěný kontejner nemá DNS alias `audio`
a gateway spadne na LiteLLM s `{"detail":"Not Found"}`.
