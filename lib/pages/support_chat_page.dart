import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ⬇️ Ajoute CET import (types Realtime v2)
import 'package:realtime_client/realtime_client.dart'
    show PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType;

class SupportChatPage extends StatefulWidget {
  const SupportChatPage({super.key, required this.partnerId});
  final String partnerId;

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final supabase = Supabase.instance.client;

  RealtimeChannel? _chan;
  List<Map<String, dynamic>> messages = [];

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
    _load();
  }

  @override
  void dispose() {
    _chan?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime() {
    // nom lisible pour le debug, les quotes doivent entourer toute la chaîne
    _chan = supabase.channel('public:messages:partner:${widget.partnerId}');

    _chan!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      // ⬇️ NOUVEAU: filtre typé (plus de String 'user_id=eq.xxx')
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'partner_id',
        value: widget.partnerId,
      ),
      // payload v2: utilise .newRecord
      callback: (payload) {
        final newRec = payload.newRecord;
        if (newRec == null) return;

        // double sécurité côté client
        if ('${newRec['partner_id']}' != widget.partnerId) return;

        setState(() => messages.insert(0, Map<String, dynamic>.from(newRec)));
      },
    );

    _chan!.subscribe();
  }

  Future<void> _load() async {
    final res = await supabase
        .from('messages')
        .select('id, partner_id, sender_role, content, created_at')
        .eq('partner_id', widget.partnerId)
        .order('created_at', ascending: false)
        .limit(200);

    final list = (res as List)
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    if (!mounted) return;
    setState(() => messages = list);
  }

  @override
  Widget build(BuildContext context) {
    // … ton UI existant (ListView des messages, champ d’envoi, etc.)
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: ListView.builder(
        reverse: true,
        itemCount: messages.length,
        itemBuilder: (_, i) {
          final m = messages[i];
          return ListTile(
            title: Text(m['content']?.toString() ?? ''),
            subtitle: Text(m['sender_role']?.toString() ?? ''),
          );
        },
      ),
    );
  }
}
