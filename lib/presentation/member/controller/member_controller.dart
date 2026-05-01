import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
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

  Future<void> makeCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      }
    } catch (e) {
      print('Could not launch $launchUri: $e');
    }
  }
}

