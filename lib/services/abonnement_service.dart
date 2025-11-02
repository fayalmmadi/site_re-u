import 'package:supabase_flutter/supabase_flutter.dart';

class AbonnementService {
  final supa = Supabase.instance.client;

  Future<Map<String, dynamic>> quote({required String period}) async {
    final uid = supa.auth.currentUser!.id;
    final data = await supa.rpc('subscription_quote', params: {
      'p_user': uid,
      'p_period': period, // 'mensuel' | 'annuel'
    });
    // data = { car_count, unit_price, total, next_renewal }
    return (data as Map).cast<String, dynamic>();
  }

  Future<bool> confirmPayment({
    required String period,
    required num amount,
  }) async {
    final uid = supa.auth.currentUser!.id;
    final res = await supa.rpc('upsert_abonnement_after_payment', params: {
      'p_user': uid,
      'p_period': period,
      'p_amount': amount,
    });
    return res == true;
  }

  Future<bool> redeemCode(String code) async {
    final uid = supa.auth.currentUser!.id;
    final res = await supa.rpc('redeem_subscription_code', params: {
      'p_user': uid,
      'p_code': code,
    });
    return res == true;
  }
}
