import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_support_service.dart';
import 'package:realunit_wallet/screens/support/cubits/support_tickets/support_tickets_cubit.dart';
import 'package:realunit_wallet/screens/support/cubits/support_tickets/support_tickets_state.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/routes/support_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/outlined_tile.dart';

class SupportTicketsPage extends StatelessWidget {
  const SupportTicketsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SupportTicketsCubit(
        getIt<DfxSupportService>(),
      ),
      child: const SupportTicketsView(),
    );
  }
}

class SupportTicketsView extends StatelessWidget {
  const SupportTicketsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).supportMyTickets),
      ),
      body: BlocBuilder<SupportTicketsCubit, SupportTicketsState>(
        builder: (context, state) {
          return switch (state) {
            SupportTicketsLoading() => const Center(
              child: CupertinoActivityIndicator(),
            ),
            SupportTicketsError(:final message) => Center(
              child: Text(message),
            ),
            SupportTicketsLoaded(:final tickets) =>
              tickets.isEmpty
                  ? Center(child: Text(S.of(context).supportNoTickets))
                  : ListView.separated(
                      padding: const .all(12),
                      itemCount: tickets.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final ticket = tickets.elementAt(index);
                        // `created` is parsed as UTC from the API; render it in
                        // the device's local time so the date is correct across
                        // the midnight boundary.
                        final created = ticket.created.toLocal();
                        return OutlinedTile(
                          leading: Padding(
                            padding: const .symmetric(vertical: 6.0),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: .circle,
                                color: ticket.isOpen
                                    ? RealUnitColors.green
                                    : RealUnitColors.neutral400,
                              ),
                            ),
                          ),
                          title: ticket.name,
                          subtitle:
                              '${created.day}.${created.month}.${created.year}',
                          onTap: () => context.pushNamed(
                            SupportRoutes.chat,
                            pathParameters: {'uid': ticket.uid},
                          ),
                          trailingIcon: Icons.chevron_right,
                        );
                      },
                    ),
            SupportTicketsInitial() => const SizedBox.shrink(),
          };
        },
      ),
    );
  }
}
