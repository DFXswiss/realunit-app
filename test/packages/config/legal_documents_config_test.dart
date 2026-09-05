import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/config/legal_documents_config.dart';
import 'package:realunit_wallet/screens/legal/subpages/legal_document_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/web_view/web_view_page.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/legal_routes.dart';
import 'package:realunit_wallet/styles/language.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState> implements SettingsBloc {}

/// Records every [launchUrl] call so each test can assert what the production
/// `onTap` requested without driving a real platform channel.
class _RecordingUrlLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final List<({String url, LaunchOptions options})> calls = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    // The production code calls the modern [launchUrl] overload, but the
    // platform-interface contract requires this legacy method to exist.
    calls.add((url: url, options: const LaunchOptions()));
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    calls.add((url: url, options: options));
    return true;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => false;
}

/// Wraps a child in a [GoRouter] that captures the route the [DocumentConfig]
/// navigates to. Both the legal-document and the in-app web-view routes are
/// declared so `pushNamed` resolves; both push their `extra` payload into the
/// shared lists so tests can assert on the params.
GoRouter _routerFor({
  required Widget child,
  List<LegalDocumentParams>? legalParams,
  List<WebViewRouteParams>? webParams,
}) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => child),
      GoRoute(
        path: '/legal-doc',
        name: LegalRoutes.document,
        builder: (_, state) {
          legalParams?.add(state.extra! as LegalDocumentParams);
          return const _RoutePlaceholder('legal');
        },
      ),
      GoRoute(
        path: '/web-view',
        name: AppRoutes.webView,
        builder: (_, state) {
          webParams?.add(state.extra! as WebViewRouteParams);
          return const _RoutePlaceholder('web');
        },
      ),
    ],
  );
}

class _RoutePlaceholder extends StatelessWidget {
  const _RoutePlaceholder(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(body: Text(label));
}

Widget _harness(GoRouter router) {
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: const [
      S.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: S.delegate.supportedLocales,
  );
}

/// Builds a button that fires [config.onTap] against the page-level context.
class _TapButton extends StatelessWidget {
  const _TapButton(this.config);
  final DocumentConfig config;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => config.onTap(context),
          child: Text(config.title(context)),
        ),
      ),
    );
  }
}

void main() {
  group('$LegalDocumentConfig', () {
    test('isExternal is false (legal docs render in-app)', () {
      final cfg = LegalDocumentConfig(
        icon: Icons.shield_outlined,
        title: (_) => 'Privacy',
        assetBaseName: 'privacy_policy',
      );

      expect(cfg.isExternal, isFalse);
      expect(cfg.icon, Icons.shield_outlined);
    });

    testWidgets(
      'title resolves the localized string from BuildContext',
      (tester) async {
        final cfg = LegalDocumentsConfig.primaryDocuments
            .whereType<LegalDocumentConfig>()
            .firstWhere((c) => c.assetBaseName == 'privacy_policy');

        final captured = <String>[];
        final router = _routerFor(
          child: Builder(
            builder: (context) {
              captured.add(cfg.title(context));
              return const SizedBox.shrink();
            },
          ),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_harness(router));

        expect(captured, isNotEmpty);
        expect(captured.single, isNotEmpty);
      },
    );

    testWidgets(
      'onTap pushes LegalRoutes.document with a LegalDocumentParams payload',
      (tester) async {
        final cfg = LegalDocumentsConfig.primaryDocuments
            .whereType<LegalDocumentConfig>()
            .firstWhere((c) => c.assetBaseName == 'registration_agreement');

        final captured = <LegalDocumentParams>[];
        final router = _routerFor(
          child: _TapButton(cfg),
          legalParams: captured,
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(_harness(router));
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();

        expect(captured, hasLength(1));
        expect(captured.single.assetBaseName, 'registration_agreement');
        expect(captured.single.title, isNotEmpty);
        // The registration-agreement entry ships its own per-language PDF map.
        expect(captured.single.pdfUrls, isNotNull);
        expect(captured.single.pdfUrls!.keys, containsAll(['de', 'en']));
      },
    );

    testWidgets('onTap forwards a null pdfUrls map for docs without a PDF', (tester) async {
      final cfg = LegalDocumentsConfig.primaryDocuments.whereType<LegalDocumentConfig>().firstWhere(
        (c) => c.assetBaseName == 'privacy_policy',
      );

      final captured = <LegalDocumentParams>[];
      final router = _routerFor(child: _TapButton(cfg), legalParams: captured);
      addTearDown(router.dispose);

      await tester.pumpWidget(_harness(router));
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(captured.single.pdfUrls, isNull);
    });
  });

  group('$WebDocumentConfig', () {
    late _RecordingUrlLauncher launcher;
    late UrlLauncherPlatform originalLauncher;

    setUp(() {
      originalLauncher = UrlLauncherPlatform.instance;
      launcher = _RecordingUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    tearDown(() {
      UrlLauncherPlatform.instance = originalLauncher;
    });

    test('isExternal mirrors the openExternally flag', () {
      final external = WebDocumentConfig(
        icon: Icons.article_outlined,
        title: (_) => 'External',
        url: (_) => 'https://example.com',
        openExternally: true,
      );
      final internal = WebDocumentConfig(
        icon: Icons.article_outlined,
        title: (_) => 'Internal',
        url: (_) => 'https://example.com',
      );

      expect(external.isExternal, isTrue);
      expect(internal.isExternal, isFalse);
    });

    testWidgets('openExternally:true → launches the URL via url_launcher', (tester) async {
      final cfg = LegalDocumentsConfig.informationalDocuments
          .whereType<WebDocumentConfig>()
          .firstWhere(
            (c) => c.openExternally,
            orElse: () => throw StateError('expected at least one external doc'),
          );

      final router = _routerFor(child: _TapButton(cfg));
      addTearDown(router.dispose);

      await tester.pumpWidget(_harness(router));
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(launcher.calls, hasLength(1));
      expect(launcher.calls.single.url, startsWith('https://'));
      expect(launcher.calls.single.options.mode, PreferredLaunchMode.externalApplication);
    });

    testWidgets(
      'openExternally:false → pushes AppRoutes.webView with a WebViewRouteParams',
      (tester) async {
        // Aktionariat-Terms is in-app (openExternally defaults to false).
        final cfg = AktionariatDocumentsConfig.allDocuments.whereType<WebDocumentConfig>().first;
        expect(cfg.isExternal, isFalse);

        final captured = <WebViewRouteParams>[];
        final router = _routerFor(child: _TapButton(cfg), webParams: captured);
        addTearDown(router.dispose);

        await tester.pumpWidget(_harness(router));
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();

        expect(launcher.calls, isEmpty);
        expect(captured, hasLength(1));
        expect(captured.single.title, isNotEmpty);
        expect(captured.single.url.scheme, 'https');
      },
    );
  });

  group('$LegalDocumentsConfig static lists', () {
    test('allDocuments concatenates primary + informational in that order', () {
      final all = LegalDocumentsConfig.allDocuments;
      final primary = LegalDocumentsConfig.primaryDocuments;
      final info = LegalDocumentsConfig.informationalDocuments;

      expect(all.length, primary.length + info.length);
      expect(all.take(primary.length).toList(), primary);
      expect(all.skip(primary.length).toList(), info);
    });

    test('primaryDocuments are all LegalDocumentConfig (in-app PDFs)', () {
      expect(
        LegalDocumentsConfig.primaryDocuments,
        everyElement(isA<LegalDocumentConfig>()),
      );
      expect(
        LegalDocumentsConfig.primaryDocuments.every((d) => !d.isExternal),
        isTrue,
      );
    });

    test('informationalDocuments are external WebDocumentConfigs', () {
      expect(
        LegalDocumentsConfig.informationalDocuments,
        everyElement(isA<WebDocumentConfig>()),
      );
      expect(
        LegalDocumentsConfig.informationalDocuments.every((d) => d.isExternal),
        isTrue,
      );
    });

    testWidgets('every static entry exposes a non-empty localized title', (tester) async {
      final titles = <String>[];
      final router = _routerFor(
        child: Builder(
          builder: (context) {
            for (final doc in LegalDocumentsConfig.allDocuments) {
              titles.add(doc.title(context));
            }
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_harness(router));

      expect(titles, hasLength(LegalDocumentsConfig.allDocuments.length));
      expect(titles.every((t) => t.isNotEmpty), isTrue);
    });

    testWidgets(
      'every informational entry resolves to an https realunit.ch or .de URL',
      (tester) async {
        final urls = <String>[];
        final router = _routerFor(
          child: Builder(
            builder: (context) {
              for (final doc
                  in LegalDocumentsConfig.informationalDocuments.whereType<WebDocumentConfig>()) {
                urls.add(doc.url(context));
              }
              return const SizedBox.shrink();
            },
          ),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_harness(router));

        expect(
          urls,
          hasLength(LegalDocumentsConfig.informationalDocuments.length),
        );
        expect(
          urls,
          everyElement(
            allOf(
              startsWith('https://realunit.'),
              anyOf(contains('realunit.ch'), contains('realunit.de')),
            ),
          ),
        );
      },
    );
  });

  group('$AktionariatDocumentsConfig', () {
    test('exposes exactly the four in-app documents', () {
      final docs = AktionariatDocumentsConfig.allDocuments;
      expect(docs, hasLength(4));
      expect(docs, everyElement(isA<WebDocumentConfig>()));
      // None of the Aktionariat documents open externally.
      expect(docs.every((d) => !d.isExternal), isTrue);
    });

    testWidgets('each URL resolves to a non-empty https aktionariat.com link', (tester) async {
      final urls = <String>[];
      final titles = <String>[];
      final router = _routerFor(
        child: Builder(
          builder: (context) {
            for (final doc
                in AktionariatDocumentsConfig.allDocuments.whereType<WebDocumentConfig>()) {
              urls.add(doc.url(context));
              titles.add(doc.title(context));
            }
            return const SizedBox.shrink();
          },
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_harness(router));

      expect(urls, hasLength(4));
      expect(
        urls,
        everyElement(allOf(startsWith('https://'), contains('aktionariat.com'))),
      );
      // The four title getters must all resolve to a distinct localized string.
      expect(titles, hasLength(4));
      expect(titles.toSet().length, 4);
      expect(titles.every((t) => t.isNotEmpty), isTrue);
    });
  });

  group('$DfxDocumentsConfig', () {
    late _MockSettingsBloc settingsBloc;

    setUp(() {
      settingsBloc = _MockSettingsBloc();
    });

    Widget wrap(Widget child) => BlocProvider<SettingsBloc>.value(
      value: settingsBloc,
      child: child,
    );

    testWidgets('URLs interpolate the current language code from SettingsBloc', (tester) async {
      when(() => settingsBloc.state).thenReturn(const SettingsState(language: Language.de));

      final urls = <String>[];
      final router = _routerFor(
        child: wrap(
          Builder(
            builder: (context) {
              for (final doc in DfxDocumentsConfig.allDocuments.whereType<WebDocumentConfig>()) {
                urls.add(doc.url(context));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_harness(router));

      expect(urls, hasLength(4));
      expect(
        urls,
        everyElement(
          allOf(
            startsWith('https://docs.dfx.swiss/de/'),
            endsWith('.html'),
          ),
        ),
      );
    });

    testWidgets('switching to English language re-evaluates every URL builder', (tester) async {
      when(() => settingsBloc.state).thenReturn(const SettingsState(language: Language.en));

      final urls = <String>[];
      final router = _routerFor(
        child: wrap(
          Builder(
            builder: (context) {
              for (final doc in DfxDocumentsConfig.allDocuments.whereType<WebDocumentConfig>()) {
                urls.add(doc.url(context));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_harness(router));

      expect(
        urls,
        everyElement(startsWith('https://docs.dfx.swiss/en/')),
      );
      // The four DFX documents map to the four documented HTML endpoints.
      expect(
        urls.map((u) => u.split('/').last).toSet(),
        {'tnc.html', 'privacy.html', 'disclaimer.html', 'imprint.html'},
      );
    });

    testWidgets('titles resolve from the localized strings, not the URL builder', (tester) async {
      when(() => settingsBloc.state).thenReturn(const SettingsState());

      final titles = <String>[];
      final router = _routerFor(
        child: wrap(
          Builder(
            builder: (context) {
              for (final doc in DfxDocumentsConfig.allDocuments) {
                titles.add(doc.title(context));
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_harness(router));

      expect(titles, hasLength(4));
      expect(titles.every((t) => t.isNotEmpty), isTrue);
    });
  });
}
