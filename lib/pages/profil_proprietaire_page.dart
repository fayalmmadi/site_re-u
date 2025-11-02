import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilProprietairePage extends StatefulWidget {
  const ProfilProprietairePage({super.key});
  @override
  State<ProfilProprietairePage> createState() => _ProfilProprietairePageState();
}

class _ProfilProprietairePageState extends State<ProfilProprietairePage> {
  final _formKey = GlobalKey<FormState>();
  final prenomCtrl = TextEditingController();
  final nomCtrl    = TextEditingController();
  bool _loading = false;

  @override
  void dispose() { prenomCtrl.dispose(); nomCtrl.dispose(); super.dispose(); }

  void _snack(String m)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if(!_formKey.currentState!.validate()) return;
    setState(()=>_loading=true);
    try{
      final s = Supabase.instance.client;
      final uid = s.auth.currentUser!.id;

      // upsert profil propriétaire
      await s.from('proprietaires').upsert({
        'user_id': uid,
        'prenom' : prenomCtrl.text.trim(),
        'nom'    : nomCtrl.text.trim(),
      });

      // ajoute rôle si manquant
      final roles = await s.from('user_roles').select('role').eq('user_id', uid);
      final has = roles.any((r)=> r['role']=='proprietaire');
      if(!has){
        await s.from('user_roles').insert({'user_id': uid, 'role':'proprietaire'});
      }

      if(!mounted) return;
      // tu peux envoyer vers une page "ajouter voiture" d'abord si tu veux
      Navigator.pushNamedAndRemoveUntil(context, '/proprietaire', (_)=>false);
    }catch(e){
      _snack('Erreur : $e');
    }finally{
      if(mounted) setState(()=>_loading=false);
    }
  }

  InputDecoration _deco(String l, IconData i)=>InputDecoration(
    labelText:l, prefixIcon:Icon(i),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    filled:true, fillColor: const Color(0xFFF7F8FA),
  );

  @override
  Widget build(BuildContext context){
    final isNarrow = MediaQuery.of(context).size.width<600;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil Propriétaire')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth:560),
            child: Card(
              elevation:8, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key:_formKey,
                  child: Column(children:[
                    if(isNarrow)...[
                      TextFormField(controller: prenomCtrl, decoration:_deco('Prénom', Icons.badge),
                        validator:(v)=>(v==null||v.trim().isEmpty)?'Requis':null),
                      const SizedBox(height:12),
                      TextFormField(controller: nomCtrl, decoration:_deco('Nom', Icons.badge_outlined),
                        validator:(v)=>(v==null||v.trim().isEmpty)?'Requis':null),
                    ] else Row(children:[
                      Expanded(child: TextFormField(controller: prenomCtrl, decoration:_deco('Prénom', Icons.badge),
                        validator:(v)=>(v==null||v.trim().isEmpty)?'Requis':null)),
                      const SizedBox(width:12),
                      Expanded(child: TextFormField(controller: nomCtrl, decoration:_deco('Nom', Icons.badge_outlined),
                        validator:(v)=>(v==null||v.trim().isEmpty)?'Requis':null)),
                    ]),
                    const SizedBox(height:18),

                    SizedBox(
                      width: double.infinity, height:52,
                      child: ElevatedButton.icon(
                        onPressed:_loading?null:_save,
                        icon: const Icon(Icons.check_circle),
                        label: _loading
                          ? const SizedBox(height:20,width:20,child:CircularProgressIndicator(strokeWidth:2,color:Colors.white))
                          : const Text('Enregistrer et continuer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height:8),
                    TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Annuler')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
