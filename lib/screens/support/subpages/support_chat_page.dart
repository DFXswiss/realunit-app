import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_support_service.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_state.dart';
import 'package:realunit_wallet/screens/support/widgets/support_chat_message_bubble.dart';
import 'package:realunit_wallet/screens/support/widgets/support_chat_message_input_field.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/widgets/image_picker_sheet.dart';

class SupportChatPage extends StatelessWidget {
  final String ticketUid;

  const SupportChatPage({super.key, required this.ticketUid});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SupportChatCubit(
        getIt<DfxSupportService>(),
        ticketUid,
      ),
      child: const SupportChatView(),
    );
  }
}

class SupportChatView extends StatefulWidget {
  const SupportChatView({super.key});

  @override
  State<SupportChatView> createState() => _SupportChatViewState();
}

class _SupportChatViewState extends State<SupportChatView> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).supportChat),
      ),
      body: BlocConsumer<SupportChatCubit, SupportChatState>(
        listener: (context, state) {
          if (state is SupportChatLoaded) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          }
        },
        builder: (context, state) {
          return switch (state) {
            SupportChatLoading() => const Center(
              child: CupertinoActivityIndicator(),
            ),
            SupportChatError(:final message) => Center(
              child: Text(message),
            ),
            SupportChatLoaded(:final ticket, :final isSending, :final attachment) => SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const .all(12),
                      itemCount: ticket.messages.length,
                      itemBuilder: (context, index) => SupportChatMessageBubble(
                        supportMessage: ticket.messages.elementAt(index),
                      ),
                    ),
                  ),
                  SupportChatMessageInputField(
                    controller: _messageController,
                    isSending: isSending,
                    isTicketOpen: ticket.isOpen,
                    attachment: attachment,
                    onAttach: () async {
                      final file = await ImagePickerSheet.show(context);
                      if (file != null && context.mounted) {
                        context.read<SupportChatCubit>().selectAttachment(file);
                      }
                    },
                    onRemoveAttachment: () {
                      context.read<SupportChatCubit>().clearAttachment();
                    },
                    onSend: () async {
                      final message = _messageController.text;
                      final hasAttachment = attachment != null;
                      if (message.trim().isEmpty && !hasAttachment) return;
                      final cubit = context.read<SupportChatCubit>();
                      if (await cubit.sendMessage(message) && context.mounted) {
                        _messageController.clear();
                      }
                    },
                  ),
                ],
              ),
            ),
            SupportChatInitial() => const SizedBox.shrink(),
          };
        },
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
}
