# RealUnit Handbook

User-Guide + Test-Doku in einem. Jeder Screenshot ist eine Visual-Regression-
Golden-Baseline aus `test/goldens/` (`screens/` + `widgets/`); das Handbook bleibt nur dann
visuell korrekt, wenn die App es auch ist — eine Drift im echten Seitenrendering
flippt den entsprechenden Golden-Test rot, bevor das Handbook-Image gebaut wird.

## Lokal lesen

```bash
# 1. Screenshots aus Goldens lokal in docs/handbook/screenshots/ assemblieren
#    (Verzeichnis ist gitignored; wird nur fürs lokale Preview befüllt)
bash scripts/assemble-handbook-screenshots.sh docs/handbook/screenshots

# 2. HTML im Browser öffnen — kein Web-Server nötig
open docs/handbook/de/index.html
```

Den gleichen Multi-Stage-Build macht `Dockerfile.handbook` automatisch beim
deployten Image (`handbook.realunit.app`).

## Screenshots regenerieren

Es gibt keinen separaten Regeneration-Schritt: Die 278 Handbook-Screenshots
sind direkt die Golden-Baselines unter `test/goldens/` (gemappt in
`scripts/assemble-handbook-screenshots.sh`). Eine UI-Änderung an einer der
gemappten Pages produziert beim `flutter test test/goldens` einen Diff —
diesen via `golden-regenerate.yaml` auf dem self-hosted Runner regenerieren lassen, und der
nächste Handbook-Deploy zeigt das aktualisierte Bild.

Workflow:

1. Page in `lib/screens/**/*_page.dart` ändern
2. `flutter test test/goldens/screens/<feature>` läuft rot mit Diff-Artefakt
3. `gh workflow run golden-regenerate.yaml --ref <branch>` — der Workflow
   regeneriert auf dem self-hosted Runner und committet die neuen PNGs als
   `github-actions[bot]` zurück auf den Branch (siehe
   [`../visual-regression-tests.md`](../visual-regression-tests.md))
4. Pullen → der nächste Handbook-Deploy zeigt die neue Baseline automatisch
   (Push auf `staging` → PRD).

## Selektive Läufe (Teilmenge)

`scripts/run-handbook-flows.sh` akzeptiert optionale Argumente: Glob-Muster auf
die Flow-Namen. Ohne Argument laufen alle Flows, mit Argument nur die passende
Teilmenge:

```bash
# Nur diesen einen Flow
scripts/run-handbook-flows.sh 25-restore-wallet

# Die ganze 20er-Serie (20..26)
scripts/run-handbook-flows.sh '2*'
```

Achtung: Die handbook-Flows sind eine **sequentielle Kette** und teilen sich den
App-State — jeder Flow greift den Zustand auf, wo der vorherige ihn hingelegt
hat. Ein Flow aus der Mitte der Kette schlägt einzeln fehl, sofern er nicht
selbst mit einem `launchApp` beginnt. Der Flow `26-terms` ist **eigenständig**
(eigener `launchApp`) und kann daher gefahrlos allein laufen.

Auch der Tier-3-GitHub-Workflow hat dafür einen `flows`-`workflow_dispatch`-Input
— so lässt sich in der CI gezielt eine Teilmenge der Flows als Navigation-Smoke
neu laufen lassen. (Die Screenshots zieht das Handbook aus den Goldens, nicht
mehr aus diesen Maestro-Läufen.)

## Live Geo-Filter-Tabelle

Die Sektion **Aktientoken — Geo-Filter** (`#spec-geo`) lädt `GET /v1/country`
zur Laufzeit. Länderzeilen gehören nicht ins Repo. Im Image proxied nginx
`/v1/country` auf `https://api.dfx.swiss/v1/country`; eine lokale HTML-Vorschau
fällt auf die öffentliche API zurück.

## Einen neuen Handbook-Eintrag hinzufügen

1. **Page + Golden-Test**: `lib/screens/<feature>/<name>_page.dart` + zugehörigen
   Golden-Test unter `test/goldens/screens/<feature>/`. Pattern siehe
   [`../visual-regression-tests.md`](../visual-regression-tests.md) und bestehende
   Tests in `test/goldens/screens/`.
2. **Screenshot-Mapping**: in `scripts/assemble-handbook-screenshots.sh` eine neue
   Zeile in der `MAPPING`-Tabelle ergänzen — `"NN-<name>=<feature>/goldens/macos/<file>.png"`.
   Die Nummer NN ist der Sortierschlüssel im Handbook (keine direkte Bindung mehr
   an einen Maestro-Flow). Damit ändert sich die Screenshot-Anzahl: den
   Count-Guard in `.github/workflows/handbook-build-check.yaml` (der
   `if [ "$count" != "N" ]`-Check plus die `NN-…`-Kommentare/-Samples im
   Smoke-Step) im selben Zug anpassen — analog zur `EXPECTED_PDF_COUNT`-Mechanik
   weiter unten.
3. **HTML**: in `docs/handbook/de/index.html` einen neuen `<div class="test">`-Block
   in die thematisch passende `<details id="spec-NN" class="spec">`-Sektion
   einfügen (Muster siehe spec-01). Die Screenshots sind in wenige thematische
   spec-Sektionen gruppiert — ein neuer Eintrag kommt meist in eine bestehende.
4. **Nur bei einem neuen Thema**: eine neue `<details id="spec-NN" class="spec">`
   anlegen und den Anker `#spec-NN` in `<nav class="toc">` ergänzen.
5. **Optional — Tier-3-Smoke**: zusätzlich `.maestro/handbook/NN-<name>.yaml` für
   den Navigation-/Tap-Routing-Smoke anlegen (siehe "Einen neuen Maestro-Flow
   hinzufügen" unten). Nicht zwingend für jeden neuen Handbook-Eintrag — nur wenn
   ein neuer User-Pfad durch die App geprüft werden soll.

### Einen neuen Maestro-Flow hinzufügen (Tier-3-Smoke)

1. Anlegen: `.maestro/handbook/NN-<name>.yaml`.
   - Erster Flow startet mit `launchApp: clearState: true`.
   - Folgeflows starten ohne `launchApp` — sie greifen den App-State auf,
     wo der vorherige Flow ihn hingelegt hat.
   - Beende mit `assertVisible` oder `extendedWaitUntil`, damit die Assertion
     stabil ist (sonst trifft Maestro mitten in der Transition).
2. Lauf: `scripts/run-handbook-flows.sh` (lokal) bzw. Tier-3-CI auf PR.

## E-Mail Previews

Die HTML-Vorschauen aller vom Backend an Endkunden versendeten Mails liegen
**nicht in diesem Repo**. Quelle ist `DFXswiss/api`:

- Generator: `scripts/generate-realunit-previews.js`
- Vorlage: `src/subdomains/supporting/notification/templates/realunit.hbs`
- Übersetzungen: `src/shared/i18n/de/mail-realunit.json` (RealUnit-Texte) mit
  Fallback auf `src/shared/i18n/de/mail.json` (DFX-Defaults)

Der Handbook-CI-Build (`.github/workflows/handbook.yaml`) checkt das api-Repo
zur Build-Zeit aus, führt den Generator aus und kopiert das Ergebnis nach
`docs/handbook/mails/`, bevor das Docker-Image gebaut wird. `docs/handbook/mails/`
ist in `.gitignore` — der Inhalt darf nie ins Repo eingecheckt werden, sonst
divergieren Image-Stand und Source-of-Truth.

### Trigger

Der Handbook-Deploy läuft in genau ein Environment (PRD): jeder `push` auf
`staging` deployt `handbook.realunit.app` (Image `:latest`) — es gibt keinen
Pfad-Filter mehr, jeder Merge nach `staging` löst den Deploy aus, unabhängig
davon, welche Dateien er ändert. Alternativ per manuellem `workflow_dispatch`
auf `handbook-deploy.yaml` in **diesem** Repo. Die frühere separate
DEV-Instanz (`dev-handbook.realunit.app`, Image `:beta`) ist stillgelegt und
wird nicht mehr bespielt; das Sicherheitsnetz für Handbook-INHALTE ist jetzt
der PR-Check `handbook-build-check.yaml`, der bei jedem handbook-relevanten
PR läuft (Screenshot-Assemblierung, Store-Listing-Sync, Legal-Sync sowie
Image-Build + Container-Smoke) — die Deploy-VERDRAHTUNG selbst (SSH/Secrets/
Rollout in `handbook-deploy.yaml`) prüft erst der Deploy-Lauf selbst. Eine
reine Mail-Template-, i18n- oder Generator-Änderung im api-Repo löst
**keinen** automatischen Rebuild aus — sie fliesst erst mit dem nächsten
Handbook-Deploy hier rein.

Wer eine reine Mail-Änderung sofort live haben will, hat zwei Optionen
im realunit-app-Repo:

```bash
# Variante A: No-op-Touch, dann push auf staging — es gibt keinen
# Pfad-Filter mehr, jeder Push auf staging löst den Deploy aus.
touch docs/handbook/.sync && git add docs/handbook/.sync \
  && git commit -m "chore(handbook): pull latest mail templates from api" \
  && git push origin staging

# Variante B: manuell dispatchen (kein Commit nötig)
gh workflow run handbook-deploy.yaml --ref staging
```

### Lokal regenerieren

Mit beiden Repos nebeneinander ausgecheckt — alle Befehle laufen im
realunit-app-Root. Wir installieren handlebars **isoliert** in einen scratch
Prefix (`_handlebars-only/`), genau wie der CI-Step in `handbook.yaml`. So
bleiben `package.json` und `package-lock.json` im api-Klon unangetastet
(sonst wäre `git status` im api-Repo nach dem Repro dreckig).

```bash
# 1. handlebars isoliert installieren (idempotent — kann beliebig oft laufen)
npm install --prefix ./_handlebars-only --no-save --no-audit --no-fund handlebars

# 2. Generator aus dem api-Repo ausführen (NODE_PATH zeigt auf den scratch-Install)
NODE_PATH="./_handlebars-only/node_modules" \
  node ../api/scripts/generate-realunit-previews.js

# 3. Ergebnis ins Handbook übernehmen
mkdir -p docs/handbook/mails
cp ../api/scripts/email-previews/realunit/*.html docs/handbook/mails/
cp docs/handbook/mails/00_index.html docs/handbook/mails/index.html

# 4. Lokal ansehen
open docs/handbook/mails/index.html

# 5. Scratch-Dir aufräumen (in .gitignore — aber sauber ist sauber)
rm -rf ./_handlebars-only
```

(Den finalen Build-Step macht aber immer der CI — lokale Files sind nur fürs
Vorab-Anschauen während eines Template-Refactors.)

## Transaktionsbelege

Die Sektion **B — Transaktionsbelege** verlinkt acht Muster-PDFs, die das
Backend erzeugt — Transaktionshistorie, Transaktionsbestätigung,
Verkauf-Bestätigung und Übertragung, jeweils in DE und EN.
Anders als die Mail-Previews werden diese PDFs **nicht** hier generiert — sie
liegen bereits committet im api-Repo unter `docs/examples/realunit-receipt/`
(gerendert vom `SwissQRService` via `realunit-receipt-example.spec.ts`) und
werden beim Handbook-Build nur ins Image kopiert (Step "Stage RealUnit receipt
examples from api repo" in `handbook.yaml`; Zielverzeichnis
`docs/handbook/receipts/` ist gitignored). Single Source of Truth ist das
api-Repo.

Kommt upstream ein Beispiel hinzu oder weg, failt der Build am
`EXPECTED_PDF_COUNT`-Guard — dann die Zahl in `handbook.yaml` und die
Download-Karten in `docs/handbook/de/index.html` (`#spec-receipts`) im selben
Zug anpassen.

### Lokal ansehen

```bash
# PDFs aus einem lokalen api-Checkout ins (gitignored) receipts-Dir kopieren
mkdir -p docs/handbook/receipts
cp <api-checkout>/docs/examples/realunit-receipt/*.pdf docs/handbook/receipts/
open docs/handbook/de/index.html   # Sektion "B — Transaktionsbelege"
```

Zum Regenerieren der Muster-PDFs selbst siehe das api-Repo
(`GENERATE_RECEIPT_EXAMPLES=true npx jest realunit-receipt-example`).

## Vermögensübersicht

Die Sektion **V — Vermögensübersicht** (`#spec-balance`) verlinkt zwei
Muster-PDFs (DE + EN): die Vermögensübersicht weist den REALU-Bestand mit dem
massgeblichen Steuerwert aus. Wie die Transaktionsbelege werden diese PDFs
**nicht** hier generiert — sie liegen bereits committet im api-Repo unter
`docs/examples/realunit-statement/` (gerendert vom `BalancePdfService` via
`realunit-balance-example.spec.ts`) und werden beim Handbook-Build nur ins Image
kopiert (Step "Stage RealUnit balance examples from api repo" in `handbook.yaml`;
Zielverzeichnis `docs/handbook/balance/` ist gitignored). Single Source of Truth
ist das api-Repo. Kommt upstream ein Beispiel hinzu oder weg, failt der Build am
eigenen `EXPECTED_PDF_COUNT`-Guard des balance-Steps — dann die Zahl in
`handbook.yaml` und die Download-Karten in `#spec-balance` im selben Zug anpassen.

## Web-Baselines (realunit.app)

Die Sektion **W — Web / realunit.app** (`#spec-web`) zeigt die
Visual-Regression-Baselines der öffentlichen Website `realunit.app`
(Landingpage + Aktionariat-Adressbestätigungs-Flow + Adresse-hinzufügen-Flow unter `/account-merge/`). Sie sind das Web-Pendant
zu den Golden-Screenshots der App: Jedes Bild ist eine **Playwright-Baseline**,
die im `RealUnitCH/web`-Repo unter `tests/__screenshots__/` committet und von
dessen Visual-Regression-CI abgesichert ist — driftet das Seitenrendering, wird
zuerst dort ein Test rot, bevor die Baseline sich ändert.

Wie die api-Artefakte werden diese PNGs **nicht** hier committet, sondern beim
Handbook-Build eingezogen: der Step "Stage web e2e baselines from web repo" in
`handbook.yaml` checkt `RealUnitCH/web@develop` aus und kopiert
`tests/__screenshots__/{desktop-chromium,tablet-chromium,mobile-safari}/` nach
`docs/handbook/web/` (gitignored). Single Source of Truth ist das web-Repo; die
Ref bleibt — wie der api-Checkout — auf `develop` gepinnt (Integrations-Branch =
aktuell akzeptierte Baselines), unabhängig vom Deploy-Branch `staging`.

Kommt im web-Repo eine View hinzu oder weg, failt der Build am
`EXPECTED_WEB_BASELINE_COUNT`-Guard des Steps — dann die Zahl in `handbook.yaml`
**und** die Bild-Karten in `#spec-web` (`docs/handbook/de/index.html`) im selben
Zug anpassen. Eine reine Website-Änderung im web-Repo löst hier **keinen**
automatischen Rebuild aus — sie fliesst erst mit dem nächsten Handbook-Deploy
rein (Push auf `staging` → PRD, oder manueller `workflow_dispatch --ref staging`
auf `handbook-deploy.yaml`).

### Lokal ansehen

```bash
# Baselines aus einem lokalen web-Checkout ins (gitignored) web-Dir kopieren
mkdir -p docs/handbook/web
cp -R <web-checkout>/tests/__screenshots__/. docs/handbook/web/
open docs/handbook/de/index.html   # Sektion "W — Web / realunit.app"
```

## Beziehung zu den Tier-0/Tier-1-Tests

Tier 0/1 (Unit + Widget + integration-mit-FakeBitboxCredentials) prüfen
einzelne Methoden / Zustände / Branches. Tier 3 (Maestro) prüft den
User-Journey-Layer drüber: dass die Pages in der richtigen Reihenfolge
erscheinen und ihre Inhalte korrekt rendern. Beide Tiers ergänzen sich;
keiner ersetzt den anderen. Siehe [`../testing.md`](../testing.md).
