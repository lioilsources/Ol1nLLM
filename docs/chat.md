# Chat

Přesunuto z `CLAUDE.md`.


`ChatProvider` (Riverpod) drží **dva backendy** za společným rozhraním
`ChatBackend` (`lib/services/chat_backend.dart`, sealed `ChatEvent`:
`ChatDelta` → `ChatDone`). Konverzace je **strom** — `Conversation.messages`
je pool zpráv spojený přes `Message.parentId`, `activeLeafId` je špička živé
větve, `thread` je cesta root→leaf.

Persistence: Hive box **`conversations`**, jediný klíč `'all'`, celý seznam
jako JSON string.

| | vLLM (výchozí) | Knihovna (RAG) |
|---|---|---|
| Endpoint | `llm.ol1n.com/v1/chat/completions` | `chat.ol1n.com/chat/stream` |
| dart-define | `VLLM_URL` | `LIBRARY_CHAT_URL` |
| SSE formát | OpenAI (`choices[].delta`, `[DONE]`) | `{"delta":…}` → `{"done":true,…}` |
| Historie | stateless, klient posílá celý thread | **na serveru v RAM** (`session_id`, 10 tahů) |
| System prompt | persona `.md` z assetů | staví si server (`librarian_cs.md` + katalog) |
| Citace | ✗ | `sources[]` → `Message.sources` |
| CF Access | povinný (bez tokenů hodí výjimku) | volitelný (kvůli LAN vývoji) |
| Idle timeout | 120 s | 5 min (prefill 9–12k tokenů trvá minuty) |

**Kopírování odpovědi**: dlouhý stisk na bublině role (jakákoli persona,
knihovna, právník) zkopíruje celý text odpovědi do schránky (`MessageBubble`,
snackbar + haptika); během streamu ne. Markdown odpovědi proto **není
`selectable`** — `SelectableText` si long press bere pro výběr slova a gesto
by nikdy nedošlo. Odkazy se dál klepnutím otevírají.

**Routing přes personu**: `Persona.backend` v `assets/personas/index.json`
(`"backend": "library"` u Knihovníka 📚) určuje transport; `_backendFor()`
v provideru je jediné místo, kde se to rozhoduje. Persona bez `file` nemá
lokální prompt — server si ho staví sám a klientský by stejně zahodil.

**Míchané vlákno je zakázané**: RAG server vidí jen poslední zprávu a vLLM by
si četl RAG odpovědi jako vlastní výstup. `_pickPersona` proto při přechodu
mezi backendy nevolá per-turn override, ale `selectPersona()`, které zakládá
novou konverzaci.

**Právník ⚖️ (`"backend": "law"`)**: druhá RAG persona, stejný serverový kód
i SSE dialekt jako Knihovna — v appce je to **tatáž třída** `LibraryChatService`,
jen instance `LibraryChatService.law()` s `LAW_CHAT_URL` (výchozí
`https://pravnik.ol1n.com`, `top_k` 8, chybové texty `[právník] …`, hint na
unit `law-chat`); `_backendFor()` je switch přes `chatBackendIdFor()`. Přechod
knihovna ↔ právník je přechod mezi backendy, takže zakládá novou konverzaci
stejně jako u knihovny; `deleteConversation` proto backend pro `/reset` bere
z `_backendFor()` podle persony konverzace, ne natvrdo z knihovny. Server:
WorldLibraryProject, unit `law-chat.service` na SPARKu :8098, postup a korpus
v `docs/plan-pravnik.md`.

**Leads 📈 (`"backend": "leads"`)**: třetí RAG persona — firmy a instituce
z Registru smluv. Jiný serverový kód (LeadsRAG, unit `leadsd` na SPARKu :8099),
ale stejný SSE dialekt (navíc `: planning` / `: keepalive` komentáře, které
`parseSseLine` zahodí), takže v appce zase jen instance
`LibraryChatService.leads()` s `LEADS_CHAT_URL` (výchozí LAN
`http://SPARK_HOST:8099` — tunel zatím není, tedy jen `make debug`;
`top_k` 8, server vrací max 15 firem; chybové texty `[leads] …`). Zdroje jsou
`LibrarySource`-kompatibilní: `work` = IČO, `name_cs` = firma, `title` =
`IČO … · segment`, `group` = segment, `path` = číslo smlouvy, `excerpt` =
předmět smlouvy; navíc posílané `url` (odkaz na smlouvu) a `channels` model
ignoruje. Fixture `test/fixtures/leads_stream.sse`.

**Právník – smlouvy 📝 (`"backend": "law-agent"`)**: agent, který sepíše
smlouvu nebo dokument ze šablony (14 šablon — nájem bytu, kupní, dílo, NDA,
DPP/DPČ, plná moc, reklamace…). Tentýž server `law-chat` jako Právník ⚖️, ale
`POST /agent/chat` místo `/chat/stream`, služba `LawAgentService`
(`LAW_CHAT_URL`). **Samostatná persona, ne přepínač v chatu Právníka**: agent
má na serveru vlastní historii (jinou než RAG chat) a vlastní dokument
v Postgresu pod týmž `session_id`, takže přepínač uvnitř jedné konverzace by
byl právě to míchané vlákno, které je zakázané. Persona s jiným `backend` to
dostane zadarmo — výběr z chatu Právníka založí novou konverzaci, session je
per konverzace, fork/větev pošle `session_id: null` a stará jde na `/reset`
(smaže rozhovor agenta; rozepsaný dokument v PG zůstává do retence, 30 dní).

- **Kontrakt je jeden JSON na krok, ne stream.** Krok je smyčka modelu
  s nástroji na serveru (3–20 s s qwen36, Gemma pomaleji, timeout 6 min);
  výsledkem jsou data, ne text na postupné vykreslení. Služba ho vydá jako
  jeden `ChatDelta` (text agenta) + `ChatDone.agentStep` (`AgentStep`:
  `otazky`, `stav`, `dokument`, `checklist`, `upozorneni`, odmítnuté
  odpovědi). Snapshot jde na asistentskou zprávu (`Message.agentStep`, Hive),
  stejně jako `sources`.
- **Karty** (`AgentStepView`, `lib/widgets/agent_step_view.dart`): až tři
  otázky s inputem podle typu proměnné šablony (`money`/`int` číselná
  klávesnice, `date` text + kalendář, `enum` a `bool` čipy, `text` víc
  řádků). Interaktivní jen na špičce aktivní větve, starší kroky ukazují
  otázky jen pro čtení. Odeslání pošle uživatelskou zprávu s čitelným
  shrnutím a `Message.agentAnswers` → `odpovedi: [{id, otazka, hodnota}]`;
  **server je uloží sám** a převede typy („16 500 Kč" → 16500,
  „1. 10. 2026" → ISO), appka hodnoty nenormalizuje. Nad kartou je progress
  (`povinnych_vyplneno/povinnych`), porušené zákonné limity a důvody
  odmítnutých odpovědí. Kompletní vstup bez dokumentu nabídne „Sestavit
  dokument".
- **Výsledek**: karta dokumentu s náhledem, „Otevřít" (celá obrazovka,
  markdown, selectable), „Kopírovat" a „Sdílet" (`share_plus`) — obojí bere
  `AgentStep.shareText`, tj. dokument **i s kontrolním seznamem
  a upozorněními**, aby návrh necestoval bez nich. Pod kartou checklist ☐
  a upozornění ⚠️.
- **Okno 19–01**: alias LiteLLM `pravnik-agent` (Gemma na vyžádání, jinak
  qwen36) běží jen večer. Mimo okno server vrací 503 s větou pro člověka
  („Právník teď smlouvy nesepisuje… od 19:00 do 01:00…") a appka ji ukáže
  doslova, bez `HTTP 503` a bez hintu na systemctl.
- Testy `test/law_agent_test.dart` nad `test/fixtures/law_agent_step*.json`
  — **skutečné odpovědi** agenta s qwen36 (2026-10-05, sedm kroků nájemní
  smlouvy, kód serveru z větve `pravnik-agent-app`); `law_agent_503.json`
  zachycený není, je postavený z kódu serveru. Serverová strana:
  WorldLibraryProject `rag/agent/klient.py`, `docs/lawyer/AGENT.md`.

**Session vs. větvení** (`Conversation.canReuseRemoteSession`): server drží
jednu lineární frontu per `session_id`, appka strom. Session se recykluje jen
když `remoteLeafId == activeLeafId`, tj. serverová historie končí přesně
u zprávy, kterou prodlužujeme. Fork, přepnutí větve i regenerate tuhle rovnost
poruší → pošle se `session_id: null` (server vyrobí novou) a stará se uvolní
přes `POST /reset`. `forksOnNextSend` **nestačí** — skok na špičku
sourozenecké větve bez potomků by prošel a serverová paměť by tiše patřila
jiné větvi (pokryto testem).

**Zdroje jsou česky** (`LibrarySource`): server posílá u každého úryvku
`name_cs` (kurátorský český název díla — „Khuddaka-nikája — Otázky krále
Milindy" místo „Milindapañhapāḷi") a `excerpt_cs` (překlad úryvku, server
ho dělá souběžně s generováním odpovědi). `label` proto dává přednost
českému názvu a pozici v díle („část 12/340") přesouvá do podtitulku, ať
se neztratí. V detailu zdroje je nahoře překlad a **pod ním originál** —
úryvek je doklad, takže nepřeložený text musí zůstat po ruce, ale samotné
pálí nebo hebrejština jsou pro čtenáře nečitelné. Obě pole jsou nullable:
starší odpovědi v Hive je nemají a překlad může selhat.

Známá omezení: RAG stream nenese `finish_reason`, takže „Pokračuj"
(`pendingContinuation`) u knihovních odpovědí nefunguje; restart serveru
smaže paměť tiše. Selhání LLM na serveru přijde jako **200 OK s prázdným
streamem** (výjimka vznikne až po flushnutí hlaviček) — proto
`LibraryChatService` hlídá `deltas == 0` a hlásí to jako chybu.

`test/fixtures/library_stream.sse` jsou rámce zachycené doslova z běžícího
serveru přes tunel — testy tak drží skutečný formát, ne domněnku o něm.

## Knihovní RAG server (mimo tohle repo)

Server od 2. vlny (srpen 2026) neposílá do promptu celý katalog, ale nejdřív
**plánovač** (jeden LLM roundtrip) určí intent — `catalog | work_overview |
chapters | chapter_detail | read | content | mixed | smalltalk` — a podle něj
buď postaví výpis z Postgresu (tabulka děl s autorem, jazykem originálu,
poznámkou „v korpusu: překlad", tématy a anotací; přehled díla; seznam kapitol;
obsah kapitoly; čtení dál), nebo jede **hybridní retrieval** (vektor nad
pasážemi + vektor nad českými glosami + fulltext → Reciprocal Rank Fusion).
Finální SSE event nese navíc `intent`, `plan` (zkrácený) a payload `catalog` /
`work` / `chapters` / `chapter`; `sources[]` mají `work_id`, `chapter_id`,
`chapter_path`, `ref_start/ref_end`, `lang_original/lang_corpus`, `score`,
`channels`. Appka to zatím ignoruje (tolerantní parser) — katalogové odpovědi
přicházejí jako markdown tabulky, které `MarkdownBody` renderuje (GFM default;
styl pro tmavé UI je v `AppTheme.markdownStyle`).

`WorldLibraryProject/rag/server.py` na SPARKu :8090, systemd unit
`library-chat`, spouštěná s `--llm-url http://localhost:8080/v1` (LiteLLM na
`:4000` není z hostu vidět). Vektory drží ChromaDB na SPARKu (`library_chroma` :8007, od 2026-09-12; dřív JODA), aktuálně
**1 173 děl / 40 721 kapitol / 164 344 chunků** — 92 původních děl + 1 080
řeckých a latinských originálů z Perseu (anglické překlady vynechány; hebrejská
Bible vyhozena — z PDF lezlo mojibake). Katalog a fulltext drží
`library_postgres` :5433 na JODĚ (`deploy/joda` v repu WorldLibraryProject),
vektory `library_chroma` :8007 na SPARKu (`deploy/spark` tamtéž, kolekce `books_v2`
+ `books_gloss`).
Korpus jsou **originály**, ne překlady; to je smysl projektu, takže české
překlady děl do knihovny nepatří — překládá se až výstup. Za Cloudflare Access (self-hosted app, policy
`non_identity` na service tokenu sdíleném s `llm.ol1n.com`), takže appka
posílá tytéž `CF_ACCESS_*` hlavičky jako jinam.
