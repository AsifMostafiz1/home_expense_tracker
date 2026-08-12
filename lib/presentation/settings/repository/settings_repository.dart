import '../../member/model/member_model.dart';
import '../model/monthly_bill_model.dart';

abstract class SettingsRepository {
  /// Every month that has been set up, newest first.
  Future<List<MonthlyBillModel>> fetchMonthlyBills();

  /// The members the bills are split between — removed accounts excluded.
  Future<List<MemberModel>> fetchActiveMembers();

  /// The same list, live. A one-shot read can come back empty on a cold or
  /// offline start; the stream fills the split in as soon as the house data
  /// arrives, and follows it while the form is open.
  Stream<List<MemberModel>> watchActiveMembers();

  Future<void> saveMonthlyBill(String monthKey, Map<String, dynamic> data);

  Future<void> deleteMonthlyBill(String monthKey);
}
