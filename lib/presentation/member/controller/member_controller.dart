import 'package:get/get.dart';
import '../model/member_model.dart';
import '../repository/member_repository.dart';

class MemberController extends GetxController implements GetxService {
  final MemberRepository repository;

  MemberController({required this.repository});

  List<MemberModel> members = [];
  bool isLoading = true;
  String errorMessage = '';

  @override
  void onInit() {
    super.onInit();
    fetchMembers();
  }

  void fetchMembers() {
    repository.getMembersStream().listen(
      (membersList) {
        isLoading = false;
        errorMessage = '';
        members = membersList;
        update();
      },
      onError: (error) {
        isLoading = false;
        errorMessage = error.toString();
        update();
      },
    );
  }
}

