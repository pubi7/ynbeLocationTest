/// Захиалгын борлуулагчийн ID нь нэвтэрсэн хэрэглэгчийнхтэй таарах эсэх.
///
/// Сервер заримдаа Agent/Employee-ийн тоон `id`-г хадгалдаг, харин профайлд
/// өөр талбар (жишээ нь JWT `sub`) илүү гэж ирдэг — энгийн string харьцуулалт
/// буруу "өөрийн биш" гэж үзнэ.
bool orderSalespersonMatchesCurrentUser({
  required String orderSalespersonId,
  required String currentUserId,
  int? agentNumericIdFromPrefs,
}) {
  final sid = orderSalespersonId.trim();
  final uid = currentUserId.trim();
  if (uid.isEmpty || sid.isEmpty) return false;
  if (sid == uid) return true;

  final orderNum = int.tryParse(sid);
  if (orderNum != null &&
      agentNumericIdFromPrefs != null &&
      orderNum == agentNumericIdFromPrefs) {
    return true;
  }

  final userNum = int.tryParse(uid);
  if (userNum != null && orderNum != null && userNum == orderNum) {
    return true;
  }

  return false;
}
