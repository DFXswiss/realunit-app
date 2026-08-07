import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/form/dropdown_field.dart';

/// Selects how a [CountryField] gates its country list.
enum CountryFieldPurpose {
  nationality,
  residence
  ;

  bool allows(Country country) => switch (this) {
    // Nationality is a fact, not a permission: the backend routes a
    // disallowed nationality to manual review instead of rejecting it,
    // so the picker must offer every country.
    CountryFieldPurpose.nationality => true,
    CountryFieldPurpose.residence => country.kycAllowed,
  };
}

class CountryField extends StatefulWidget {
  final String label;
  final CountryFieldPurpose purpose;
  final Country? initialValue;
  final void Function(Country?)? onChanged;

  /// 2-letter country symbols to omit from the picker (e.g. already selected
  /// tax-residence rows). Matching is case-sensitive on [Country.symbol].
  final Set<String> excludeSymbols;

  const CountryField({
    super.key,
    required this.label,
    required this.purpose,
    this.initialValue,
    this.onChanged,
    this.excludeSymbols = const {},
  });

  @override
  State<CountryField> createState() => _CountryFieldState();
}

class _CountryFieldState extends State<CountryField> {
  final DfxCountryService countryService = getIt<DfxCountryService>();
  late Future<List<Country>> _countriesFuture;
  bool _initialValuePropagated = false;

  @override
  void initState() {
    super.initState();
    _countriesFuture = _loadCountries();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Country>>(
      future: _countriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _StatusField(
            label: widget.label,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: CupertinoActivityIndicator(),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return _StatusField(
            label: widget.label,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    S.of(context).countriesLoadFailed,
                    style: TextStyle(color: RealUnitColors.status.red600),
                  ),
                ),
                TextButton(
                  onPressed: _retry,
                  child: Text(S.of(context).retry),
                ),
              ],
            ),
          );
        }

        final countries = snapshot.data!
            .where(widget.purpose.allows)
            .where((c) => !widget.excludeSymbols.contains(c.symbol))
            .toList();
        final initial = widget.initialValue != null && countries.contains(widget.initialValue)
            ? widget.initialValue
            : null;

        // DropdownButtonFormField doesn't fire onChanged for initialValue, so push it once
        // after countries load to keep the parent's controller in sync with what's displayed.
        if (initial != null && !_initialValuePropagated) {
          _initialValuePropagated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChanged?.call(initial));
        }

        return DropdownField<Country>(
          hintText: S.of(context).countryHint,
          label: widget.label,
          items: countries.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
          initialValue: initial,
          onChanged: widget.onChanged,
          validator: (value) => value == null ? '' : null,
          autovalidateMode: AutovalidateMode.onUserInteraction,
        );
      },
    );
  }

  void _retry() {
    setState(() {
      _countriesFuture = _loadCountries();
    });
  }

  Future<List<Country>> _loadCountries() async {
    final countries = await countryService.getAllCountries();

    final priority = ['CH', 'DE', 'IT', 'FR'];

    // Sort a copy — the service hands out its shared cached list.
    final sorted = [...countries]..sort((a, b) {
      final aIndex = priority.indexOf(a.symbol.toUpperCase());
      final bIndex = priority.indexOf(b.symbol.toUpperCase());

      if (aIndex != -1 && bIndex != -1) {
        return aIndex.compareTo(bIndex);
      }

      if (aIndex != -1) return -1;
      if (bIndex != -1) return 1;

      return a.name.compareTo(b.name);
    });

    return sorted;
  }
}

/// A labeled container that always registers an *invalid* [FormField] while no
/// country can be selected (loading or error). This guarantees that
/// `Form.validate()` cannot return `true` before the user picks a country.
class _StatusField extends StatelessWidget {
  final String label;
  final Widget child;

  const _StatusField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 18 / 13,
            ),
          ),
        ),
        FormField<Country>(
          // No country is available yet, so the field is always invalid and
          // blocks the surrounding Form from validating.
          validator: (_) => '',
          builder: (state) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: state.hasError ? RealUnitColors.status.red600 : RealUnitColors.neutral300,
                ),
              ),
              child: child,
            );
          },
        ),
      ],
    );
  }
}
