import 'package:realunit_wallet/screens/pay/pay_info_page.dart';

import '../../../helper/helper.dart';

void main() {
  goldenTest(
    'pay info disclosure',
    fileName: 'pay_info_page',
    constraints: phoneConstraints,
    builder: () => wrapForGolden(const PayInfoPage()),
  );
}
