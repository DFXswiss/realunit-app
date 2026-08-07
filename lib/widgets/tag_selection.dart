import 'package:flutter/material.dart';
import 'package:realunit_wallet/styles/colors.dart';

class TagSelection<T> extends StatelessWidget {
  const TagSelection({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<(T, String, IconData?)> items;
  final T? selected;
  /// Pass `null` to disable every chip (Flutter's ChoiceChip pattern).
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: items.map((item) {
        final isSelected = selected == item.$1;
        return ChoiceChip(
          label: item.$3 != null
              ? Row(
                  mainAxisSize: .min,
                  spacing: 4.0,
                  children: [
                    Icon(
                      item.$3,
                      size: 18,
                      color: isSelected ? RealUnitColors.basic.white : RealUnitColors.neutral600,
                    ),
                    Flexible(
                      child: Text(
                        item.$2,
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ),
                  ],
                )
              : Text(item.$2),
          selected: isSelected,
          onSelected: onSelected == null ? null : (_) => onSelected!(item.$1),
          selectedColor: RealUnitColors.realUnitBlue,
          backgroundColor: RealUnitColors.basic.white,
          labelStyle: TextStyle(
            color: isSelected ? RealUnitColors.basic.white : RealUnitColors.neutral600,
          ),
          side: BorderSide(
            color: isSelected ? RealUnitColors.realUnitBlue : RealUnitColors.neutral200,
          ),
          showCheckmark: false,
          labelPadding: .zero,
        );
      }).toList(),
    );
  }
}
