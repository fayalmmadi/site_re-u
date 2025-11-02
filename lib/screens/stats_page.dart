import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../controllers/voiture_selection.dart';
import 'package:flutter/services.dart'; // SystemUiOverlayStyle

class StatsPage extends StatefulWidget {
  const StatsPage({Key? key}) : super(key: key);
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with TickerProviderStateMixin {
  late final TabController _tabs;
  final _db = Supabase.instance.client;

  final Map<int, _LineData?> _cache = {};
  bool _loading = false;

  // palette & mise en page
  static const _bgCream = Color(0xFFF6F5F0);
  static const _green = Color(0xFF3C7C66);
  static const _gridGrey = Color(0xFFE7E6E1);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (!_tabs.indexIsChanging) _load(_tabs.index);
      });
    _load(0); // charge "Jour" par défaut
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ------------------------------- DATA -------------------------------

  Future<List<_Point>> _fetchRows(DateTime fromUtc, DateTime toUtc) async {
    final voitureId = VoitureSelection.voitureActuelle?['id'];
    if (voitureId == null) return [];

    final resp = await _db
        .from('passagers')
        .select('created_at, nombre_passagers')
        .eq('voiture_id', voitureId)
        .gte('created_at', fromUtc.toIso8601String()) // bornes en UTC
        .lt('created_at', toUtc.toIso8601String())
        .order('created_at', ascending: true);

    // v2 : resp est une List<dynamic>
    final list = List<Map<String, dynamic>>.from(resp as List);

    // convertit chaque timestamp reçu (UTC) en heure locale
    return list.map((m) {
      final raw = m['created_at'] as String;
      final dtLocal = DateTime.parse(raw).toLocal();
      final n = (m['nombre_passagers'] ?? 0) as int;
      return _Point(dtLocal, n);
    }).toList();
  }

  Future<int> _computeRecordGoal() async {
    final voitureId = VoitureSelection.voitureActuelle?['id'];
    if (voitureId == null) return 0;

    final resp = await _db
        .from('passagers')
        .select('created_at, nombre_passagers')
        .eq('voiture_id', voitureId)
        .order('created_at', ascending: true);

    final rows = List<Map<String, dynamic>>.from(resp as List);
    if (rows.isEmpty) return 0;

    // Reset si inactif > 3 mois
    final last = DateTime.parse(rows.last['created_at'] as String).toLocal();
    if (DateTime.now().difference(last).inDays > 90) return 0;

    // Record du nombre de passagers sur une journée (pour cette voiture)
    final perDay = <String, int>{};
    for (final m in rows) {
      final dt = DateTime.parse(m['created_at'] as String).toLocal();
      final k = DateTime(dt.year, dt.month, dt.day).toIso8601String();
      perDay[k] = (perDay[k] ?? 0) + ((m['nombre_passagers'] ?? 0) as int);
    }
    final maxDay = perDay.values.fold<int>(0, (a, b) => a > b ? a : b);

    return _roundUpToNice(maxDay.toDouble()).toInt();
  }

  Future<void> _load(int tabIndex) async {
    if (_cache[tabIndex] != null || _loading) return;
    setState(() => _loading = true);

    final nowLocal = DateTime.now();
    late DateTime fromLocal, toLocal;
    late _Group group;
    late String title;

    switch (tabIndex) {
      case 0: // Jour -> par heure
        fromLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);
        toLocal = fromLocal.add(const Duration(days: 1));
        group = _Group.hour;
        title = "Passagers par heure (aujourd’hui)";
        break;

      case 1: // Semaine -> par jour
        fromLocal = nowLocal.subtract(Duration(days: nowLocal.weekday - 1));
        fromLocal = DateTime(fromLocal.year, fromLocal.month, fromLocal.day);
        toLocal = fromLocal.add(const Duration(days: 7));
        group = _Group.day;
        title = "Passagers par jour (cette semaine)";
        break;

      case 2: // Mois -> par jour
        fromLocal = DateTime(nowLocal.year, nowLocal.month, 1);
        toLocal = (nowLocal.month == 12)
            ? DateTime(nowLocal.year + 1, 1, 1)
            : DateTime(nowLocal.year, nowLocal.month + 1, 1);
        group = _Group.day;
        title = "Passagers par jour (ce mois)";
        break;

      default: // Année -> par mois
        fromLocal = DateTime(nowLocal.year, 1, 1);
        toLocal = DateTime(nowLocal.year + 1, 1, 1);
        group = _Group.month;
        title = "Passagers par mois (cette année)";
    }

    // 1) Requête en UTC
    final rows = await _fetchRows(fromLocal.toUtc(), toLocal.toUtc());

    // 2) Objectif adaptatif selon l'onglet (on part d'un objectif/jour)
    final int goalDaily = await _computeRecordGoal();
    late int goal;

    if (tabIndex == 0) {
      goal = goalDaily; // Jour
    } else if (tabIndex == 1) {
      goal = goalDaily * 7; // Semaine
    } else if (tabIndex == 2) {
      final daysInMonth =
          DateUtils.getDaysInMonth(fromLocal.year, fromLocal.month);
      goal = goalDaily * daysInMonth; // Mois
    } else {
      final daysInYear = DateTime(fromLocal.year + 1, 1, 1)
          .difference(DateTime(fromLocal.year, 1, 1))
          .inDays;
      goal = goalDaily * daysInYear; // Année
    }

    // 3) Agrégation avec les bornes LOCALES (+ objectif)
    final data =
        _aggregate(rows, group, fromLocal, toLocal, title, goal: goal);

    _cache[tabIndex] = data;
    setState(() => _loading = false);
  }

  // Agrégation -> spots & axes
  _LineData _aggregate(
    List<_Point> rows,
    _Group g,
    DateTime from,
    DateTime to,
    String title, {
    int? goal,
  }) {
    final bool isMonthDays =
        g == _Group.day && from.day == 1 && (to.difference(from).inDays >= 28);

    final map = <int, int>{};
    for (final r in rows) {
      late int x;
      switch (g) {
        case _Group.hour:
          x = r.dt.hour; // 0..23
          break;
        case _Group.day:
          x = isMonthDays
              ? r.dt.day
              : r.dt.difference(from).inDays + 1; // 1..31 ou 1..7
          break;
        case _Group.month:
          x = r.dt.month; // 1..12
          break;
      }
      map[x] = (map[x] ?? 0) + r.n;
    }

    final int startX = (g == _Group.hour) ? 0 : 1;
    final int endX = (g == _Group.hour)
        ? 24
        : (g == _Group.day
            ? (isMonthDays
                ? DateUtils.getDaysInMonth(from.year, from.month)
                : to.difference(from).inDays)
            : 12);

    final spots = <FlSpot>[];
    int maxVal = 0;
    int total = 0;

    for (int x = startX; x <= endX; x++) {
      final y = (map[x] ?? 0).toDouble();
      spots.add(FlSpot(x.toDouble(), y));
      if (y > maxVal) maxVal = y.toInt();
      total += y.toInt();
    }

    final double maxY = _roundUpToNice(maxVal == 0 ? 10 : maxVal * 1.2);
    final double avg =
        (endX - startX + 1) == 0 ? 0 : total / (endX - startX + 1);

    return _LineData(
      spots,
      maxY,
      title,
      g,
      isMonthDays: isMonthDays,
      total: total,
      avg: avg,
      goal: goal,
    );
  }

  double _roundUpToNice(double x) {
    if (x <= 10) return 10;
    final bases = [1, 2, 5, 10];
    double m = 1;
    while (x > bases.last * m) m *= 10;
    for (final b in bases) {
      final t = b * m;
      if (x <= t) return t;
    }
    return 10 * m;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgCream,
      appBar: AppBar(
        backgroundColor: const Color(0xFF084C28),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Statistiques',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(width: 3, color: Colors.white),
            insets: EdgeInsets.symmetric(horizontal: 24),
          ),
          tabs: const [
            Tab(text: 'Jour'),
            Tab(text: 'Semaine'),
            Tab(text: 'Mois'),
            Tab(text: 'Année'),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: TabBarView(
            controller: _tabs,
            children: List.generate(4, _buildTab),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(int index) {
    final d = _cache[index];
    if (_loading && d == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (d == null) {
      return const Center(child: Text('Pas encore de données'));
    }

    // Libellés selon l'onglet
    String totalLabel, avgLabel;
    switch (index) {
      case 0:
        totalLabel = "Total aujourd'hui";
        avgLabel = "Moyenne/h";
        break;
      case 1:
        totalLabel = "Total cette semaine";
        avgLabel = "Moyenne/j";
        break;
      case 2:
        totalLabel = "Total ce mois";
        avgLabel = "Moyenne/j";
        break;
      default:
        totalLabel = "Total cette année";
        avgLabel = "Moyenne/mois";
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        children: [
          _card(
            title: d.title,
            child: SizedBox(height: 220, child: LineChart(_lineChart(d))),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _kpiCard('${d.total}', totalLabel)),
              const SizedBox(width: 12),
              Expanded(child: _kpiCard(d.avg.toStringAsFixed(1), avgLabel)),
              const SizedBox(width: 12),
              Expanded(child: _gaugeCard('Objectif', d.goal ?? 20, d.total)),
            ],
          ),
        ],
      ),
    );
  }

  // Carte blanche
  Widget _card({required String title, required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _kpiCard(String value, String label, {String? sub}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub,
                style:
                    const TextStyle(fontSize: 11, color: Colors.black54)),
          ]
        ],
      ),
    );
  }

  Widget _gaugeCard(String label, int goal, int current) {
    final p = (goal == 0) ? 0.0 : (current / goal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SizedBox(
            height: 70,
            child: PieChart(
              PieChartData(
                startDegreeOffset: 180,
                centerSpaceRadius: 26,
                sectionsSpace: 0,
                sections: [
                  PieChartSectionData(
                      value: p * 100, color: _green, radius: 10, showTitle: false),
                  PieChartSectionData(
                      value: (1 - p) * 100,
                      color: _green.withOpacity(.25),
                      radius: 10,
                      showTitle: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            goal == 0 ? 'Aucun objectif (inactif)' : 'Objectif $goal',
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  // Le graphique — identique à la maquette (grille H, courbe + zone)
  LineChartData _lineChart(_LineData d) => LineChartData(
        minY: 0,
        maxY: d.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (d.maxY / 5).clamp(2, 20).toDouble(),
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: _gridGrey, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),

          // Axe Y à gauche
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (d.maxY / 5).clamp(2, 20).toDouble(),
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ),

          // Axe X bas
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: 2,
              getTitlesWidget: (v, _) {
                final i = v.round();

                if (d.group == _Group.hour) {
                  if (i < 2 || i % 2 != 0) return const SizedBox.shrink();
                  return Text(i.toString().padLeft(2, '0'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black87));
                }

                if (d.group == _Group.day && d.isMonthDays) {
                  if (i < 2 || i % 2 != 0) return const SizedBox.shrink();
                  return Text(i.toString().padLeft(2, '0'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black87));
                }

                if (d.group == _Group.day && !d.isMonthDays) {
                  if (i < 2 || i % 2 != 0) return const SizedBox.shrink();
                  return Text(i.toString().padLeft(2, '0'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black87));
                }

                if (d.group == _Group.month) {
                  if (i < 2 || i % 2 != 0) return const SizedBox.shrink();
                  return Text(i.toString().padLeft(2, '0'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black87));
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: d.spots,
            isCurved: true,
            barWidth: 4,
            color: _green,
            belowBarData:
                BarAreaData(show: true, color: _green.withOpacity(.18)),
            dotData: FlDotData(show: false),
          )
        ],
      );
}

enum _Group { hour, day, month }

class _Point {
  final DateTime dt;
  final int n;
  _Point(this.dt, this.n);
}

class _LineData {
  final List<FlSpot> spots;
  final double maxY;
  final String title;
  final _Group group;
  final bool isMonthDays;

  // KPIs
  final int total;
  final double avg;
  final int? goal;

  _LineData(
    this.spots,
    this.maxY,
    this.title,
    this.group, {
    this.isMonthDays = false,
    this.total = 0,
    this.avg = 0.0,
    this.goal,
  });
}
