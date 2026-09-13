import 'package:flutter/foundation.dart';

import '../models/auth_user.dart';
import 'auth_service.dart';

class AuthSession extends ChangeNotifier {
  AuthSession({AuthService? service}) : _service = service ?? AuthService();
  final AuthService _service;
  AuthUser? user;
  bool isLoading = true;

  Future<void> restore() async {
    user = await _service.restoreSession();
    isLoading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    user = await _service.login(email, password);
    notifyListeners();
  }

  Future<void> register({required String fullName, required String email, required String password}) => _service.register(fullName: fullName, email: email, password: password);

  Future<void> logout() async {
    await _service.logout();
    user = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }
}