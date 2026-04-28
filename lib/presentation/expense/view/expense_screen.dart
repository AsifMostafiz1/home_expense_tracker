import 'package:flutter/material.dart';
import '../../../common/widgets/custom_app_bar.dart';

class ExpenseScreen extends StatelessWidget {
  const ExpenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: CustomAppBar(
        title: 'Expense',
      ),
      body: Center(
        child: Text('Expense Screen'),
      ),
    );
  }
}
