# Screenshoty pro olin.now (`test/screenshots_test.dart`)

Přesunuto z `CLAUDE.md`.


Stránka appky na olin.now (repo `ol1n.now`, `apps/ol1nllm/`, podstránka
`pages/features.html`) bere mobilní screenshoty z golden testu nad skutečnými
obrazovkami, ne z telefonu:

```bash
flutter test test/screenshots_test.dart --update-goldens   # → test/screenshots/*.png
cp test/screenshots/*.png ../ol1n.now/apps/ol1nllm/screenshots/raw/mobile/android/
```

Suita má tag `screenshots` (`dart_test.yaml`); běžný běh ji má vynechat přes
`flutter test --exclude-tags screenshots`, protože goldeny srovnávají pixely
a jiná verze Skia nebo fontu by shodila build kvůli rozdílu, který není chyba.
Běží jen na macOS: emoji, `monospace` a ☐ si půjčuje ze systémových fontů.

Na obrazovce není nic vymyšleného tam, kde appka ukazuje výstup serveru:
odpovědi chatu jsou tytéž zachycené fixtury jako v testech parserů, katalogy
v `test/fixtures/screenshots/` (scény, příběhy, tance, checkpointy) jsou
stažené ze serveru, obrázky jsou výstupy labu. Výjimky jsou vypsané
v hlavičce testu (LoRA seznam je výběr z živého, hudební projekt je vzorek).
Stav se do providerů vkládá přímo (`notifier.state = …`), takže produkční kód
kvůli screenshotům nemá žádný háček navíc. Dva záběry chybí, protože pro ně
nebylo co pravdivého ukázat: odpověď Knihovníka a review záběrů ve StoryStudiu
— až bude zachycená odpověď / keyframy skutečného jobu, stačí přidat fixturu.
