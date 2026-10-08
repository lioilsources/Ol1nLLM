import 'package:flutter/material.dart';

import 'model.dart';

/// Search and facets for a style map. Pops with the chosen [StyleMapFilter]
/// (an empty one clears the filter), or with null when dismissed.
class StyleMapFilterSheet extends StatefulWidget {
  const StyleMapFilterSheet({
    super.key,
    required this.pack,
    required this.initial,
    this.valueLabel,
    this.textOf,
  });

  /// The whole set, unfiltered.
  final StyleMapPack pack;
  final StyleMapFilter initial;

  /// The name of a facet value, for the ones the pack only knows by id.
  final String Function(String key, StyleMapFacetValue value)? valueLabel;
  final String Function(StyleMapImage)? textOf;

  @override
  State<StyleMapFilterSheet> createState() => _StyleMapFilterSheetState();
}

class _StyleMapFilterSheetState extends State<StyleMapFilterSheet> {
  late StyleMapFilter _filter = widget.initial;
  late final _query = TextEditingController(text: widget.initial.query);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  int get _count => widget.pack.images
      .where((im) => _filter.matches(im, widget.pack, textOf: widget.textOf))
      .length;

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                // Never focused by itself: the chips below are the common
                // case and the keyboard would cover them.
                child: TextField(
                  controller: _query,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Hledat (umělec, styl, akvarel…)',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon: Icon(Icons.search, color: Colors.white54),
                    isDense: true,
                  ),
                  onChanged: (q) =>
                      setState(() => _filter = _filter.withQuery(q)),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final facet in widget.pack.facets) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 4),
                        child: Text(
                          facet.label,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final v in facet.values)
                            FilterChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                '${widget.valueLabel?.call(facet.key, v) ?? v.label} ${v.count}',
                              ),
                              selected:
                                  _filter.values[facet.key]?.contains(v.id) ??
                                  false,
                              onSelected: (_) {
                                FocusManager.instance.primaryFocus?.unfocus();
                                setState(
                                  () => _filter = _filter.toggled(
                                    facet.key,
                                    v.id,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        count == 0
                            ? 'Nic neodpovídá'
                            : '$count z ${widget.pack.images.length} obrázků',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(const StyleMapFilter()),
                      child: const Text('Zrušit filtr'),
                    ),
                    FilledButton(
                      onPressed: count == 0
                          ? null
                          : () => Navigator.of(context).pop(_filter),
                      child: const Text('Použít'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
