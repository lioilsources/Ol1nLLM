import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/persona.dart';

class PersonaService {
  static const _indexPath = 'assets/personas/index.json';

  List<Persona>? _cachedList;
  final Map<String, String> _promptCache = {};

  Future<List<Persona>> list() async {
    if (_cachedList != null) return _cachedList!;
    final raw = await rootBundle.loadString(_indexPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final items = (json['personas'] as List)
        .map((e) => Persona.fromJson(e as Map<String, dynamic>))
        .toList();
    _cachedList = items;
    return items;
  }

  Future<Persona?> byId(String? id) async {
    if (id == null) return null;
    final all = await list();
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<String?> systemPrompt(String? personaId) async {
    if (personaId == null) return null;
    final cached = _promptCache[personaId];
    if (cached != null) return cached;
    final persona = await byId(personaId);
    if (persona == null) return null;
    final prompt = await rootBundle.loadString(persona.file);
    _promptCache[personaId] = prompt;
    return prompt;
  }
}

final personaServiceProvider = Provider<PersonaService>((_) => PersonaService());

final personaListProvider = FutureProvider<List<Persona>>((ref) async {
  return ref.read(personaServiceProvider).list();
});
