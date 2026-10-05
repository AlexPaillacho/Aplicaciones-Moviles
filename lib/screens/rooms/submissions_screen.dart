import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../data/rooms_remote_source.dart';
import '../../models/audio_submission.dart';
import '../../services/api_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_view.dart';

/// Historial de los audios que el usuario envió a una sala, leído de la
/// base de datos (`GET /rooms/<id>/submissions`). Está paginado: se pide
/// una página y el botón "Cargar más" trae la siguiente.
class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  final int roomId;
  final String roomName;

  @override
  State<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<SubmissionsScreen> {
  static const int _pageSize = 10;

  final _remote = RoomsRemoteSource(ApiService.instance);

  final List<AudioSubmission> _items = [];
  int _page = 0;
  bool _hasMore = false;
  int _total = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await _remote.listSubmissions(
        widget.roomId,
        perPage: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.submissions);
        _page = page.page;
        _hasMore = page.hasMore;
        _total = page.total;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is NetworkException
            ? e.message
            : 'No se pudo cargar el historial. Intenta de nuevo.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _remote.listSubmissions(
        widget.roomId,
        page: _page + 1,
        perPage: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.submissions);
        _page = page.page;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar más: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Historial · ${widget.roomName}')),
      body: StatusView(
        loading: _isLoading,
        error: _error,
        onRetry: _loadFirstPage,
        isEmpty: _items.isEmpty,
        emptyMessage: 'Aún no has enviado audios en esta sala.\n'
            'Graba uno y aparecerá aquí.',
        builder: (context) => RefreshIndicator(
          onRefresh: _loadFirstPage,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppTokens.spaceMD),
            itemCount: _items.length + 1,
            separatorBuilder: (_, _) =>
                const SizedBox(height: AppTokens.spaceSM),
            itemBuilder: (context, index) {
              if (index < _items.length) {
                // Numeración propia del usuario: el más reciente lleva el
                // número más alto (el `id` de la base es global y no dice
                // nada al usuario).
                return _SubmissionTile(
                  submission: _items[index],
                  number: _total - index,
                );
              }
              return _buildFooter();
            },
          ),
        ),
      ),
    );
  }

  /// Pie de la lista: cuántos envíos se muestran y, si hay más, el botón
  /// para pedir la página siguiente.
  Widget _buildFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Mostrando ${_items.length} de $_total envíos',
          style: AppTokens.textCaption,
        ),
        if (_hasMore) ...[
          const SizedBox(height: AppTokens.spaceSM),
          AppButton(
            label: 'Cargar más',
            icon: Icons.expand_more,
            variant: AppButtonVariant.secondary,
            loading: _isLoadingMore,
            onPressed: _loadMore,
          ),
        ],
      ],
    );
  }
}

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile({required this.submission, required this.number});

  final AudioSubmission submission;
  final int number;

  @override
  Widget build(BuildContext context) {
    // Todo audio del historial ya está guardado: siempre check verde.
    const icon = Icons.check_circle_outline;
    const color = AppTokens.colorOnSuccessContainer;

    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppTokens.spaceSM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Audio $number', style: AppTokens.textBodyLarge),
                const SizedBox(height: AppTokens.spaceXS),
                Text('Duración: ${submission.durationLabel}',
                    style: AppTokens.textCaption),
                Text('Enviado: ${formatSubmissionDate(submission.createdAt)}',
                    style: AppTokens.textCaption),
              ],
            ),
          ),
          const SizedBox(width: AppTokens.spaceSM),
          Flexible(
            child: Text(
              submission.statusLabel,
              textAlign: TextAlign.end,
              style: AppTokens.textBody,
            ),
          ),
        ],
      ),
    );
  }
}

/// `dd/MM/yyyy HH:mm`, sin depender de `intl`.
String formatSubmissionDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}
