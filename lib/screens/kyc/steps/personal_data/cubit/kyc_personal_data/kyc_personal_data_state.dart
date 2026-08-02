part of 'kyc_personal_data_cubit.dart';

abstract class KycPersonalDataState extends Equatable {
  const KycPersonalDataState();

  @override
  List<Object?> get props => [];
}

class KycPersonalDataInitial extends KycPersonalDataState {
  const KycPersonalDataInitial();
}

class KycPersonalDataLoading extends KycPersonalDataState {
  const KycPersonalDataLoading();
}

class KycPersonalDataSuccess extends KycPersonalDataState {
  const KycPersonalDataSuccess();
}

class KycPersonalDataFailure extends KycPersonalDataState {
  final String message;

  const KycPersonalDataFailure(this.message);

  @override
  List<Object?> get props => [message];
}
