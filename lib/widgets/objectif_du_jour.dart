// lib/widgets/objectif_du_jour.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/voiture_selection.dart';

class ObjectifDuJourCard extends StatefulWidget {
  /// Optionnel : si tu ne passes rien, on utilise VoitureSelection.voitureActuelle?['id']
  final String? voitureId;
  const ObjectifDuJourCard({Key? key, this.voitureId}) : super(key: key);

  @override
  State<ObjectifDuJourCard> createState() => _ObjectifDuJourCardState();
}

class _ObjectifDuJourCardState extends State<ObjectifDuJourCard> {
  static const _green = Color(0xFF3C7C66);
  int? _todayTotal;
  int? _todayGoal;
  bool _loading = false;

  SupabaseClient get _db => Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _passagersSub;

  void _subscribeRealtime() {
    // stop ancienne écoute si elle existe
    _passagersSub?.cancel();

    final vId = _resolvedVoitureId;
    if (vId == null) return;

    _passagersSub = _db
        .from('passagers')
        .stream(primaryKey: ['id'])
        .eq('voiture_id', vId)
        .listen((rows) {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));

      for (final r in rows) {
        final createdAt = (r['created_at'] as String?) ?? '';
        if (createdAt.isEmpty) continue;
        final dt = DateTime.parse(createdAt).toLocal();
        if (dt.isAfter(start) && dt.isBefore(end)) {
          _load(); // refresh jauge
          break;
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void didUpdateWidget(covariant ObjectifDuJourCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.voitureId != oldWidget.voitureId) {
      _subscribeRealtime(); // réabonne sur la bonne voiture
      _load();              // recalcule total + objectif
    }
  }

  @override
  void dispose() {
    _passagersSub?.cancel(); // ✅
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);

    final total = await _fetchTodayTotal();
    final goal  = await _computeDailyGoal();

    if (!mounted) return;
    setState(() {
      _todayTotal = total;
      _todayGoal  = goal;
      _loading = false;
    });
  }

  String? get _resolvedVoitureId {
    if (widget.voitureId != null) return widget.voitureId;
    final v = VoitureSelection.voitureActuelle;
    return v == null ? null : v['id']?.toString();
  }

  /// Total scanné aujourd’hui (en local) pour la voiture
  Future<int> _fetchTodayTotal() async {
    final voitureId = _resolvedVoitureId;
    if (voitureId == null) return 0;

    final now = DateTime.now();
    final fromLocal = DateTime(now.year, now.month, now.day);
    final toLocal   = fromLocal.add(const Duration(days: 1));

    final resp = await _db
        .from('passagers')
        .select('nombre_passagers, created_at')
        .eq('voiture_id', voitureId)
        .gte('created_at', fromLocal.toUtc().toIso8601String())
        .lt('created_at',  toLocal.toUtc().toIso8601String());

    // v2 : resp est List<dynamic>
    final rows = List<Map<String, dynamic>>.from(resp as List);
    return rows.fold<int>(
      0,
      (a, m) => a + ((m['nombre_passagers'] ?? 0) as int),
    );
    }

  /// Objectif du jour = meilleur total/jour des 30 derniers jours (reset si inactif > 90 jours)
  Future<int> _computeDailyGoal() async {
    final voitureId = _resolvedVoitureId;
    if (voitureId == null) return 0;

    final now = DateTime.now();

    // reset si inactif > 90 jours
    final since90 = now.subtract(const Duration(days: 90));
    final lastRow = await _db
        .from('passagers')
        .select('created_at')
        .eq('voiture_id', voitureId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle(); // v2

    if (lastRow == null) return 0;
    final lastAt = DateTime.parse(lastRow['created_at'] as String).toLocal();
    if (lastAt.isBefore(since90)) return 0;

    // fenêtre 30 jours (en UTC côté requête)
    final from30 = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 30));
    final to     = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));

    final resp = await _db
        .from('passagers')
        .select('created_at, nombre_passagers')
        .eq('voiture_id', voitureId)
        .gte('created_at', from30.toUtc().toIso8601String())
        .lt('created_at',  to.toUtc().toIso8601String());

    final rows = List<Map<String, dynamic>>.from(resp as List);

    // groupe par jour (local) -> max/jour
    final perDay = <String, int>{};
    for (final row in rows) {
      final dtLocal = DateTime.parse(row['created_at'] as String).toLocal();
      final key = DateTime(dtLocal.year, dtLocal.month, dtLocal.day)
          .toIso8601String();
      perDay[key] = (perDay[key] ?? 0) + ((row['nombre_passagers'] ?? 0) as int);
    }
    if (perDay.isEmpty) return 0;

    int maxDay = 0;
    for (final v in perDay.values) {
      if (v > maxDay) maxDay = v;
    }
    return maxDay;
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedVoitureId == null) {
      return _shell(
        child: const Center(child: Text("Aucune voiture sélectionnée")),
      );
    }
    if (_loading || _todayGoal == null || _todayTotal == null) {
      return _shell(child: const Center(child: CircularProgressIndicator()));
    }
    return _card(current: _todayTotal!, goal: _todayGoal!);
  }

  Widget _shell({required Widget child}) {
    return Container(
      width: 280,
      height: 130,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(.07),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: child,
    );
  }

  Widget _card({required int current, required int goal}) {
    final p = goal <= 0 ? 0.0 : (current / goal).clamp(0.0, 1.0);
    return Container(
      width: 280,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(.07),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Objectif du jour',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        startDegreeOffset: -90,
                        sectionsSpace: 0,
                        centerSpaceRadius: 26,
                        sections: [
                          PieChartSectionData(
                              value: p * 100,
                              color: _green,
                              radius: 10,
                              showTitle: false),
                          PieChartSectionData(
                              value: (1 - p) * 100,
                              color: _green.withOpacity(.2),
                              radius: 10,
                              showTitle: false),
                        ],
                      ),
                    ),
                    Text('$current',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal <= 0 ? 'Aucun objectif (inactif)' : 'sur $goal',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: p == 0 ? 0 : p,
                      minHeight: 6,
                      backgroundColor: _green.withOpacity(.15),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(_green),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
