import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../view/personal_finance_screen.dart';

/// The way into a member's own books from the home tabs.
///
/// Deliberately the loudest thing in the app bar: filled rather than tinted,
/// with the same primary-and-shadow treatment the segmented controls use for
/// their selected state. A private ledger nobody can find is a private ledger
/// nobody keeps, and the profile menu is three taps away.
class LedgerAppBarButton extends StatelessWidget {
  const LedgerAppBarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Material(
          color: primary,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          elevation: 3,
          shadowColor: primary.withOpacity(0.45),
          child: InkWell(
            onTap: () => Get.to(() => const PersonalFinanceScreen()),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 7, 13, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'my_ledger'.tr,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
