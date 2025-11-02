// lib/pages/pending_status_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kBrand = Color(0xFF0B5E3B);
const _kPollEvery = Duration(seconds: 10);
const _kDecisionDelay = Duration(hours: 72);

class PendingStatusPage extends StatefulWidget {
  /// tableName attend en pratique 'partenaires' ou 'livreurs'
  final String tableName;          // 'partenaires' | 'livreurs'
  final String roleLabel;          // 'Partenaire' | 'Livreur'
  final String dashboardRoute;     // route vers le dashboard après approbation
  final String signupRoute;        // route pour refaire la demande (si refus)

  const PendingStatusPage({
    super.key,
    required this.tableName,
    required this.roleLabel,
    required this.dashboardRoute,
    required this.signupRoute,
  });

  @override
  State<PendingStatusPage> createState() => _PendingStatusPageState();
}

class _PendingStatusPageState extends State<PendingStatusPage> {
  Map<String, dynamic>? _row;
  Timer? _timer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_kPollEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Déduit un statut textuel robuste à partir des colonnes disponibles.
  /// - Si une colonne 'status' existe -> on la prend
  /// - Sinon on mappe est_valide / est_bloque vers approved / blocked
  /// - Sinon 'pending'
  String _deriveStatus(Map<String, dynamic>? row) {
    final r = row ?? const {};
    final hasStatusKey = r.containsKey('status');
    if (hasStatusKey && (r['status']?.toString().isNotEmpty ?? false)) {
      return r['status'].toString();
    }
    final estValide = r['est_valide'] == true;
    final estBloque = r['est_bloque'] == true;
    if (estValide) return 'approved';
    if (estBloque) return 'blocked';
    return 'pending';
  }

  DateTime _parseCreatedAt(Map<String, dynamic>? row) {
    final raw = (row?['created_at'] ?? '').toString();
    final dt = DateTime.tryParse(raw);
    // par défaut on reste en UTC pour la logique de délai
    return (dt ?? DateTime.now()).toUtc();
  }

  Future<void> _load() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      // On sélectionne explicitement les colonnes utiles.
      final row = await Supabase.instance.client
          .from(widget.tableName)
          .select('prenom, nom, phone, avatar_url, created_at, status, est_valide, est_bloque, user_id')
          .eq('user_id', uid)
          .maybeSingle() as Map<String, dynamic>?;

      if (!mounted) return;
      setState(() {
        _row = row;
        _loading = false;
      });

      // Si approuvé -> on redirige vers le dashboard
      if (_deriveStatus(_row) == 'approved' && mounted) {
        Navigator.pushReplacementNamed(context, widget.dashboardRoute);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur de chargement : $e')),
      );
    }
  }

  String _countdown72h(DateTime createdAt) {
    final end = createdAt.add(_kDecisionDelay);
    final now = DateTime.now().toUtc();
    final remain = end.difference(now);
    if (remain.isNegative) return 'Délai dépassé';
    final h = remain.inHours;
    final m = remain.inMinutes % 60;
    final s = remain.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}h '
           '${m.toString().padLeft(2, '0')}m '
           '${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final p = _row ?? {};
    final prenom = (p['prenom'] ?? '').toString();
    final nom = (p['nom'] ?? '').toString();
    final phone = (p['phone'] ?? '').toString();
    final avatarUrl = p['avatar_url'] as String?;
    final status = _deriveStatus(_row);
    final createdAt = _parseCreatedAt(_row);

    Color badge = Colors.orange;
    String label = 'Vérification en cours';
    if (status == 'approved') { badge = Colors.green;   label = 'Compte validé'; }
    if (status == 'rejected') { badge = Colors.red;     label = 'Refusé'; }
    if (status == 'blocked')  { badge = Colors.black87; label = 'Bloqué'; }

    final delayPassed = DateTime.now().toUtc().isAfter(createdAt.add(_kDecisionDelay));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: _kBrand,
        foregroundColor: Colors.white,
        title: Text('Statut ${widget.roleLabel}'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Carte profil
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: _kBrand.withOpacity(.1),
                                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: (avatarUrl == null || avatarUrl.isEmpty)
                                    ? const Icon(Icons.person, color: _kBrand, size: 36)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (('$prenom $nom').trim().isEmpty)
                                          ? email
                                          : '$prenom $nom',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(email, style: const TextStyle(color: Colors.grey)),
                                    if (phone.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.phone, size: 16),
                                          const SizedBox(width: 6),
                                          Text(phone),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: badge.withOpacity(.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: badge),
                                ),
                                child: Text(label,
                                    style: TextStyle(
                                        color: badge,
                                        fontWeight: FontWeight.w600)),
                              )
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Bloc message / countdown
                      Card(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _buildStatusBlock(
                            status: status,
                            createdAt: createdAt,
                            delayPassed: delayPassed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildStatusBlock({
    required String status,
    required DateTime createdAt,
    required bool delayPassed,
  }) {
    final df = DateFormat('dd/MM/yyyy HH:mm');

    if (status == 'approved') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('✅ Compte validé',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Créé le ${df.format(createdAt.toLocal())}'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.pushReplacementNamed(
                context, widget.dashboardRoute),
            child: Text('Accéder à mon espace ${widget.roleLabel.toLowerCase()}'),
          ),
        ],
      );
    }

    if (status == 'rejected' || status == 'blocked' || delayPassed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status == 'blocked' ? '⛔ Compte bloqué' : '❌ Demande refusée',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            status == 'blocked'
                ? 'Contacte le support si tu penses qu’il s’agit d’une erreur.'
                : 'Tu peux refaire une demande.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pushReplacementNamed(
                context, widget.signupRoute),
            child: const Text('Refaire une demande'),
          ),
        ],
      );
    }

    // pending + countdown
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('⏳ Vérification en cours…',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
          "Ton identité et tes informations sont en cours de vérification.\n"
          "Délai estimé : 72 heures maximum."
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.timer_outlined),
            const SizedBox(width: 8),
            Text(
              _countdown72h(createdAt),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Demande créée le ${DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toLocal())}'),
      ],
    );
  }
}
