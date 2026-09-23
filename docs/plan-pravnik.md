# Plán: Právník — RAG persona nad zákony ČR (na způsob Knihovníka)

Plán pro Claude Code (Opus). Práce se odehrává ve **dvou repech**: RAG server a
data v `WorldLibraryProject` (na SPARKu `~/deploy/WorldLibraryProject`, ingest
může běžet na M2 nebo na SPARKu), appka v `Ol1nLLM` (tohle repo). Cíl: v chatu
přibude role **⚖️ Právník**, která odpovídá z **účinných právních předpisů ČR**
(ústavní pořádek, občanský zákoník, trestní právo, právo obchodní, pracovní,
správní, daňové…) s **citací paragrafu a datem účinnosti znění**.

Sepsáno 2026-09-23 po průzkumu kódu obou rep a ověření zdrojů (co bylo skutečně
staženo/zavoláno, je označeno **[V]**; co je jen z popisu třetí strany, **[S]**;
odhad **[I]**). Čísla a URL v §2 a §7 platí k tomu dni.

> **Stav 2026-09-23 (implementováno téhož dne):** fáze A–B a D hotové, C
> připravená. Vrstva 1 = **53 předpisů, 13 458 §, 18 331 chunků, 19 031
> pasáží** v `law_v1`; `law-chat` běží na SPARKu na **portu 8098** (8091, se
> kterým plán počítal, drží gen-queue). Tři věci vyšly jinak, než plán čekal —
> všechny změřené (`rag/eval/eval_law.py`, 28 otázek):
> 1. **Jen vektor poráží hybrid.** ref-hit@8: `vec` 91 % (MRR 0,75), `vec+fts`
>    74 %, `fts` 35 %. Postgres `simple` bez českého stemmingu tahá do RRF šum;
>    §5.3 níže („fulltext má u práva velkou váhu") neplatí, `--channels vec`.
> 2. **Plánovač knihovny je pro zákony škodlivý** (překládá termíny do němčiny,
>    ~10 s na první token) → `--planner off --rewrite off`; katalogový intent
>    tím zatím není (follow-up: právní plánovač).
> 3. Stránky cache REST jsou **0-based** a Listina má normu celou v příloze
>    usnesení; část `novela` se zahazuje (§7 a `rag/README.md` „Právník").
> `cite` intent: 100 % ve všech režimech. Appka má zachycený stream
> (`test/fixtures/law_stream.sse`, `test/law_sse_parse_test.dart`) — zdroj se
> vykreslí jako „Zákon č. 262/2006 Sb., zákoník práce — § 51 odst. 1–3" bez
> změny `LibrarySource`. Datum znění jde do kontextu úryvku
> (`retriever.context_block`), protože bez něj si ho model vymýšlel.
> Zbývá: Access App + DNS + restart cloudflared (fáze C, `[ČLOVĚK]`; blok
> v `cloudflared/config.yml` je připravený), commity v obou repech, měření
> kvality odpovědí (§9.3 — dnes odpovídá `fallback`), právní plánovač pro
> katalogové otázky.

---

## 0. Souhrn — co se staví a co ne

**Nestaví se nový RAG server.** `rag/server.py` je celý řízený parametry
(`--prompt-file`, `--collection`, `--pg-dsn`, `--port`, `--channels`,
`--no-translate-excerpts`, …) a jeho datový kontrakt jsou tři JSONL soubory
(`works.jsonl`, `chapters.jsonl`, `books.jsonl`) se slugy
`{work_id}:{kapitola:04d}:{chunk:04d}`. Právník je proto:

1. **nový ingester** `rag/ingest_law.py` — e-Sbírka → tytéž tři JSONL,
2. **druhá instance** téhož serveru (`law-chat.service`, port **8098**, kolekce
   `law_v1`, vlastní Postgres databáze `law`, prompt `prompts/pravnik_cs.md`),
3. **jeden nový intent** `cite` (dotaz na konkrétní § → deterministický lookup,
   ne vektor) a pár záznamů v tabulce aliasů,
4. hostname `pravnik.ol1n.com` v témže Cloudflare tunelu (stejný service token),
5. v appce **persona s `backend: "law"`** a `LawChatService` = knihovní služba
   s jinou URL (~5 dotyků v kódu).

```
e-Sbírka (opendata.eselpoint.gov.cz, denní dump; sbr-cache REST pro vývoj)
        │  ingest_law.py  (M2 nebo SPARK)
        ▼
works.jsonl / chapters.jsonl / books.jsonl   ← STEJNÝ kontrakt jako knihy
        │  load_pg.py --pg-dsn …/law            embed_books.py --collection law_v1
        ▼                                       ▼
JODA  library_postgres :5433  db `law`     SPARK  library_chroma :8007  law_v1
        └────────────────┬──────────────────────┘
                         ▼
SPARK  server.py --port 8098 --prompt-file prompts/pravnik_cs.md   (law-chat.service)
        │  cloudflared: pravnik.ol1n.com → host.docker.internal:8098 (+ Access)
        ▼
Ol1nLLM  persona ⚖️ Právník (backend "law") → LawChatService (LAW_CHAT_URL)
```

Zásady, které plán dodržuje a Opus taky:

- **Kontrakt se nemění, plní se.** Nic v `load_pg.py`, `embed_books.py`,
  `retriever.py` ani v appce se kvůli Právníkovi nesmí rozbít pro Knihovnu.
  Změny v serveru jsou aditivní (nový intent, nový parametr) a knihovní
  instance jede dál beze změny konfigurace.
- **Čísla, ne dojmy.** Než se prohlásí „funguje", projde zlatý standard
  (`rag/eval/golden_law.jsonl`) — u práva je halucinovaný paragraf horší než
  žádná odpověď.
- **Není to právní poradenství** a appka i prompt to říkají nahlas.

---

## 1. Co už existuje (a kde) — přečti před psaním kódu

### 1.1 RAG server (`WorldLibraryProject/rag/`, SPARK)

| Co | Kde | Poznámka |
|---|---|---|
| FastAPI server, `/chat`, `/chat/stream` (SSE `{"delta"}`…`{"done":true,"sources","routed","session_id","model"}`), `/reset` | `rag/server.py` (~1 230 ř.); argparse ř. 1155–1227, `_prepare()` ř. 562–740, stream ř. 846–910 | paměť per `session_id` v RAM (`deque`, `--history-turns 10`) |
| Systémový prompt | `--prompt-file`, výchozí `rag/prompts/librarian_cs.md` | čte se jednou při startu |
| Vektorová DB | Chroma `library_chroma` :8007 na SPARKu (NVMe); kolekce `books_v2` (+ `books_gloss`) | `--collection`, `--gloss-collection` |
| Katalog + fulltext | Postgres `library_postgres` :5433 na JODA (3,8 GB RAM!) — tabulky `works`, `chapters`, `chunks` (`rag/sql/0001_init.sql`), FTS nad `text_fold` v konfiguraci `simple` | `--pg-dsn`; migrace `rag/pg_migrate.py` |
| Hybridní retrieval | `rag/retriever.py` (`Plan`, `Retriever`), `rag/hybrid.py` (RRF), `rag/pg_search.py` (`fts_orig`, `neighbors`, `hydrate`) | kanály `vec,gloss,fts,fts_cs` (`--channels`) |
| Směrování na dílo | `rag/retrieval.py` — `ALIASES` (folded kmeny) + `works.aliases` z registru; `route()`, `diversify()` (`--max-per-work 2`) | aliasy se hledají **od hranice slova jako kmen** — viz past v §5.1 |
| Plánovač intentů | `rag/planner.py` (`catalog`, `reading`, retrieve…), `rag/catalog.py` | `--planner auto\|on\|off` |
| Embedding | `rag/embeddings.py` — `intfloat/multilingual-e5-large`, lokálně na GB10 fp16 (28→95 pasáží/s); prefixy `passage:`/`query:` | index i dotaz **stejným modelem** |
| Ingest knih | `rag/ingest_books.py` (kontrakt v docstringu), `rag/chapters.py` (detektory kapitol), `rag/chunking.py` (1500 zn., překryv 150, min 150, `CHUNK_BY_LANG`) | chunk nikdy nekříží hranici kapitoly |
| Load/embed | `rag/load_pg.py` (per dílo v transakci, `text_sha` přežije), `rag/embed_books.py` (idempotentní, `PASSAGE_META` ř. 43–44, `sync_delete_stale`) | re-ingest po novele vymění jen ten zákon |
| Registr děl | `rag/registry/works.yaml` (name_cs, aliases, group, priority…), `registry/validate.py` | kurátorské, LLM nepřepisuje |
| Eval | `rag/eval/golden*.jsonl`, `eval_retrieval.py`, `eval_catalog.py` | měří retrieval bez LLM |
| Provoz | user unit `library-chat` (`ExecStart=…/.venv/bin/python3 server.py --llm-url http://localhost:8080/v1`), `rag/Makefile` (`serve`, `restart-chat`, `install-unit`, `pg-migrate`, `load-pg`, `pg-index`, `embed`, `eval`) | `rag/.env`: `PG_DSN`, `CHROMA_URL`, `COLLECTION` |
| Tunel | AiStack `cloudflared/config.yml` ř. 62–79: `chat.ol1n.com → host.docker.internal:8090` + `access` blok (AUD) | vzor pro `pravnik.ol1n.com` |
| Plánovací konvence toho repa | `PLAN-spark-chatbot.md` (fáze, ověření, `[ČLOVĚK]` kroky) | drž stejný tvar |

**LLM:** server volá `http://localhost:8080/v1` (Go gateway → LiteLLM, role
`translate` → `swarm-director` → `fallback`). Dne 23. 9. běžel z LLM jen
kontejner `fallback` (vLLM, 9,2 GiB) — `translate` ani `director` ne. Odpověď
nese `model` v posledním SSE eventu, takže je vždy vidět, kdo odpovídal.
**U práva rozhoduje kvalita modelu víc než u knihovny** (viz §9.3).

Paměť SPARKu (unified 121,7 GiB): druhá instance serveru = druhý e5 model,
**+~1,3 GiB GPU** (změřeno na knihovní instanci). Denní rozpočet to unese; noční
režim (`swarm-director` 93 GiB od 01:00) taky, ale ověř `free -g` po startu.

### 1.2 Appka (`Ol1nLLM`)

Vše backend-neutrální kromě tří míst. Mapa (ověřeno 23. 9.):

| Co | Kde |
|---|---|
| Persona registr; Knihovník je **bez `file`** (server si prompt staví) | `assets/personas/index.json` ř. 61–67 |
| `Persona` (`file?`, `backend?`) | `lib/models/persona.dart` |
| `persona_service.dart:41` — `file == null` ⇒ žádný lokální prompt | `lib/services/persona_service.dart` |
| `kChatBackendLibrary = 'library'`, `ChatBackend`, `ChatDone(sources, remoteSessionId, model)` | `lib/services/chat_backend.dart:4-7, 18-46, 51-78` |
| `_backendFor()` — ternár `library ? _library : _vllm`; služby jako **eager fieldy** bez konstruktoru | `lib/providers/chat_provider.dart:59-74` |
| ⚠ `deleteConversation` posílá `/reset` **natvrdo na `_library`** | `chat_provider.dart:146-151` |
| `sendMessage` — `canReuseRemoteSession`, `resetSession` osiřelé session | `chat_provider.dart:166-249, 266-296` |
| `dispose()` | `chat_provider.dart:478-484` |
| Přepnutí backendu = nová konverzace (porovnává **raw string** `backend`, takže `library`→`law` to řeší samo) | `lib/widgets/chat_input_bar.dart:358-376` |
| `isLibrary` → hint „Zeptej se knihovny…" | `chat_input_bar.dart:155-159, 207-210` |
| `LibraryChatService` — `LIBRARY_CHAT_URL` (výchozí `https://chat.ol1n.com`), CF hlavičky **volitelné**, `top_k` 5, idle timeout 5 min, `parseSseLine` (`@visibleForTesting`), `deltas == 0` ⇒ chyba | `lib/services/library_chat_service.dart:30-70, 72-89, 96-113, 146-196, 199-217` |
| `LibrarySource` — `work`, `name_cs`, `title`, `group`, `lang`, `path`, `distance`, `excerpt`, `excerpt_cs`; `label` (name_cs > title > work), `subtitle` = `(…)` z konce `title` · group · lang; **žádné `url`** | `lib/models/library_source.dart:7-92` |
| Zobrazení zdrojů (řádek + bottom sheet: label, subtitle, `readableExcerpt`, originál, `path` monospace) | `lib/widgets/source_list.dart`, `message_bubble.dart:143-157` |
| Session model (`remoteSessionId`, `remoteLeafId`, `canReuseRemoteSession`) | `lib/models/conversation.dart:23-34, 80-84` |
| Makefile `$(if $(LIBRARY_CHAT_URL),…)`; `.env.local` | `Makefile:5-14`; `CLAUDE.md` „Volitelné URL overrides" |
| Testy: SSE parser + zachycený stream `test/fixtures/library_stream.sse` (40 delt, `model == 'translate'`), session model | `test/library_sse_parse_test.dart`, `test/conversation_remote_session_test.dart` |

Appka **nezobrazuje `routed`** (CLAUDE.md to říká) — u práva by se hodil
(„odpověď ze zákona č. 89/2012 Sb., znění od 1. 1. 2026"), viz §8.4.

---

## 2. Zdroje dat — ověřeno

### 2.1 e-Sbírka (primární, jediný nutný zdroj)

Oficiální elektronická Sbírka zákonů (od 1. 1. 2024, zákon č. 222/2016 Sb.),
portál `https://e-sbirka.gov.cz` (`www.e-sbirka.cz` přesměrovává) **[V]**.
Konsolidovaná („úplná") znění s časovou osou, explicitní struktura (část › hlava
› díl › oddíl › pododdíl › § › odstavec › písmeno › bod), stabilní identifikátory.
Tři cesty k týmž datům:

| Cesta | URL | Auth | K čemu |
|---|---|---|---|
| **Otevřená data — denní dumpy** | `https://opendata.eselpoint.gov.cz/datove-sady-esbirka/` (Apache index, 45 sad × `.json.gz` + `.jsonld.gz`, generováno každou noc ~00:05–05:36) **[V]** | žádný | **plný korpus** (vrstvy 2–3), noční refresh |
| **Nekeyovaná cache REST** | `https://e-sbirka.gov.cz/sbr-cache/…` (i `…/sbr-externi/…`), tytéž cesty a JSON jako keyovaná API **[V]** | žádný; MV pro ni neposkytuje podporu **[S]**; komunitní klient hlásí WAF 403/429 při dávkách **[S]** — ~80 volání po 0,3 s prošlo bez throttlingu **[V]** | **vývoj a vrstva 1** (desítky zákonů) — per fragment je tu navíc `xhtml`, `zkracenaCitace`, `staleUrl` s kotvou |
| **Keyovaná veřejná API** | `https://api.e-sbirka.gov.cz`, hlavička `esel-api-access-key` **[V]**; bez klíče `401 NEPLATNY_API_KLIC` | registrace: DOCX `https://opendata.eselpoint.gov.cz/dokumentace/Zadost o registraci klienta verejneho REST API e-Sbirky a e-Legislativy.docx` datovou schránkou MV **6bnaawp**, předmět „e-Sbírka a e-Legislativa – registrace REST API", do 10 pracovních dnů **[V]** | až později: `GET /dokumenty-sbirky/zmeny-zneni` (inkrementální refresh) |
| SPARQL | `https://opendata.eselpoint.gov.cz/sparql` (Virtuoso; občas 502, opakovat) **[V]** | žádný | dotazy na katalog; dnes 92 614 aktů, 117 980 znění, 6,6 M fragmentů |

Dokumentace **[V]**: OpenAPI `https://opendata.eselpoint.gov.cz/dokumentace/Definicni_soubor_REST_API_e-Sbirka.zip`
(`daver.json`, 66 cest), příručka REST `…/dokumentace/Prirucka_REST_API_e-Sbirka.pdf`,
příručka open dat `…/dokumentace/Prirucka_OpenData_e-Sbirka.pdf`. Kontakt esel@spcss.cz.
NKOD: `https://data.gov.cz/datové-sady?dotaz=e-sbírka` (poskytovatel MV, IČO 00007064).

**Datové sady, které ingester potřebuje** (velikosti `.json.gz`, 23. 9.) **[V]**:

| Soubor | Velikost | Obsah |
|---|---|---|
| `002PravniAkt` | 5,2 MB | 46 046 aktů (sb 31 161, ul, sm, eu) + IRI všech znění |
| `006PravniAktMetadata` | 5,9 MB | per akt `metadata-datum-účinnosti-od/do`, `metadata-datum-zrušení`, podtyp (`ZAKON`, `ZAKONUST`, `VYHLASKA`, `NARIZENI`, …) |
| `003PravniAktZneniFragment` | **1,2 GB** | strom fragmentů per znění: `znění-fragment-eli`, `znění-fragment-předek`, `znění-fragment-hierarchie` („/2/1/6/2/") |
| `004PravniAktFragment` | **507 MB** | `fragment-text` (prostý text) + `cis-esb-typ-fragmentu-položka` |
| `001PravniAktZneni` | 170 MB | znění (datum účinnosti od/do, typ AKTUALNI/MINULE/BUDOUCI/VYHLASENE) |
| `013CiselnikTypFragmentu`, `017CiselnikPodtypuPravnichAktu` | malé | číselníky (170 typů fragmentů) |

⚠ Každý dump je **jeden JSON objekt** `{"položky":[…]}`, ne NDJSON — parsovat
streamově (`ijson`), jinak 1,2 GB gz ≈ desítky GB v RAM (kritika Lupa.cz
8. 1. 2024 **[V]**). `002`+`006` se vejdou do paměti, `003`/`004` ne.

**Cache REST — ověřené volání** (staleUrl v cestě plně percent-encoded) **[V]**:

```
GET /sbr-cache/dokumenty-sbirky/%2Fsb%2F2012%2F89                 → metadata aktuálního znění (staleUrl, eli, typZneni,
                                                                     datumUcinnostiZneniOd/Do, novely[], uplnaCitace, dokumentBaseId=48945)
GET …/%2Fsb%2F2012%2F89/historie                                   → všech 20 znění NOZ (cisloZneni, typZneni, data, novely)
GET …/%2Fsb%2F2012%2F89%2F2026-01-01/obsah                         → obsah: 5 částí, rozsah „§ 1 — § 654", fragmentId, maPotomky
GET …/%2Fsb%2F2012%2F89%2F2026-01-01/fragmenty?cisloStranky=1       → 1 000 fragmentů/stránka (parametr POVINNÝ, bez něj 400);
                                                                     NOZ = 10 472 fragmentů = 11 stránek
GET …/%2Fsb%2F2012%2F89/odkazy-ke-stazeni                           → dokumentId PDF/DOCX informativního a PDF právně závazného znění
GET /sbr-cache/castky/sb/2012/33                                    → overeneZneniOdkazPdf.dokumentId → /sbr-externi/stahni/overena-zneni/{id}
GET /sbr-cache/rejstriky/UCINNE_PRAVNI_AKTY?pocet=30                → jen posledních 7 dní (NENÍ úplný rejstřík; pocet<30 → 400)
```

Fragment: `id, eli, staleUrl (s kotvou), kodTypuFragmentu, hloubka, xhtml,
zkracenaCitace ("§ 2079 odst. 1 zákona č. 89/2012 Sb."), uplnaCitace, jeUcinny,
odkazyZFragmentu[], maNovelizace/maDerogace/maNalezyUS…`. Ukázka `xhtml`:
`<var>(1)</var> <czechvoc-termin koncept-id="279703">Kupní smlouvou</czechvoc-termin> se prodávající zavazuje…`.
Formáty souborů jen `DOCX, PDF, ZIP`; „XML" v `odkazXml` je editorský formát
e-Legislativy, ne text **[V]**.

**Identifikátory** **[V]**:

- Stálá URL `/{sbirka}/{rok}/{cislo}[/{rrrr-mm-dd}]#{kotva}`; `sbirka` ∈ `sb, sm, ul, eu`;
  bez data = aktuální znění; **libovolné datum se normalizuje na začátek platného
  znění** (`/sb/2012/89/2020-05-01` → `/sb/2012/89/2018-12-01`); `0000-00-00` =
  vyhlášené znění. Kotvy `#par_2079-odst_2-pism_a-bod_1`, `#cl_10`,
  `#cast_1-hlava_2-dil_1`, `#priloha_x`; duplicity `#par_10:2`.
- ELI `/eli/cz/sb/2012/89/2026-01-01/dokument/norma/cast_4/hlava_2/dil_1/oddil_2/pododdil_1/par_2079/odst_2`
  — celá hierarchie v cestě. **Použij ELI/staleUrl jako stabilní id**, ne
  `fragmentId`: MV varuje, že identifikátory fragmentů se mohou měnit (uvedeno
  do 15. 1. 2026; NKOD píše 2027 — nesoulad, ber za nestabilní).

**Typy fragmentů, na kterých se řeže** (z číselníku 170 typů) **[V]**:
`Cast, Hlava, Dil, Oddil, Pododdil` (hierarchie), `Paragraf`, `Clanek`
(ústavní předpisy, smlouvy), `Odstavec_Dc`, `Pismeno_Lb`, `Bod_Dd`,
`Nadpis_nad`, `Nadpis_pod`, `PPC` (poznámka pod čarou), `Priloha*`,
`Virtual_Norma/Prefix/Postfix`.

**Pasti** **[V]**: (a) konsolidace zaostává — akty mimo e-Legislativu se
digitalizují typicky do **15 pracovních dnů**, složité novely přes 30 dnů ⇒
vždy říkat „znění účinné od …, staženo …"; (b) `rejstriky/UCINNE_PRAVNI_AKTY`
není úplný seznam — katalog se staví z `006`; (c) cache bez podpory — backoff
+ cache na disk.

**Licence** **[V]**: § 3 písm. a) zákona č. 121/2000 Sb.: právní předpis i
rozhodnutí jsou **úřední dílo bez autorskoprávní ochrany**. NKOD podmínky
každé e-Sbírka distribuce: „neobsahuje autorská díla", není chráněnou databází,
neobsahuje osobní údaje, `skos:narrowMatch` CC0. Bez omezení.

### 2.2 Co nepoužít

- **zakonyprolidi.cz** — podmínky zakazují „masivní nebo dávkové stahování",
  API „typicky na komerční bázi", `robots.txt` blokuje `/api/` **[V]**. Texty
  jsou volné, jejich *databáze* si nárokuje ochranu pořizovatele. Není důvod
  tam chodit — e-Sbírka má totéž oficiálně.
- **aplikace.mvcr.cz/sbirka-zakonu** — aplikace zmizela (`mv.gov.cz/sbirka-zakonu/`
  → 404) **[V]**; stejnopisy jsou PDF, ne text, nekonsolidované. Náhrada:
  e-Sbírka `castky` / `odkazy-ke-stazeni`.
- **CzCDC 1.0** (LINDAT, 237 k rozhodnutí NS/NSS/ÚS 1993–2018) — **CC BY-NC**
  **[V]**, nepatří do produktu.

### 2.3 Volitelné vrstvy (ne v MVP)

| Zdroj | Přístup | Verdikt |
|---|---|---|
| **Ministerstvo spravedlnosti — rozhodnutí okresních/krajských/vrchních soudů** | `https://rozhodnuti.justice.cz/api/opendata/{rok}/{mesic}/{den}?page=N` (100/str.) → položky `ecli, soud, jednaciCislo, klicovaSlova, zminenaUstanoveni[], odkaz`; `odkaz` = `…/api/finaldoc/{uuid}` → `header, verdictText, justificationText, metadata.regulations[]` (§ + zákon!) **[V]**; bez auth, bez uvedených limitů; 605 159 rozhodnutí 2020–2026; OpenAPI `github.com/MSPotevrenadata/soudnirozhonduti_api`; **obsahuje jména soudců (osobní údaje)** | nejlepší strojově čitelná judikatura; jen nižší soudy; vlastní kolekce `caselaw_v1`, filtr přes `regulations` na zákony vrstvy 1 |
| ÚS NALUS | jen scrape: `https://nalus.usoud.cz/Search/GetText.aspx?sz=Pl-24-10_1` **[V]**; podmínka: citovat zdroj, uvést neautentičnost | později |
| NS `rozhodnuti.nsoud.cz`, NSS `vyhledavac.nssoud.cz` | bez API; NSS „open data" xlsx = jen metadata **[V]** | později |
| Právo EU česky | Cellar: `http://publications.europa.eu/resource/celex/{CELEX}` s `Accept: application/xhtml+xml`, `Accept-Language: cs` (konsolidace = sektor 0, např. `02016R0679-20160504`); SPARQL `https://publications.europa.eu/webapi/rdf/sparql`; CC BY 4.0 **[V]**; datadump chce EU Login | vrstva 5; e-Sbírka má vlastní `eu` sbírku (`/eurlex-dokumenty-sbirky/{celex}`, neotestováno) |
| Komunitní `github.com/flatiocom/czech-law-md` (31 161 aktů jako Markdown, týdně) | hotové markdowny **[V README]** | zkratka pro vrstvu 2, ale bez záruky struktury — preferuj oficiální dump |

---

## 3. Korpus po vrstvách

Stav e-Sbírky 23. 9. 2026 (z `006PravniAktMetadata`) **[V]**: v účinnosti
**3 275 zákonů + 41 ústavních zákonů, 4 418 vyhlášek, 1 543 nařízení vlády**
(= 9 377 předpisů); z účinných zákonů je ~2 113 novel („kterým se mění…"),
věcných zákonů tedy ~1 200 **[I]**. Počty § v aktuálním znění (včetně vložených
§ 2a a rušených stubů) **[V]**: OZ 89/2012 **3 106** (10 472 fragmentů), TZ 40/2009
467, ZP 262/2006 430, OSŘ 99/1963 597, TŘ 141/1961 574, ZOK 90/2012 791, SŘ
500/2004 183, DŘ 280/2009 311, Ústava 1/1993 114 čl., Listina 2/1993 44 čl.

| Vrstva | Obsah | Odhad chunků | Embedding (95 p/s) | Kdy |
|---|---|---|---|---|
| **1 — jádro (MVP)** | ~50 kurátorských zákonů (seznam níže) | ~35–45 k | ~8 min | fáze A–D |
| 2 — všechny účinné zákony a ústavní zákony | 3 316 aktů; bez čistých novel ~1 200 | ~200–250 k **[I]** | ~45 min | po evalu vrstvy 1 |
| 3 — vyhlášky + nařízení vlády | 5 961 aktů | velké, nízká hodnota per § | later, jen na vyžádání |
| 4 — judikatura MSp | 605 k rozhodnutí | vlastní kolekce | po vrstvě 2 |
| 5 — právo EU (cs) | Cellar | vlastní kolekce | mimo tento plán |

**Vrstva 1 — `rag/registry/law_tier1.yaml`** (kurátorský registr; `group` =
odvětví, na které se dá směrovat a podle kterého se dělá katalog):

- `ustavni`: 1/1993 Sb. Ústava; 2/1993 Sb. Listina; 182/1993 Sb. o Ústavním soudu;
  110/1998 Sb. o bezpečnosti ČR; 90/1995 Sb. jednací řád PS; 107/1999 Sb. jednací řád Senátu; 247/1995 Sb. o volbách do Parlamentu
- `obcanske`: 89/2012 Sb. občanský zákoník; 90/2012 Sb. ZOK; 91/2012 Sb. ZMPS;
  99/1963 Sb. OSŘ; 292/2013 Sb. ZŘS; 120/2001 Sb. exekuční řád; 182/2006 Sb. insolvenční zákon;
  634/1992 Sb. o ochraně spotřebitele; 256/2013 Sb. katastrální; 121/2000 Sb. autorský; 441/2003 Sb. o ochranných známkách
- `trestni`: 40/2009 Sb. TZ; 141/1961 Sb. TŘ; 418/2011 Sb. TOPO; 218/2003 Sb. o soudnictví ve věcech mládeže; 45/2013 Sb. o obětech
- `pracovni_socialni`: 262/2006 Sb. ZP; 435/2004 Sb. o zaměstnanosti; 187/2006 Sb. nemocenské; 155/1995 Sb. důchodové; 589/1992 Sb. pojistné na SZ; 592/1992 Sb. pojistné na VZP; 48/1997 Sb. o veřejném zdravotním pojištění; 251/2005 Sb. inspekce práce
- `spravni`: 500/2004 Sb. správní řád; 150/2002 Sb. SŘS; 250/2016 Sb. o odpovědnosti za přestupky; 251/2016 Sb. o některých přestupcích; 106/1999 Sb. o svobodném přístupu k informacím; 110/2019 Sb. o zpracování osobních údajů; 128/2000 Sb. o obcích; 361/2000 Sb. o silničním provozu; 283/2021 Sb. stavební zákon; 326/1999 Sb. o pobytu cizinců; 134/2016 Sb. o zadávání veřejných zakázek
- `obchodni`: 455/1991 Sb. živnostenský; 304/2013 Sb. o veřejných rejstřících; 563/1991 Sb. o účetnictví; 143/2001 Sb. o ochraně hospodářské soutěže; 6/1993 Sb. o ČNB; 21/1992 Sb. o bankách
- `danove`: 280/2009 Sb. daňový řád; 586/1992 Sb. o daních z příjmů; 235/2004 Sb. o DPH; 338/1992 Sb. o dani z nemovitých věcí; 353/2003 Sb. spotřební daně
- `justice`: 6/2002 Sb. o soudech a soudcích; 85/1996 Sb. o advokacii; 358/1992 Sb. notářský řád; 283/1993 Sb. o státním zastupitelství; 292/2013 Sb. (viz výš)

Seznam je návrh — Opus ho před ingestem projde proti `006` (existence, podtyp
`ZAKON`/`ZAKONUST`, účinnost) a doplní, co v `002` chybí nebo má jiné číslo.
Každá položka nese `name_cs` (plný název), `short` („občanský zákoník"),
`aliases` (kmeny pro `route()`, viz §5.1), `abbr` (celé tokeny: `OZ`, `NOZ`,
`ZOK`, `ZP`, `TZ`, `TŘ`, `OSŘ`, `SŘ`, `DŘ`, `SŘS`, `IZ`, `LZPS`), `group`,
`priority: 1`.

---

## 4. Datový model — mapování zákona na `works / chapters / chunks`

Schéma se **nemění**; plní se takto:

| Tabulka / pole | Hodnota pro zákon | Příklad |
|---|---|---|
| `works.id` | `cz.sb.{rok}.{cislo}` | `cz.sb.2012.89` |
| `works.title` | číslo předpisu | `89/2012 Sb.` |
| `works.name_cs` | plná citace | `zákon č. 89/2012 Sb., občanský zákoník` |
| `works.author` | `Parlament ČR` (vyhláška: ministerstvo) | |
| `works.group` / `subgroup` | odvětví z registru / podtyp e-Sbírky | `obcanske` / `ZAKON` |
| `works.lang_original` = `lang_corpus` | `cs` | `is_translation` = false |
| `works.form` | `zakonik` (hodnota z enumu v komentáři schématu) | |
| `works.period` | účinnost aktu | `účinný od 1. 1. 2014` |
| `works.edition` | verze znění + datum stažení | `úplné znění účinné od 2026-01-01 (e-Sbírka, staženo 2026-09-23)` |
| `works.urn` | ELI aktu | `/eli/cz/sb/2012/89` |
| `works.source_path` | stálá URL znění | `/sb/2012/89/2026-01-01` |
| `works.aliases` | kmeny z registru | `["obcansk zakonik", "obcanskeho zakoniku", "noz", …]` |
| `works.priority` | 1 (vrstva 1), 2 (vrstva 2), 3 (novely, zrušené stubs) | |
| `chapters` | **celá hierarchie**: `Cast`=1, `Hlava`=2, `Dil`=3, `Oddil`=4, `Pododdil`=5, `Paragraf`/`Clanek`=6, `Priloha`=1 | `ref` = `§ 2079` / `čl. 10` / `Část čtvrtá`, `heading` = nadpis (z `Nadpis_nad`/`Nadpis_pod`), `path` = `Část čtvrtá › Hlava II › Díl 1 › Oddíl 2 › Pododdíl 1 › § 2079 Kupní smlouva` |
| `chapters.id` | `{work_id}:{ordinal:04d}` — ordinal = pořadí v dokumentu napříč úrovněmi | OZ: 3 106 § + ~250 uzlů < 9 999 ✓ (největší akt) |
| `chunks` | **text § (leaf)**; jeden chunk, když ≤ 1 500 zn.; jinak dělení **po odstavcích** (`(n)` markery) do skupin ≤ 1 500 zn., každý kus s prefixem `§ 2079 Kupní smlouva\n` | `id` `cz.sb.2012.89:1234:0001`, `ref_start`/`ref_end` = `§ 2079 odst. 1` / `§ 2079 odst. 3`, `seq` napříč aktem |
| `chunks.text` | prostý text: `(1) Kupní smlouvou se prodávající zavazuje…` (odstavce oddělené `\n`, písmena `a) …`, body `1. …`); `<czechvoc-termin>` odstraněn (text zůstává), `<var>` → text; PPC (poznámky pod čarou) **připojit na konec § jako `[pozn. 1] …`** jen když ≤ 300 zn., jinak vynechat | |
| `chunks.lang` | `cs` — do `CHUNK_BY_LANG` přidat `"cs": 1500` (~0,3 tok/zn. ⇒ ~450 tokenů, jako `en`/`de`) | |
| Chroma `law_v1` | `PASSAGE_META` beze změny (`work`, `work_id`, `group`, `chapter_id`, `chapter_path`, `seq`, `text_sha`, `source`, `path`, `title`, `chunk_index`); `title` = `"89/2012 Sb. (§ 2079 odst. 1)"` — viz §8.2 proč | |

Co **se do chunků nedává**: zrušená ustanovení (`(zrušen)`) — chunk vzniká,
ale s `text` = `§ 123 (zrušen)` a `priority` se neřeší (jsou krátké, nikdy
nevyhrají); `Virtual_Prefix/Postfix` (preambule, podpisy) — jen jako kapitola
level 1 „(úvod)"/„(závěr)", ať čl. 1 Ústavy neztratí preambuli.

Přílohy: `Priloha*` = kapitola level 1 `Příloha č. N`, text přes generický
`chunk_text` (tabulky jsou prostý text, e5 je zvládne jen přibližně — nevadí,
přílohy jsou zřídka to, na co se lidé ptají).

**Idempotence a refresh**: `load_pg.py --work cz.sb.2012.89 --replace-work`
vymění chunky jednoho aktu v transakci; `embed_books.py` přeskočí nezměněné
`text_sha` a `sync_delete_stale` smaže id, která zmizela. Re-ingest po novele
tak stojí jen ten zákon. `works.edition` říká, k jakému datu znění je.

---

## 5. Retrieval pro právo

### 5.1 Směrování na zákon (aliasy)

`route()` v `retrieval.py` hledá folded **kmeny od hranice slova**. Pro zákony:

- Kmeny do `works.aliases` (přes `law_tier1.yaml` → `works.jsonl`):
  `obcansk zakonik`, `obcanskem zakoniku`, `obcanskeho zakoniku`, `trestn zakonik`,
  `trestniho zakoniku`, `zakonik prace`, `zakoniku prace`, `obcansk soudni rad`,
  `trestni rad`, `spravni rad`, `danov rad`, `insolvencn`, `zivnostensk`,
  `listin zakladnich prav`, `ustav ceske republiky` (ne holé `ustav` — chytá
  „ústava" i „ústavní soud"), `89/2012`, `40/2009`, `262/2006`, … (čísla jsou
  bezpečné kmeny).
- ⚠ **Zkratky (`OZ`, `ZP`, `TZ`, `SŘ`, `DŘ`) do stem-aliasů nedávat**: kmen `zp`
  od hranice slova chytí „zpět", „zpráva"; `oz` chytí „označení". Zkratky řeší
  parser citací v §5.2 jako **celé tokeny** (`\bOZ\b`, bez ohledu na velikost
  písmen jen u ≥ 3 znaků; `oz`/`zp` jen velkými).
- `--max-per-work`: knihovní 2 je pro právo špatně — otázka na nájem má 5 § v OZ.
  Nastavit **6** (nebo 0 = vypnuto) u law instance; ověřit v evalu.

### 5.2 Nový intent `cite` — deterministický lookup paragrafu

Nejcennější právnická funkce: „Co říká § 2079 občanského zákoníku?", „§ 51
odst. 1 ZP", „čl. 10 Listiny", „§ 29 trestního zákoníku" ⇒ **bez vektoru**.

- Regex (folded): `§\s*(\d+[a-z]?)(?:\s*odst\.\s*(\d+))?(?:\s*písm\.\s*([a-z]))?(?:\s*bod\s*(\d+))?`
  a `čl\.?\s*(\d+[a-z]?)`, plus identifikace aktu: číslo (`89/2012`), kmen z
  aliasů, nebo zkratka (celý token). Bez aktu: hledat `ref` ve všech aktech
  vrstvy 1 s prioritou 1; víc než jeden zásah ⇒ **zeptat se zpět** (vyjmenovat
  kandidáty s nadpisy) místo hádání.
- Implementace: nová větev v `server._prepare()` **před** LLM plánovačem
  (`planner.py`), deterministická, nulová latence. Dotaz do PG:
  `SELECT c.* FROM chunks c JOIN chapters ch ON ch.id=c.chapter_id WHERE
  c.work_id=%s AND ch.ref=%s ORDER BY c.seq` (+ `ref_start` pro odstavec), kontext =
  celý § (všechny jeho chunky) + `neighbors()` ±1 chunk; `routed = {"works":[wid],
  "intent":"cite", "ref":"§ 2079 odst. 1"}`. Zdroj v odpovědi = ten §.
- Test: `rag/tests/test_cite.py` — parser (20 tvarů včetně `§2079odst.1`,
  `paragraf 2079`, `§ 2079 OZ`, `§ 51 ZP`, `čl. 10 LZPS`), a nad fixture PG
  (`tests/fixtures/law_*.jsonl`) lookup.

### 5.3 Kanály, plánovač, embedding

- `--channels vec,fts` — bez `gloss` a `fts_cs` (korpus je česky, glosy nejsou).
  **Ověř, že server bez gloss kolekce nastartuje** (`Retriever(gloss=None)` to umí;
  `get_collection` na neexistující jméno může vyhodit — když ano, přidat guard,
  ne vytvářet prázdnou kolekci).
- FTS: Postgres `simple` bez českého stemmingu (stejné omezení jako dnes);
  `_tsquery(prefix_min=4)` s prefixy pomáhá („výpověd:*"). Termíny z dotazu
  (`query_terms`) jsou u práva silné — „výpovědní doba", „nutná obrana",
  „promlčení" jsou v textu doslova. Zvaž váhu `fts` 1.0 místo 0.8 (`--weights`,
  pokud existuje; jinak `DEFAULT_WEIGHTS` per instance přes parametr) — rozhodne eval.
- Plánovač: `catalog` intent dává smysl („které zákony máš k pracovnímu právu"),
  `reading` („čti dál") ne — nechat `--planner auto`, `cite` jde před něj.
  `--rewrite terms` (bez HyDE: HyDE v právu vymýšlí paragrafy, které pak
  fulltext „najde").
- Embedding **beze změny**: `multilingual-e5-large` fp16 (index i dotaz stejným
  `LocalEmbedder`). Čeština je v e5 dobře pokrytá; `BAAI/bge-m3` jen jako
  pozdější A/B přes eval, ne teď.
- `top_k`: appka posílá 5; law služba **8** (více § na jednu otázku), server
  respektuje `req.top_k`.
- `--no-translate-excerpts` (překlad úryvků je pro pálí; tady by jen zdržoval a
  „přeložil" češtinu do češtiny). `excerpt_cs` v odpovědi pak chybí ⇒ appka
  ukáže originál (pole je nullable, ověřeno).

---

## 6. Prompt `rag/prompts/pravnik_cs.md` — návrh textu

```
Jsi můj právní průvodce nad účinnými právními předpisy České republiky. Zdrojem
jsou úplná znění zákonů z e-Sbírky; u každého úryvku vidíš paragraf, zákon a
datum účinnosti znění.

Zásady:
- Odpovídej česky, věcně, v právní terminologii, ale srozumitelně laikovi.
- Vycházej VÝHRADNĚ z dodaných úryvků. Každé tvrzení o tom, co zákon stanoví,
  opři o citaci ve tvaru [n] a slovně: „§ 2079 odst. 1 občanského zákoníku".
  Nikdy nevymýšlej paragrafy, lhůty, sazby ani judikaturu, které v úryvcích nejsou.
- Když úryvky odpověď neobsahují, řekni to na rovinu („v dodaných ustanoveních
  to není"), navrhni, ve kterém předpisu nebo ustanovení hledat, a NEodpovídej
  z obecné znalosti jako by to bylo ze zákona.
- Vždy uveď, z jakého znění vycházíš („znění účinné od 1. 1. 2026"); připomeň,
  že konsolidované znění může zaostávat za Sbírkou o několik týdnů.
- Odděluj tři věci: (1) co zákon doslova říká, (2) co z toho pro popsanou
  situaci plyne, (3) co je nejisté nebo závisí na výkladu a skutkových
  okolnostech. Na (3) upozorni výslovně.
- Když popis situace nestačí k odpovědi, polož upřesňující otázku, než
  odpovíš — zvlášť u lhůt (od kdy běží), u smluv (co je sjednáno) a u trestů
  (okolnosti).
- U lhůt a dat počítej opatrně a ukaž postup; u peněžních částek uveď, zda jde
  o zákon nebo prováděcí předpis (ten nemusíš mít).
- Na otázky po tom, které předpisy znáš, dostaneš v kontextu výpis z katalogu:
  odpovídej jen z něj, nepřidávej předpisy, které tam nejsou.
- Nejsi advokát a tohle není právní poradenství. U konkrétní věci s následky
  (soud, smlouva, trestní řízení, daně) doporuč ověření u advokáta nebo
  příslušného úřadu — jednou, na konci, bez moralizování.
- Mluv jako zkušený kolega, ne jako formulář: dávej souvislosti, upozorni na
  související ustanovení, které se uživatele může týkat.
```

Prompt je start, ne verdikt — ladit podle §9.3 (halucinace, disclaimer únava,
délka).

---

## 7. Ingester `rag/ingest_law.py` — specifikace

Vstup (dva režimy, stejný výstup):

- `--source cache --acts 89/2012,40/2009,…` nebo `--tier 1` (čte
  `registry/law_tier1.yaml`): per akt `sbr-cache` → `dokumenty-sbirky/{url}`
  (aktuální znění, `staleUrl` s datem) → `…/fragmenty?cisloStranky=1..n`.
  Backoff (429/403: 30 s, ×2, max 5), rozestup ≥ 0,5 s, **cache surových JSON
  na disk** (`downloads/law/cache/{sb}_{rok}_{cislo}_{datum}/p{n}.json`) — druhý
  běh nesahá na síť. Pro vrstvu 1 (~50 aktů, ~60 stránek) je to pár minut.
- `--source dump --dump-dir downloads/law/dumps/` (`002`, `006`, `003`, `004`
  `.json.gz`; stáhnout `curl -O` z Apache indexu; `003`/`004` číst přes `ijson`
  streamově, `002`/`006` do paměti). Filtr: `sb` + podtyp `ZAKON|ZAKONUST`
  (vrstva 2), účinnost od ≤ dnes < do (nebo do = null), bez `zrušení`; aktuální
  znění = to s `typZneni=AKTUALNI`.

Kroky per akt:

1. Strom fragmentů: `hierarchie`/`predek` (dump) nebo `hloubka` + pořadí (cache)
   → strom; typy podle číselníku; neznámý typ **zalogovat** (`--strict` ⇒ chyba).
2. Kapitoly: hierarchické uzly + každý `Paragraf`/`Clanek` jako leaf level 6
   (`ref`, `heading`, `path` — vzor `chapters.Chapter`; `parent_ordinal`,
   `children`).
3. Text §: odstavce/písmena/body v pořadí, `xhtml` → text (strip tagů, `<var>`
   zachovat), nebo `fragment-text` z dumpu; NFC; PPC podle §4.
4. Chunky podle §4 (≤ 1 500 zn.; dělit po odstavcích; prefix `§ N Nadpis\n`);
   `ref_start`/`ref_end`; `seq`.
5. Řádky `works` (z registru + e-Sbírky: `uplnaCitace` → `name_cs`, datum
   znění → `edition`, `eli` → `urn`, `staleUrl` → `source_path`), `chapters`,
   `books` (kontrakt EduRAG + rozšíření — přesně jako `ingest_books.py`, viz
   jeho docstring; pole navíc tolerovat, `load_pg.py` je ignoruje).
6. `--stats-only` (počty §, chunků, znaky, histogram délek — do `docs`), `--out-dir`.

Testy `rag/tests/test_ingest_law.py`: fixture = **první stránka fragmentů NOZ
z cache** (`tests/fixtures/law_sb_2012_89_p1.json`, ~1 000 fragmentů, sáhne
do části 1) + celá Listina (44 čl., malá): očekávané počty kapitol/§/chunků,
že žádný chunk nekříží §, že `§ 2079` má správný `path`, že dělení dlouhého §
zachová odstavce celé, že `(zrušen)` vznikne jako krátký chunk.

Reprodukovatelnost: `make ingest-law TIER=1` v `rag/Makefile`; výstup do
`rag/law/` (`works.jsonl`, `chapters.jsonl`, `books.jsonl`) — **ne** do
knihovních souborů v `rag/`.

---

## 8. Nasazení — fáze s ověřením (styl `PLAN-spark-chatbot.md`)

### Fáze A — data (M2 nebo SPARK, WorldLibraryProject)

1. `registry/law_tier1.yaml` + `registry/validate.py` rozšířit (klíče `abbr`,
   `short`; `group` z povolené množiny odvětví).
2. `ingest_law.py` (+ testy). `make ingest-law TIER=1` → `rag/law/*.jsonl`.
   **Ověř**: `--stats-only` ukáže OZ ≈ 3 100 §, chunků ≈ 4–5 k; Listina 44 čl.;
   `python3 -c` náhodných 5 chunků má text začínající `(1)`/`§`.
3. Postgres: na JODA `docker exec library_postgres psql -U … -c "CREATE DATABASE law OWNER library"`;
   `PG_DSN=…/law python3 pg_migrate.py`; `load_pg.py --input law/books.jsonl
   --works law/works.jsonl --chapters law/chapters.jsonl --replace-all`;
   `make pg-index` s law DSN. **Ověř**: `SELECT count(*) FROM chunks`, FTS
   `to_tsquery('simple','vypovedn:*')` vrátí § 51 ZP. JODA má 3,8 GB RAM —
   GIN index vrstvy 1 je malý; u vrstvy 2 stavět index po částech / sledovat `free -m`.
4. Chroma: `embed_books.py --input law/books.jsonl --collection law_v1
   --chroma-url http://127.0.0.1:8007` na SPARKu (fp16, ~8 min). **Ověř**:
   `collection.count()` = počet chunků; dotaz `query: výpovědní doba` vrátí
   `cz.sb.2006.262` v top-3.

### Fáze B — server (SPARK)

5. `prompts/pravnik_cs.md`; intent `cite` (`planner.py`/`server.py`) +
   `tests/test_cite.py`; `CHUNK_BY_LANG["cs"]`; guard pro chybějící gloss.
   **Knihovní instance po změnách restartovat a ověřit stejný dotaz jako v
   `Ol1nLLM/test/fixtures/library_stream.sse`** (regrese).
6. Unit `~/.config/systemd/user/law-chat.service` (kopie `library-chat` s):
   ```
   ExecStart=%h/deploy/WorldLibraryProject/rag/.venv/bin/python3 server.py \
     --port 8098 --prompt-file prompts/pravnik_cs.md \
     --collection law_v1 --channels vec,fts --no-translate-excerpts \
     --pg-dsn postgresql://library:…@192.168.88.88:5433/law \
     --max-per-work 6 --rewrite terms --summaries-file law/summaries.json \
     --llm-url http://localhost:8080/v1
   ```
   (heslo číst z env souboru unitu, ne do gitu; `--summaries-file` může být
   prázdný JSON `{}`.) `systemctl --user enable --now law-chat`.
   **Ověř**: `curl -s localhost:8098/chat -d '{"message":"Co říká § 2079 občanského zákoníku?"}'`
   → `routed.intent == "cite"`, zdroj `§ 2079`; `free -g` a `nvidia-smi
   --query-compute-apps` (+~1,3 GiB); `journalctl --user -u law-chat`.
7. Eval (§9) — **teprve tady** se rozhoduje, jestli jde dál.

### Fáze C — tunel (SPARK, AiStack) — `[ČLOVĚK]` uprostřed

8. `cloudflared/config.yml`: blok `pravnik.ol1n.com → http://host.docker.internal:8098`
   (kopie `chat.ol1n.com` včetně `originRequest` timeoutů) **s `access` blokem
   od začátku** (viz varování v `PLAN-spark-chatbot.md`: bez Access je hostname
   veřejný). DNS route: `cloudflared tunnel route dns f3cb3ac1-d9fa-4c78-9d87-ff3cab6c7051 pravnik.ol1n.com`.
9. `[ČLOVĚK]` Zero Trust: Access App `pravnik.ol1n.com`, policy `non_identity`
   se **stejným service tokenem** jako `llm.ol1n.com` (appka pak nic nemění);
   AUD tag do configu; `docker compose -f deploy/docker-compose.yml restart cloudflared-1 cloudflared-2`.
   **Ověř** z M2: `curl -H CF-Access-Client-Id… https://pravnik.ol1n.com/` → 200;
   bez hlaviček → 302 na Access.

### Fáze D — appka (Ol1nLLM)

10. `assets/personas/index.json`:
    ```json
    {"id":"pravnik","name":"Právník","emoji":"⚖️","backend":"law",
     "description":"Odpovídá z účinných zákonů ČR (e-Sbírka) s citací paragrafů. Není právní poradenství."}
    ```
    bez `file` (server staví prompt sám — `persona_service.dart:41`).
11. `chat_backend.dart:7`: `const kChatBackendLaw = 'law';`.
12. **Refaktor místo kopie**: `LibraryChatService` dostane konstruktor
    `({required String baseUrl, required String id, required String label, int topK = 5})`
    a dvě pojmenované továrny `LibraryChatService.library()` (`LIBRARY_CHAT_URL`,
    „knihovna", 5) a `LibraryChatService.law()` (`LAW_CHAT_URL`, výchozí
    `https://pravnik.ol1n.com`, „právník", 8). `String.fromEnvironment` musí
    zůstat `static const` — dvě konstanty, továrny je předají. Chybové texty
    (`[knihovna] …`, hint „knihovna neběží (systemctl status library-chat)") přes
    `label`/jméno unitu. `parseSseLine` zůstává statické (test se nemění).
13. `chat_provider.dart`: field `_law = LibraryChatService.law()`; `_backendFor`
    jako `switch (persona?.backend) { kChatBackendLibrary => _library,
    kChatBackendLaw => _law, _ => _vllm }`; **`deleteConversation`** přes
    `_backendFor(doomed.activePersonaId).then((b) => b.resetSession(id))`
    (dnes natvrdo `_library`, ř. 146–151); `dispose()` doplnit.
14. `chat_input_bar.dart:155-159, 207-210`: `isLibrary` → obecné
    `ragBackend` + hint per backend („Zeptej se na zákon…"). Přepnutí backendu
    (ř. 358–376) funguje beze změny — porovnává řetězec.
15. `Makefile`: `$(if $(LAW_CHAT_URL),--dart-define=LAW_CHAT_URL=$(LAW_CHAT_URL),)`;
    `CLAUDE.md`: řádek do „Volitelné URL overrides" (+ LAN `http://192.168.88.66:8098`
    jen s `make debug`) a odstavec do sekce Chat (tabulka backendů dostane třetí sloupec).
16. Testy: `test/fixtures/law_stream.sse` **zachycený z běžícího serveru přes
    tunel** (stejně jako knihovní fixture — `curl -N` na `/chat/stream`, dotaz
    „Jaká je výpovědní doba u pracovního poměru?"); `test/law_sse_parse_test.dart`
    (nebo knihovní test parametrizovat továrnou): terminální rámec 1×, `sources`
    neprázdné, `name_cs` obsahuje `262/2006`, `title` obsahuje `§ 51`,
    `excerpt_cs == null`, `model` neprázdný; **provider test** `_backendFor`:
    persona `pravnik` → služba s `id == 'law'`, `knihovnik` → `library`, ostatní
    → vLLM (dnes žádný takový test není).
17. `make debug` proti LAN :8098, pak `make run` přes tunel; ručně 5 otázek z
    goldenu + jedna mimo korpus („vyhláška o …") — musí říct, že to nemá.

### 8.1 Odhad práce

Vrstva 1 od nuly po appku: **~3 dny Opusova času** (A 1 den, B+C 1 den, D 1 den),
GPU čas zanedbatelný. Vrstva 2: +½ dne (dump + ijson + delší embed), a **teprve
po evalu vrstvy 1**.

### 8.2 Proč `title = "89/2012 Sb. (§ 2079 odst. 1)"`

`LibrarySource.subtitle` bere pozici z **konce `title` v závorce** a ukáže ji,
jen když je `name_cs`. Tímhle tvarem se řádek zdroje vykreslí jako
*„zákon č. 89/2012 Sb., občanský zákoník — § 2079 odst. 1 · obcanske · cs"*
**bez jediné změny v appce**. Server law instance to skládá v místě, kde dnes
staví `"{name} (část N/M)"` (`server.py` ~ř. 393–404) — přepínač podle
`chapters.ref` (když existuje, použij ho). `path` = stálá URL (`/sb/2012/89/2026-01-01#par_2079-odst_1`),
zobrazí se monospace dole v detailu.

### 8.3 Co appka dostane navíc, až bude čas (ne MVP)

- Klikací odkaz na `https://e-sbirka.gov.cz{path}` v detailu zdroje.
- Pole `citation` v `LibrarySource` (server posílá `zkracenaCitace`) místo
  parsování `title`.
- Zobrazení `routed` (zákon + datum znění) pod odpovědí; badge „znění účinné od …".
- Persona description v UI s trvalým disclaimerem (ne jen v promptu).

---

## 9. Eval — bez něj se nic neprohlašuje za hotové

### 9.1 `rag/eval/golden_law.jsonl` (~40 otázek, vrstva 1)

Formát rozšiřuje dnešní golden o očekávaný **§**:

```jsonl
{"q": "Co říká § 2079 občanského zákoníku?", "intent": "cite", "expect": [{"work": "cz.sb.2012.89", "ref": "§ 2079"}]}
{"q": "§ 51 ZP", "intent": "cite", "expect": [{"work": "cz.sb.2006.262", "ref": "§ 51"}]}
{"q": "Jaká je výpovědní doba u pracovního poměru?", "expect": [{"work": "cz.sb.2006.262", "ref": "§ 51"}], "k": 5}
{"q": "Kdy jde o nutnou obranu?", "expect": [{"work": "cz.sb.2009.40", "ref": "§ 29"}], "k": 5}
{"q": "Jak dlouhá je obecná promlčecí lhůta?", "expect": [{"work": "cz.sb.2012.89", "ref": "§ 629"}], "k": 5}
{"q": "Do kdy musím podat odvolání proti rozsudku okresního soudu v civilní věci?", "expect": [{"work": "cz.sb.1963.99", "ref": "§ 204"}], "k": 5}
{"q": "Kolik činí základní kapitál společnosti s ručením omezeným?", "expect": [{"work": "cz.sb.2012.90", "ref": "§ 142"}], "k": 5}
{"q": "Jaké zákony máš k pracovnímu právu?", "intent": "catalog", "expect_group": "pracovni_socialni", "min_works": 3}
{"q": "Jaká je sazba DPH na knihy?", "expect_none": true, "note": "sazby jsou v příloze — ověřit, jestli příloha prošla ingestem; jinak musí říct, že nemá"}
```

Čísla § v ukázkách jsou k ověření proti korpusu, ne opsat slepě.

### 9.2 Metriky (`eval_retrieval.py` rozšířit o `expect[].ref`)

- `cite` intent: **100 %** správný § (deterministické — cokoli míň je bug).
- Sémantické dotazy: recall@5 ≥ **0,8**, recall@8 ≥ 0,9 na vrstvě 1; srovnat
  `--channels vec,fts` vs `vec` (fulltext má u práva velkou váhu) a `--max-per-work 2/6/0`.
- Katalog: `expect_group`/`min_works` jako dnes.
- Baseline bez routingu (`--no-routing`) pro srovnání, ať je vidět, co aliasy přinesly.

### 9.3 Kvalita odpovědí (ručně, 15 otázek × 3 modely)

Retrieval může být správně a odpověď stejně halucinuje. Tabulka
otázka × `translate` / `swarm-director` / `fallback` (co zrovna běží — viz
§1.1), hodnotit: (a) cituje jen dodané §, (b) uvede znění/datum, (c) odliší
zákon od výkladu, (d) disclaimer právě jednou, (e) česky správně. Ukládat do
`rag/eval/results/law_answers_<datum>.md`. **Pokud `fallback` selhává v (a),
Právník se nesmí pouštět na produkci, dokud pro něj neběží lepší role** —
to je rozhodnutí pro uživatele, ne pro Opuse.

---

## 10. Provoz

- **Refresh**: týdně (cron na M2 nebo timer na SPARKu, mimo noční okno RAG):
  stáhnout `002`/`006`, porovnat datum aktuálního znění per akt s
  `works.edition`; změněné akty re-ingest z cache (`--acts …`), `load_pg
  --replace-work`, `embed` (idempotentní). S klíčem API později `zmeny-zneni`.
- **Noční režim SPARKu** (`rag-schedule.timer`): `law-chat` nechat běžet (1,3 GiB),
  ale nespouštět embed vrstvy 2 mezi 00:00–08:00 (director si bere 93 GiB).
- **Monitoring**: `journalctl --user -u law-chat`; appka hlásí 502/503 s hintem
  na unit — v `LibraryChatService.law()` hint `systemctl status law-chat`.
- **Verze korpusu** je vidět: `works.edition` v katalogu, datum v každé odpovědi.

---

## 11. Rizika a otevřené otázky (rozhodne uživatel)

1. **Hostname**: `pravnik.ol1n.com` (samostatný, Access blok zvlášť) vs. cesta
   pod `chat.ol1n.com` (jedna Access App, ale server by musel multiplexovat
   korpusy — větší zásah). Plán počítá se samostatným hostname.
2. **LLM**: dnes běží jen `fallback`. Právník s ním může být nepoužitelný
   (§9.3). Zapnout `translate` (36 GiB) na dobu měření?
3. **Vrstva 2 hned, nebo až po evalu?** Plán: až po evalu.
4. **Zkratky bez diakritiky** (`osr`, `sr`, `dr`) jsou dvojznačné — parser je
   bere jen velkými písmeny; uživatel to musí vědět (hint v UI).
5. **Nestabilní `fragmentId`** do 15. 1. 2026/2027 — proto ELI/staleUrl.
   **Konsolidační zpoždění** (15+ pracovních dnů) — proto datum v odpovědi.
6. **Právní/produktové riziko**: persona radí v právu. Disclaimer v promptu, v
   popisu persony a v UI; žádné „poradenství" ve jménu ani popisu.
7. **Judikatura MSp** obsahuje jména soudců — je to oficiální open data, ale do
   promptu je nedávat (strip `header`), když se vrstva 4 bude dělat.
8. **Cache REST bez podpory** — když začne 403/429 padat i s backoffem, přejít
   na dumpy i pro vrstvu 1 (kód to musí umět od začátku: dva `--source`).

---

## Příloha A — ukázkové záznamy JSONL

```jsonl
# works.jsonl
{"id":"cz.sb.2012.89","group":"obcanske","subgroup":"ZAKON","title":"89/2012 Sb.","work_legacy":"89/2012 Sb.","name_cs":"zákon č. 89/2012 Sb., občanský zákoník","author":"Parlament ČR","author_cs":"Parlament ČR","lang_original":"cs","lang_corpus":"cs","form":"zakonik","period":"účinný od 1. 1. 2014","edition":"úplné znění účinné od 2026-01-01 (e-Sbírka, staženo 2026-09-23)","urn":"/eli/cz/sb/2012/89","source_path":"/sb/2012/89/2026-01-01","priority":1,"aliases":["obcansk zakonik","obcanskeho zakoniku","obcanskem zakoniku","89/2012"],"abbr":["OZ","NOZ"],"chunk_count":4380,"chapter_count":3350,"char_count":2100000}
# chapters.jsonl
{"id":"cz.sb.2012.89:2411","work_id":"cz.sb.2012.89","ordinal":2411,"level":6,"parent_ordinal":2405,"ref":"§ 2079","heading":"Kupní smlouva","path":"Část čtvrtá › Hlava II › Díl 1 › Oddíl 2 › Pododdíl 1 › § 2079 Kupní smlouva","eli":"/eli/cz/sb/2012/89/2026-01-01/dokument/norma/cast_4/hlava_2/dil_1/oddil_2/pododdil_1/par_2079","char_count":412}
# books.jsonl
{"id":"cz.sb.2012.89:2411:0000","source":"e-sbirka","lang":"cs","group":"obcanske","title":"89/2012 Sb. (§ 2079)","text":"§ 2079 Kupní smlouva\n(1) Kupní smlouvou se prodávající zavazuje, že kupujícímu odevzdá věc, která je předmětem koupě, a umožní mu nabýt vlastnické právo k ní, a kupující se zavazuje, že věc převezme a zaplatí prodávajícímu kupní cenu.\n(2) Neplyne-li ze smlouvy nebo zvyklostí něco jiného, jsou prodávající a kupující zavázáni splnit své povinnosti současně.","work":"89/2012 Sb.","work_id":"cz.sb.2012.89","chapter_id":"cz.sb.2012.89:2411","chapter_ref":"§ 2079","chapter_path":"Část čtvrtá › Hlava II › Díl 1 › Oddíl 2 › Pododdíl 1 › § 2079 Kupní smlouva","seq_in_chapter":0,"chunk_index":2398,"ref_start":"§ 2079 odst. 1","ref_end":"§ 2079 odst. 2","citation":"§ 2079 zákona č. 89/2012 Sb.","stale_url":"/sb/2012/89/2026-01-01#par_2079","effective_from":"2026-01-01","text_sha":"…","created_at":"2026-09-23T10:00:00Z","embedded":false}
```

## Příloha B — ověřené URL v jednom místě

| | |
|---|---|
| Dumpy | `https://opendata.eselpoint.gov.cz/datove-sady-esbirka/` |
| SPARQL | `https://opendata.eselpoint.gov.cz/sparql` |
| Cache REST | `https://e-sbirka.gov.cz/sbr-cache/dokumenty-sbirky/%2Fsb%2F{rok}%2F{cislo}[%2F{datum}]/{fragmenty?cisloStranky=N \| obsah \| historie \| odkazy-ke-stazeni}` |
| Keyovaná API | `https://api.e-sbirka.gov.cz` (`esel-api-access-key`), OpenAPI `…/dokumentace/Definicni_soubor_REST_API_e-Sbirka.zip` |
| Příručky | `…/dokumentace/Prirucka_REST_API_e-Sbirka.pdf`, `…/dokumentace/Prirucka_OpenData_e-Sbirka.pdf` |
| Stálá URL / ELI | `https://e-sbirka.gov.cz/sb/2012/89/2026-01-01#par_2079`, `/eli/cz/sb/2012/89/2026-01-01/dokument/norma/…/par_2079` |
| Judikatura MSp | `https://rozhodnuti.justice.cz/api/opendata/{rok}/{mesic}/{den}?page=N`, `…/api/finaldoc/{uuid}` |
| EU (cs) | `http://publications.europa.eu/resource/celex/{CELEX}` + `Accept-Language: cs` |
| Licence | § 3 písm. a) z. č. 121/2000 Sb.; NKOD podmínky e-Sbírky (CC0-ekvivalent) |
