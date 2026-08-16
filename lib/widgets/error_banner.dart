import 'package:flutter/material.dart';

/// Banner reutilizable para errores de red/backend.
///
/// Usado en `rooms_list_screen.dart` y `room_detail_screen.dart` (Fase 5)
/// cuando `errorMessage`/`_errorMessage` viene de una `RoomException` o
/// `NetworkException`.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
