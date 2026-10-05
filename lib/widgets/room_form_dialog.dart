import 'package:flutter/material.dart';

import '../core/tokens.dart';
import 'app_text_field.dart';

/// Datos que devuelve [RoomFormDialog] al confirmar.
class RoomFormResult {
  const RoomFormResult({required this.name, required this.active});

  final String name;
  final bool active;
}

/// Diálogo para crear o editar una sala.
///
/// Es un widget con estado propio para que el `TextEditingController` se
/// cree y se libere (`dispose`) con el ciclo de vida del diálogo, también
/// durante su animación de cierre.
///
/// Si [initialActive] es `null` no se muestra el interruptor "Activa"
/// (caso de crear una sala, que siempre nace activa).
class RoomFormDialog extends StatefulWidget {
  const RoomFormDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.initialName = '',
    this.initialActive,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final bool? initialActive;

  @override
  State<RoomFormDialog> createState() => _RoomFormDialogState();
}

class _RoomFormDialogState extends State<RoomFormDialog> {
  late final TextEditingController _controller;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _active = widget.initialActive ?? true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(controller: _controller, label: 'Nombre de la sala'),
          if (widget.initialActive != null) ...[
            const SizedBox(height: AppTokens.spaceMD),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activa'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            RoomFormResult(name: _controller.text.trim(), active: _active),
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
