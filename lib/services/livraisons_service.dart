// lib/services/livraisons_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

/// Commission appliquée par l'app (10 %)
const double kAppRate = 0.10;

final supabase = Supabase.instance.client;

class LivraisonsService {
  const LivraisonsService();

  // ----- Utils -----
  double _commissionOf(num? price) {
    final p = (price ?? 0).toDouble();
    return double.parse((p * kAppRate).toStringAsFixed(2));
  }

  Future<String> _requireUserId() async {
    final u = supabase.auth.currentUser;
    if (u == null) throw Exception('Utilisateur non connecté.');
    return u.id;
  }

  // ======================================================================
  // 1) Lister les DEMANDES adressées à un livreur (table: livraison_demandes)
  // ======================================================================
  Future<List<Map<String, dynamic>>> fetchDemandesLivreur(String livreurId) async {
    final data = await supabase
        .from('livraison_demandes')
        .select('''
          id, client_id, livreur_id,
          depart_adresse, arrivee_adresse,
          prix_propose, devise, status, accepted_at, created_at,
          client_phone, client_nom, client_pays,
          commission_amount, objet
        ''')
        .eq('livreur_id', livreurId)
        .order('created_at', ascending: false);

    return (data as List).cast<Map<String, dynamic>>();
  }

  // ======================================================================================
  // 2) (Optionnel) Lister des jobs ouverts (si tu en as)
  //    -> livraisons.status = 'pending' et livraisons.livreur_id IS NULL
  // ======================================================================================
  Future<List<Map<String, dynamic>>> fetchOpenJobs() async {
    final data = await supabase
        .from('livraisons')
        .select('id, client_id, created_at, montant, status, livreur_id')
        .eq('status', 'pending')
        .isFilter('livreur_id', null) // méthode de supabase-dart
        .order('created_at', ascending: false);

    return (data as List).cast<Map<String, dynamic>>();
  }

  // =====================================================================================
  // 3) ACCEPTER une demande (source: livraison_demandes)
  //    -> crée une ligne dans livraisons en liant le BON livreur_id (table livreurs.id)
  //    -> met la demande à 'accepted'
  //    -> crédite le wallet via RPC add_commission(user_id, amount)
  // =====================================================================================
  Future<Map<String, dynamic>> accepterLivraison(String demandeId) async {
    final nowIso = DateTime.now().toIso8601String();
    final userId = await _requireUserId();

    // 1) Récupérer la demande
    final demande = await supabase
        .from('livraison_demandes')
        .select('id, client_id, livreur_id, prix_propose, devise, status')
        .eq('id', demandeId)
        .maybeSingle();

    if (demande == null) {
      throw Exception("Demande introuvable.");
    }
    if (demande['status'] != 'pending') {
      throw Exception("Demande déjà traitée (status=${demande['status']}).");
    }

    // 🔴 IMPORTANT : c’est l’ID de la table LIVREURS (pas auth.uid)
    String? livreurRowId = demande['livreur_id'] as String?;
    if (livreurRowId == null) {
      // Si la demande n’est pas ciblée, on récupère TON livreur.id via user_id = auth.uid()
      final row = await supabase
          .from('livreurs')
          .select('id')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle() as Map<String, dynamic>?;
      if (row == null) {
        throw Exception("Profil livreur introuvable pour cet utilisateur.");
      }
      livreurRowId = row['id'] as String;
    } else {
      // Si la demande cible un livreur précis, on vérifie qu’il t’appartient
      final owns = await supabase
          .from('livreurs')
          .select('id')
          .eq('id', livreurRowId)
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      if (owns == null) {
        throw Exception("Cette demande n'est pas assignée à ton profil livreur.");
      }
    }

    final num? montant = demande['prix_propose'] as num?;
    final double commissionApp = _commissionOf(montant);
    final double netLivreur = ((montant ?? 0).toDouble() - commissionApp);

    // 2) Insérer dans LIVRAISONS avec le bon livreur_id (=> livreurs.id)
    final inserted = await supabase
        .from('livraisons')
        .insert({
          'livreur_id': livreurRowId,   // ✅ clé de la table livreurs
          'client_id': demande['client_id'],
          'montant': montant ?? 0,
          'commission_app': commissionApp,
          'net_livreur': netLivreur,
          'status': 'accepted',
          'accepted_at': nowIso,
          'created_at': nowIso,
        })
        .select()
        .single();

    // 3) Marquer la demande comme acceptée (garde-fou)
    final updated = await supabase
        .from('livraison_demandes')
        .update({
          'status': 'accepted',
          'accepted_at': nowIso,
          'commission_amount': commissionApp,
        })
        .eq('id', demandeId)
        .eq('status', 'pending')
        .select()
        .maybeSingle();

    if (updated == null) {
      // Option: rollback si besoin
      // await supabase.from('livraisons').delete().eq('id', inserted['id'] as String);
      throw Exception("Cette demande n'est plus disponible (déjà prise/refusée).");
    }

    // 4) Créditer le wallet (par user_id)
    await supabase.rpc('add_commission', params: {
      'p_user': userId,
      'p_amount': commissionApp,
    });

    return (inserted as Map<String, dynamic>);
  }

  // ==========================================================
  // 4) REFUSER une demande (table: livraison_demandes)
  // ==========================================================
  Future<Map<String, dynamic>?> refuserDemande(String demandeId) async {
    final updated = await supabase
        .from('livraison_demandes')
        .update({'status': 'refused'})
        .eq('id', demandeId)
        .eq('status', 'pending') // éviter de repasser une accepted en refused
        .select()
        .maybeSingle();

    return updated == null ? null : (updated as Map<String, dynamic>);
  }

  // =========================================================================================
  // 5) Alternative via RPC SQL unique (si tu ajoutes une fonction accept_livraison(p_id uuid))
  // =========================================================================================
  Future<Map<String, dynamic>> accepterViaRpc(String demandeId) async {
    final res = await supabase.rpc('accept_livraison', params: {'p_id': demandeId});
    if (res == null) throw Exception("Demande indisponible (déjà prise/refusée).");

    if (res is List && res.isNotEmpty) {
      return (res.first as Map<String, dynamic>);
    } else if (res is List && res.isEmpty) {
      throw Exception("Demande indisponible (déjà prise/refusée).");
    } else if (res is Map) {
      return (res as Map<String, dynamic>);
    } else {
      throw Exception("Réponse inattendue de la RPC.");
    }
  }
}
