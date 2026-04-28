import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/app_constant.dart';
import '../model/member_model.dart';

class MemberController extends GetxController {
  final RxList<MemberModel> members = <MemberModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxString errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchMembers();
  }

  void fetchMembers() {
    FirebaseFirestore.instance
        .collection(AppConstant.collectionUsers)
        .snapshots()
        .listen(
      (snapshot) {
        isLoading.value = false;
        errorMessage.value = '';
        members.value = snapshot.docs.map((doc) {
          return MemberModel.fromMap(doc.data() as Map<String, dynamic>);
        }).toList();
      },
      onError: (error) {
        isLoading.value = false;
        errorMessage.value = error.toString();
      },
    );
  }
}
