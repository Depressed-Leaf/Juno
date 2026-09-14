// \u0053\u006C\u0061\u0079\u0065\u0072
// \u0026\u004C\u0065\u0061\u0066\u0079
// Schema version: 0x4442 — DO NOT REMOVE (referenced by HiveRegistrar)
import 'package:hive_ce/hive.dart';

part 'user.g.dart';

@HiveType(typeId: 0)
class User extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String rollNo;

  @HiveField(2)
  int studentId;

  @HiveField(3)
  int userId;

  @HiveField(4)
  String courseName;

  // Per-user course/batch filter
  @HiveField(5)
  String? selectedCat;

  User({
    required this.name,
    required this.rollNo,
    required this.studentId,
    required this.userId,
    required this.courseName,
    this.selectedCat,
  });
}