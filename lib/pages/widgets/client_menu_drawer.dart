import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../accepted_list_page.dart';
import '../refused_list_page.dart';
import '../rejected_list_page.dart';

class ClientMenuDrawer extends StatefulWidget {
  const ClientMenuDrawer({super.key, required this.clientId});
  final String clientId;

  @override
  State<ClientMenuDrawer> createState() => _ClientMenuDrawerState();
}

class _ClientMenuDrawerState extends State<ClientMenuDrawer> {
  final supa = Supabase.instance.client;

  int _acceptedN = 0;
  int _refusedN = 0;
  int _rejectedN = 0;

  @override
  void initState() {
    super.initState();
    _reloadCounters();
    // Optionnel : abonnement Realtime pour maj auto
    // _subscribeRealtime();
  }

  Future<void> _reloadCounters() async {
    final acc = await supa
        .from('livraison_demandes')
        .select('id', head: true, count: CountOption.exact)
        .eq('client_id', widget.clientId)
        .in_('status', ['accepted','accepted_by_driver'])
        .eq('client_seen_accepted', false);
    _acceptedN = acc.count ?? 0;

    final ref = await supa
        .from('livraison_demandes')
        .select('id', head: true, count: CountOption.exact)
        .eq('client_id', widget.clientId)
        .in_('status', ['refused','refused_by_driver'])
        .eq('client_seen_refused', false);
    _refusedN = ref.count ?? 0;

    final rej = await supa
        .from('livraison_demandes')
        .select('id', head: true, count: CountOption.exact)
        .eq('client_id', widget.clientId)
        .in_('status', ['client_rejected','canceled_by_client'])
        .eq('client_seen_rejected', false);
    _rejectedN = rej.count ?? 0;

    if (mounted) setState(() {});
  }

  // Optionnel si tu veux du “live”
  // void _subscribeRealtime() {
  //   supa.channel('livraisons_client_${widget.clientId}')
  //     ..onPostgresChanges(
  //       event: PostgresChangeEvent.any,
  //       schema: 'public',
  //       table: 'livraison_demandes',
  //       filter: PostgresChangeFilter(
  //         type: PostgresChangeFilterType.eq,
  //         column: 'client_id',
  //         value: widget.clientId,
  //       ),
  //       callback: (_) async => _reloadCounters(),
  //     )
  //     ..subscribe();
  // }

  Future<void> _openAndRefresh(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    await _reloadCounters(); // ← retombe à 0 après lecture
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            // En-tête (adapte à ton design)
            const ListTile(
              leading: CircleAvatar(child: Text('CJ')),
              title: Text('Carnegui Juice'),
              subtitle: Text('Tel: ********7733'),
            ),
            const Divider(),

            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Row(
                children: [
                  const Expanded(child: Text('Demandes acceptées')),
                  if (_acceptedN > 0)
                    CircleAvatar(radius: 12, child: Text('$_acceptedN', style: TextStyle(fontSize: 12))),
                ],
              ),
              onTap: () => _openAndRefresh(AcceptedListPage(clientId: widget.clientId)),
            ),

            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: Row(
                children: [
                  const Expanded(child: Text('Demandes refusées')),
                  if (_refusedN > 0)
                    CircleAvatar(radius: 12, child: Text('$_refusedN', style: TextStyle(fontSize: 12))),
                ],
              ),
              onTap: () => _openAndRefresh(RefusedListPage(clientId: widget.clientId)),
            ),

            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: Row(
                children: [
                  const Expanded(child: Text("Rejets d'acceptation")),
                  if (_rejectedN > 0)
                    CircleAvatar(radius: 12, child: Text('$_rejectedN', style: TextStyle(fontSize: 12))),
                ],
              ),
              onTap: () => _openAndRefresh(RejectedListPage(clientId: widget.clientId)),
            ),

            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Déconnexion'),
              onTap: () {/* ... */},
            ),
          ],
        ),
      ),
    );
  }
}
