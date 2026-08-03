import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/bloc/connect_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/connect_bitbox_view.dart';
import 'package:realunit_wallet/setup/di.dart';

class ConnectBitboxPage extends StatelessWidget {
  const ConnectBitboxPage({super.key, required this.onFinish, this.acquireWallet});

  final void Function(AWallet wallet) onFinish;
  final Future<BitboxWallet> Function()? acquireWallet;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ConnectBitboxCubit(
      getIt<BitboxService>(),
      getIt<WalletService>(),
      // DfxKycService is the smallest registered DFXAuthService — used only as
      // a transport for ensureSignatureFor(account); no KYC-specific calls here.
      getIt<DfxKycService>(),
      acquireWallet: acquireWallet,
    ),
    child: ConnectBitboxView(onFinish: onFinish),
  );
}
