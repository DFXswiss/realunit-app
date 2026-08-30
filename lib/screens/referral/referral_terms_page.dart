import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_terms_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/load_referral_terms.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/web_view/web_view_page.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// Origin for root-relative TB links (`/downloads/…`).
const referralTermsLinkOrigin = 'https://realunit.ch';

/// TB links opened in the in-app browser. Mail and non-http(s) schemes
/// stay in the markdown (no WebView). Root-relative paths are folded onto
/// [referralTermsLinkOrigin]. Protocol-relative `//host/…` is https.
Uri? referralTermsInAppUri(String? href) {
  if (href == null) return null;
  final value = href.trim();
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'http' || scheme == 'https') return uri;
  if (value.startsWith('//')) {
    return Uri.tryParse('https:$value');
  }
  if (!uri.hasScheme && value.startsWith('/')) {
    return Uri.parse('$referralTermsLinkOrigin$value');
  }
  return null;
}

bool referralTermsOpensInApp(String? href) => referralTermsInAppUri(href) != null;

class ReferralTermsPage extends StatefulWidget {
  /// Pre-loaded markdown for golden tests.
  @visibleForTesting
  final String? initialMarkdownContent;

  /// Injected in tests so a Retry path can fail the bundled TB fallback.
  @visibleForTesting
  final Future<String> Function(String assetPath)? loadAsset;

  /// After the Empfehler has accepted, hide the checkbox and create CTA.
  /// Still loads GET /terms 1:1, then the bundled 14.08 TB.
  final bool readOnly;

  const ReferralTermsPage({
    super.key,
    this.initialMarkdownContent,
    this.loadAsset,
    this.readOnly = false,
  });

  @override
  State<ReferralTermsPage> createState() => _ReferralTermsPageState();
}

class _ReferralTermsPageState extends State<ReferralTermsPage> {
  String? _markdown;
  bool _loadFailed = false;
  bool _reloading = false;
  bool _accepted = false;
  String _termsVersion = ReferralTermsDto.bundledVersion;
  String? _loadedForLang;

  /// Bumped on every fetch so a slower earlier GET cannot overwrite a
  /// later language or Retry result.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialMarkdownContent != null) {
      _markdown = widget.initialMarkdownContent;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.initialMarkdownContent != null) return;
    final code = _languageCode();
    if (_loadedForLang == code) return;
    final reload = _loadedForLang != null;
    _loadedForLang = code;
    if (reload) {
      setState(() {
        _markdown = null;
        _loadFailed = false;
      });
    }
    _loadMarkdown();
  }

  String _languageCode() {
    if (getIt.isRegistered<SettingsBloc>()) {
      return getIt<SettingsBloc>().state.language.code;
    }
    return Localizations.localeOf(context).languageCode;
  }

  Future<void> _loadMarkdown() async {
    final generation = ++_loadGeneration;
    final code = _languageCode();
    String? apiText;
    try {
      if (getIt.isRegistered<RealUnitReferralService>()) {
        final terms = await getIt<RealUnitReferralService>().getTerms();
        if (!mounted || generation != _loadGeneration) return;
        if (terms.version.trim().isNotEmpty) {
          _termsVersion = terms.version;
        }
        apiText = terms.textForLang(code);
      }
    } catch (_) {
      // Bundled TB 14.08 is the fallback when the API is unreachable.
    }
    if (!mounted || generation != _loadGeneration) return;
    final content = await loadReferralTermsMarkdown(
      languageCode: code,
      loadAsset:
          widget.loadAsset ??
          ((path) => rootBundle.loadString(path, cache: false)),
      apiText: apiText,
    );
    if (!mounted || generation != _loadGeneration) return;
    if (content != null) {
      setState(() {
        _markdown = content;
        _loadFailed = false;
        _reloading = false;
      });
    } else {
      setState(() {
        _loadFailed = true;
        _reloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.referralTermsTitle)),
      body: SafeArea(
        child: widget.readOnly
            ? _layout(context, s, accepting: false, error: null)
            : BlocBuilder<ReferralCubit, ReferralState>(
                builder: (context, state) {
                  final accepting = state is ReferralTermsAccepting;
                  final error = state is ReferralNeedsTerms
                      ? state.errorMessage
                      : state is ReferralTermsAccepting
                      ? state.errorMessage
                      : null;
                  return _layout(
                    context,
                    s,
                    accepting: accepting,
                    error: error,
                  );
                },
              ),
      ),
    );
  }

  Widget _layout(
    BuildContext context,
    S s, {
    required bool accepting,
    required String? error,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ScrollableActionsLayout(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            if (_loadFailed) ...[
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 8,
                          children: [
                            Text(s.legalDocumentLoadFailed),
                            Text(
                              s.legalDocumentLoadFailedDescription,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: RealUnitColors.neutral500),
                            ),
                          ],
                        ),
                      ),
                      AppFilledButton(
                        label: s.retry,
                        autofocus: !_reloading,
                        variant: FilledButtonVariant.secondary,
                        state: _reloading
                            ? FilledButtonState.loading
                            : FilledButtonState.idle,
                        onPressed: accepting || _reloading
                            ? null
                            : () {
                                if (!_loadFailed || _reloading) return;
                                setState(() {
                                  _reloading = true;
                                  _accepted = false;
                                });
                                _loadMarkdown();
                              },
                      ),
                    ] else if (_markdown == null)
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Row(
                          spacing: 8,
                          children: [
                            const ExcludeSemantics(
                              child: CupertinoActivityIndicator(),
                            ),
                            Expanded(
                              child: Text(
                                s.referralTermsLoading,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: RealUnitColors.neutral500),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      MarkdownBody(
                        data: _markdown!,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          h2Padding: const EdgeInsets.only(top: 16),
                        ),
                        onTapLink: (text, href, title) {
                          final uri = referralTermsInAppUri(href);
                          if (uri == null) return;
                          context.pushNamed(
                            AppRoutes.webView,
                            extra: WebViewRouteParams(
                              title: text,
                              url: uri,
                            ),
                          );
                        },
                      ),
                    if (!widget.readOnly &&
                        accepting &&
                        (error == null || error.isEmpty))
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Row(
                          spacing: 8,
                          children: [
                            const ExcludeSemantics(
                              child: CupertinoActivityIndicator(),
                            ),
                            Expanded(
                              child: Text(
                                s.referralTermsAccepting,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: RealUnitColors.neutral500),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (!widget.readOnly &&
                        error != null &&
                        error.isNotEmpty)
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Text(
                          localizedReferralError(context, error),
                          style: TextStyle(color: RealUnitColors.status.red600),
                        ),
                      ),
                    if (!widget.readOnly &&
                        _markdown != null &&
                        !_loadFailed)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _accepted,
                        onChanged: accepting
                            ? null
                            : (v) => setState(() => _accepted = v ?? false),
                        title: Text(s.referralTermsCheckbox),
                      ),
                  ],
                ),
                actions: [
                  if (!widget.readOnly)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: AppFilledButton(
                        label: s.referralCreateInvite,
                        autofocus:
                            error != null &&
                            error.isNotEmpty &&
                            _accepted &&
                            !accepting,
                        state: accepting
                            ? FilledButtonState.loading
                            : FilledButtonState.idle,
                        onPressed:
                            _accepted &&
                                !accepting &&
                                _markdown != null &&
                                !_loadFailed
                            ? () => context.read<ReferralCubit>().acceptTerms(
                                version: _termsVersion,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            );
  }
}
