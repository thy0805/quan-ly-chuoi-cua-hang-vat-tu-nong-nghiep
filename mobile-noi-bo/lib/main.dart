import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/api_client.dart';
import 'auth/auth_controller.dart';
import 'auth/session_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final controller = AuthController(
      ApiClient.fromEnvironment(),
      SecureSessionStore(),
    );
    runApp(MobileApp(controller: controller));
    controller.restore();
  } on ApiFailure catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(error.message),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
