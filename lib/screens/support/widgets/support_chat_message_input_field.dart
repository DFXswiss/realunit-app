import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';

class SupportChatMessageInputField extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final bool isTicketOpen;
  final XFile? attachment;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onRemoveAttachment;

  const SupportChatMessageInputField({
    super.key,
    required this.controller,
    required this.isSending,
    required this.isTicketOpen,
    required this.onSend,
    required this.onAttach,
    required this.onRemoveAttachment,
    this.attachment,
  });

  @override
  Widget build(BuildContext context) {
    if (!isTicketOpen) {
      return Container(
        width: .infinity,
        padding: const .all(20),
        color: RealUnitColors.neutral100,
        child: Text(
          S.of(context).supportTicketClosed,
          textAlign: .center,
          style:
              Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(
                color: RealUnitColors.neutral500,
                fontWeight: .w500,
              ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RealUnitColors.basic.white,
        border: const Border(
          top: BorderSide(color: RealUnitColors.neutral200),
        ),
      ),
      child: Column(
        mainAxisSize: .min,
        spacing: 8.0,
        children: [
          if (attachment != null)
            // Match the TextField below: filled neutral100, radius 8.
            Container(
              width: .infinity,
              padding: const .symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: RealUnitColors.neutral100,
                borderRadius: .circular(8.0),
              ),
              child: Row(
                spacing: 8.0,
                children: [
                  const Icon(
                    Icons.attach_file_rounded,
                    size: 18,
                    color: RealUnitColors.neutral500,
                  ),
                  Expanded(
                    child: Text(
                      attachment!.name,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: RealUnitColors.neutral600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: isSending ? null : onRemoveAttachment,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: RealUnitColors.neutral500,
                    ),
                    visualDensity: .compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: .zero,
                  ),
                ],
              ),
            ),
          Row(
            spacing: 8.0,
            children: [
              IconButton(
                onPressed: isSending ? null : onAttach,
                icon: const Icon(
                  Icons.attach_file_rounded,
                  color: RealUnitColors.realUnitBlue,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !isSending,
                  decoration: InputDecoration(
                    hintText: S.of(context).supportEnterMessage,
                    border: OutlineInputBorder(
                      borderRadius: .circular(8.0),
                      borderSide: .none,
                    ),
                    filled: true,
                    fillColor: RealUnitColors.neutral100,
                    contentPadding: const .all(12.0),
                  ),
                  maxLines: null,
                ),
              ),
              IconButton(
                onPressed: isSending ? null : onSend,
                icon: isSending
                    ? const CupertinoActivityIndicator()
                    : const Icon(Icons.send_rounded, color: RealUnitColors.realUnitBlue),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
