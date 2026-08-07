import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/legal/subpages/legal_document_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';

import '../../../helper/helper.dart';

void main() {
  // Sibling `legal_document_golden_test.dart` covers the empty placeholder and a
  // loaded document without a PDF footer. This file adds the loaded state WITH
  // the "Original-PDF" footer button (`params.pdfUrls` set) and the asset
  // load-error view.
  late MockSettingsBloc settingsBloc;

  setUp(() {
    // The page loads its document from rootBundle, which caches per asset path.
    // Clear it so the load-error golden's missing-asset read fails fresh rather
    // than replaying a cached future.
    rootBundle.clear();
    settingsBloc = MockSettingsBloc();
    when(() => settingsBloc.state).thenReturn(const SettingsState());
  });

  Widget buildSubject({
    String assetBaseName = 'terms',
    String? initialMarkdownContent,
    Map<String, String>? pdfUrls,
  }) =>
      BlocProvider<SettingsBloc>.value(
        value: settingsBloc,
        child: LegalDocumentPage(
          params: LegalDocumentParams(
            title: 'Terms',
            assetBaseName: assetBaseName,
            pdfUrls: pdfUrls,
          ),
          initialMarkdownContent: initialMarkdownContent,
        ),
      );

  group('$LegalDocumentPage', () {
    // Loaded document WITH a PDF footer: a non-null `params.pdfUrls` makes
    // `_pdfUrl` resolve, adding the secondary "Original-PDF" button under the
    // Markdown body (page:121-140). The markdown is passed via the
    // @visibleForTesting hook so it renders synchronously (no async asset load).
    goldenTest(
      'document loaded with PDF footer button',
      fileName: 'legal_document_page_loaded_with_pdf',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        buildSubject(
          initialMarkdownContent: _termsMarkdownStub,
          pdfUrls: const {'de': _termsPdfUrl, 'en': _termsPdfUrl},
        ),
      ),
    );

    // Load-error view: a missing asset makes `rootBundle.loadString` throw, so
    // `initState` flips `_loadFailed` and the page renders the error state
    // (error_outline icon + title + description + retry — page:150-184).
    // pumpAndSettle drives the async failure to completion.
    goldenTest(
      'load error view',
      fileName: 'legal_document_page_load_error',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) => tester.pumpAndSettle(),
      builder: () => wrapForGolden(
        buildSubject(assetBaseName: 'missing_legal_asset_test'),
      ),
    );
  });
}

/// Placeholder PDF URL — the value is only used on tap, never rendered, so a
/// stable stub keeps the golden independent of the live legal-documents config.
const _termsPdfUrl = 'https://realunit.ch/legal/terms.pdf';

/// Representative head of `assets/legal/terms_of_use_de.md` — kept inline so the
/// golden does not depend on the live asset file changing.
const _termsMarkdownStub = '''# Nutzungsbedingungen der RealUnit Wallet App

*Stand: Februar 2026*


## 1. Geltungsbereich

Diese Nutzungsbedingungen regeln die Verwendung der RealUnit Wallet App (nachfolgend «App»), herausgegeben von der RealUnit Schweiz AG, Schochenmühlestrasse 6, 6340 Baar, Schweiz (nachfolgend «RealUnit» oder «wir»).

Mit der Nutzung der App erklären Sie sich mit diesen Nutzungsbedingungen einverstanden. Für den Kauf und Verkauf von RealUnit Aktien-Token gelten zusätzlich die Allgemeinen Geschäftsbedingungen (AGB).


## 2. Beschreibung der App

Die App ist eine Self-Custody-Wallet für die Verwaltung von RealUnit Aktien-Token (REALU) und weiteren ERC-20-Token auf der Ethereum-Blockchain. Sie ermöglicht insbesondere:

- Erstellen und Wiederherstellen von Wallets mittels Wiederherstellungs-Wörtern (Seed Phrase)
- Empfangen und Senden von Token
- Anzeige von Guthaben und Transaktionshistorie
- Erstellung von Steuerberichten
- Anbindung von Hardware-Wallets (BitBox02)


## 3. Eigenverantwortung und Verwahrung

Die App ist eine Self-Custody-Lösung. Das bedeutet:
''';
