const { createClient } = require('@supabase/supabase-js');

// Initialiser Supabase avec les variables d'environnement
const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE
);

// Fonction principale de la Netlify Function
exports.handler = async (event, context) => {
  try {
    // Récupérer les données JSON envoyées (ID chauffeur, date, heure, montant)
    const { chauffeur_id, date, heure, montant } = JSON.parse(event.body);

    // Insertion dans la table 'passagers'
    const { error } = await supabase
      .from('passagers')
      .insert([{ chauffeur_id, nombre_passagers: 1, date, heure, montant }]);

    // Gérer les erreurs
    if (error) {
      return {
        statusCode: 401,
        body: JSON.stringify({
          message: 'Erreur Supabase',
          erreur: error.message,
          details: error.details || null,
        }),
      };
    }

    // Succès
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Insertion réussie' }),
    };
  } catch (e) {
    // Gérer les erreurs de parsing JSON ou erreurs internes
    return {
      statusCode: 500,
      body: JSON.stringify({ message: 'Erreur serveur', erreur: e.message }),
    };
  }
};