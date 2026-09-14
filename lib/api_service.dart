import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'hive/user.dart';

class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  ApiResponse({required this.success, this.data, this.message});
}

class ApiService {
  static const String _baseUrl = 'https://muerp.mahindrauniversity.edu.in';

  static Future<String> _getDeviceId(String username) async {
    final prefs = await SharedPreferences.getInstance();
    String? stored = prefs.getString('device_id_$username');
    if (stored != null) return stored;
    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
    await prefs.setString('device_id_$username', id);
    return id;
  }

  static String _extractJsVar(String html, String varName) {
    final pattern = varName + r"\s*=\s*'([^']*)'";
    return RegExp(pattern).firstMatch(html)?.group(1) ?? '';
  }

  static String _extractInputValue(String html, String inputId) {
    final pattern = 'id="$inputId"\\s+value="([^"]*)"';
    return RegExp(pattern).firstMatch(html)?.group(1) ?? '';
  }

  static Future<ApiResponse<User>> fetchUser(String username, String password) async {
    try {
      final loginResp = await http.post(
        Uri.parse('$_baseUrl/j_spring_security_check'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'okhttp/4.9.2',
        },
        body: 'j_username=${Uri.encodeComponent(username)}&j_password=${Uri.encodeComponent(password)}',
      );

      final location = loginResp.headers['location'] ?? '';
      if (!location.contains('home')) {
        return ApiResponse(success: false, message: 'Invalid credentials');
      }

      final rawCookie = loginResp.headers['set-cookie'] ?? '';
      final sessionMatch = RegExp(r'JSESSIONID=([^;]+)').firstMatch(rawCookie);
      if (sessionMatch == null) {
        return ApiResponse(success: false, message: 'No session created');
      }
      final sessionId = sessionMatch.group(1)!;

      final homeResp = await http.get(
        Uri.parse('$_baseUrl/stu_studentProfile.htm'),
        headers: {
          'Cookie': 'JSESSIONID=$sessionId',
          'User-Agent': 'okhttp/4.9.2',
        },
      );

      final html = homeResp.body;
      final fullName = _extractJsVar(html, 'juno.login_userFullName');
      final email = _extractJsVar(html, 'juno.login_emailId');

      // Extract course name from hidden input — gives "B.Tech AI", "B.Tech ECE" etc.
      final courseName = _extractInputValue(html, 'courseNameTemp');

      final userIdMatch = RegExp(r'"userId"\s*:\s*' + "'(" + r'\d+' + ")'").firstMatch(html);
      final userId = int.tryParse(userIdMatch?.group(1) ?? '0') ?? 0;
      final rollNo = email.split('@').first.toUpperCase();

      if (fullName.isEmpty) {
        return ApiResponse(success: false, message: 'Login failed — check credentials');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session_$username', sessionId);

      final user = User(
        name: fullName.trim(),
        rollNo: rollNo,
        studentId: userId,
        userId: userId,
        courseName: courseName.isNotEmpty ? courseName : 'Student',
      );

      return ApiResponse(success: true, data: user);
    } catch (e) {
      return ApiResponse(success: false, message: 'Error: $e');
    }
  }

  static Future<ApiResponse<String>> markAttendance(String at, String ld, String username) async {
    try {
      final deviceId = await _getDeviceId(username);
      final response = await http.get(
        Uri.parse('$_baseUrl/markAtt.json?at=$at&ld=$ld&deviceId=$deviceId'),
        headers: {
          'User-Agent': 'okhttp/4.9.2',
          'Accept': 'application/json',
        },
      );

      final body = response.body.trim();
      if (body.isEmpty) return ApiResponse(success: false, message: 'Empty response');
      final data = jsonDecode(body);
      return ApiResponse(success: true, data: data['responseMsg'] ?? 'Attendance marked');
    } catch (e) {
      return ApiResponse(success: false, message: 'Error: $e');
    }
  }
}