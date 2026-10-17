import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

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

  Future<void> refreshProfile() async {
    final current = user;
    final updated = await _service.getProfile();
    if (user != current || current == null) return;
    user = updated;
    notifyListeners();
  }

  Future<void> updateProfile({required String fullName, required String email, String? phoneNumber}) async {
    final current = user;
    final updated = await _service.updateProfile(fullName: fullName, email: email, phoneNumber: phoneNumber);
    if (user != current || current == null) return;
    user = updated;
    notifyListeners();
  }

  Future<void> uploadProfilePhoto(XFile file) async {
    final current = user;
    final updated = await _service.uploadProfilePhoto(file);
    if (user != current || current == null) return;
    user = updated;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }
}
