import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_message.dart';
import 'package:realunit_wallet/styles/colors.dart';

class SupportChatMessageBubble extends StatelessWidget {
  final SupportMessage supportMessage;

  const SupportChatMessageBubble({
    super.key,
    required this.supportMessage,
  });

  @override
  Widget build(BuildContext context) {
    final isFromCustomer = supportMessage.isFromCustomer;

    return Padding(
      padding: const .symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isFromCustomer ? .end : .start,
        children: [
          Column(
            crossAxisAlignment: isFromCustomer ? .end : .start,
            spacing: 2.0,
            children: [
              if (!isFromCustomer)
                Padding(
                  padding: const .only(left: 4),
                  child: Text(
                    S.of(context).supportChatSupportLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: RealUnitColors.neutral500,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const .symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isFromCustomer ? RealUnitColors.realUnitBlue : RealUnitColors.neutral100,
                  borderRadius: .circular(12),
                ),
                child: Column(
                  crossAxisAlignment: isFromCustomer ? .end : .start,
                  spacing: 4.0,
                  children: [
                    if (supportMessage.message != null)
                      Text(
                        supportMessage.message!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isFromCustomer ? RealUnitColors.basic.white : RealUnitColors.neutral900,
                        ),
                      ),
                    if (supportMessage.fileName != null)
                      Row(
                        mainAxisSize: .min,
                        spacing: 4.0,
                        children: [
                          Icon(
                            Icons.attach_file_rounded,
                            size: 16,
                            color: isFromCustomer
                                ? RealUnitColors.basic.white
                                : RealUnitColors.neutral900,
                          ),
                          Flexible(
                            child: Text(
                              supportMessage.fileName!,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: isFromCustomer
                                    ? RealUnitColors.basic.white
                                    : RealUnitColors.neutral900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    Text(
                      _formatTime(supportMessage.created),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isFromCustomer ? RealUnitColors.neutral300 : RealUnitColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime date) {
    // `date` is a UTC instant (the API sends `created` as a `Z`-suffixed
    // ISO-8601 string, parsed to a UTC `DateTime`). Convert it to the device's
    // local zone using the rules that applied on the message's own date, so a
    // message stays render-time-stable across DST boundaries — a March instant
    // always shows CET, a July instant always shows CEST. Adding
    // `DateTime.now().timeZoneOffset` instead would apply the *current* offset
    // to a historic instant and drift by an hour across the DST switch.
    final localDate = date.toLocal();
    return '${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
  }
}
