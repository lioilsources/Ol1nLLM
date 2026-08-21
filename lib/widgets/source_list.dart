import 'package:flutter/material.dart';
import '../core/constants/theme.dart';
import '../models/library_source.dart';

/// Collapsible "📖 Zdroje" section under a library (RAG) answer.
///
/// Deliberately not an [ExpansionTile]: that brings its own dividers and
/// ListTile padding, which fight the tight padding of the surrounding bubble.
class SourceList extends StatefulWidget {
  final List<LibrarySource> sources;

  const SourceList({super.key, required this.sources});

  @override
  State<SourceList> createState() => _SourceListState();
}

class _SourceListState extends State<SourceList> {
  // Collapsed by default; not persisted — an answer's citations are a detail
  // you open on demand, not a preference.
  bool _expanded = false;

  void _showExcerpt(BuildContext context, LibrarySource source) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                source.label,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (source.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  source.subtitle,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    source.excerpt.isEmpty
                        ? '(úryvek nedorazil)'
                        : source.excerpt,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              if (source.path != null) ...[
                const SizedBox(height: 12),
                Text(
                  source.path!,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.sources;
    if (sources.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(color: Colors.white12, height: 16),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '📖 Zdroje (${sources.length})',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 150),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 4),
              for (final source in sources) _buildRow(context, source),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, LibrarySource source) {
    return InkWell(
      onTap: () => _showExcerpt(context, source),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    source.label,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  if (source.subtitle.isNotEmpty)
                    Text(
                      source.subtitle,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            if (source.distance != null) ...[
              const SizedBox(width: 8),
              // Vector distance, NOT a similarity score: lower is a closer
              // match. Shown raw on purpose — inverting it into a "% match"
              // would invent a scale the retriever never produced.
              Text(
                source.distance!.toStringAsFixed(2),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
