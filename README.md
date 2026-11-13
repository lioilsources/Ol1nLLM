# ol1n_llm

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Distribuce

Každý release build nese service token Cloudflare Access (`--dart-define`)
a repo je veřejné. Proto se binárky **nikam veřejně nenahrávají**:

- iOS jde do TestFlightu, Android do Firebase App Distribution. Obojí na
  pozvání, odkaz se rozdává jen známým lidem.
- GitHub Release nese jen poznámky, žádné soubory.
- Desktopové workflowy (`release-macos/windows/linux.yml`) se spouští ručně
  a jen ověří build — bez tokenu a bez nahrání. Soukromý kanál pro desktop
  zatím není.
- CI staví debug buildy bez tokenu, jejich artefakty jsou tedy neškodné.

Kdyby appka měla být veřejná, token patří nahradit přihlášením uživatele,
ne schovat lépe.
