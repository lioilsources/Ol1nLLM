import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/theme.dart';
import '../models/persona.dart';
import '../providers/chat_provider.dart';
import '../services/persona_service.dart';

class PersonaPicker extends ConsumerWidget {
  const PersonaPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPersonas = ref.watch(personaListProvider);

    return asyncPersonas.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nepodařilo se načíst persony:\n$e',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      ),
      data: (personas) => _PersonaGrid(personas: personas),
    );
  }
}

class _PersonaGrid extends ConsumerWidget {
  final List<Persona> personas;
  const _PersonaGrid({required this.personas});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 720
            ? 4
            : constraints.maxWidth > 480
                ? 3
                : 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Column(
                  children: [
                    Text(
                      'Vyber si personu',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'S kým si dnes budeš povídat?',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.95,
                ),
                itemCount: personas.length,
                itemBuilder: (_, i) => _PersonaCard(
                  persona: personas[i],
                  onTap: () => ref
                      .read(chatProvider.notifier)
                      .selectPersona(personas[i].id),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PersonaCard extends StatelessWidget {
  final Persona persona;
  final VoidCallback onTap;

  const _PersonaCard({required this.persona, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(persona.emoji, style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text(
                persona.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                persona.description,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
