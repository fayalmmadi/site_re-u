// netlify/functions/add_passager.js
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE
);

exports.handler = async (event) => {
  try {
    if (event.httpMethod !== 'POST') {
      return {
        statusCode: 405,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: 'error', message: 'Method Not Allowed' })
      };
    }

    const body = JSON.parse(event.body || '{}');

    const voiture_id    = body.voiture_id;  // UUID de la voiture
    const date          = body.date;        // "YYYY-MM-DD"
    const heure         = body.heure;       // "HH:MM:SS"
    const mois_validite = body.mois_validite; // "YYYY-MM"
    const montant       = body.montant ?? 0;
    const uuid          = body.uuid;
    const isCheckOnly   = body.isCheckOnly === true;

    // IP pour anti-spam (15 min)
    const ip =
      body.ip ||
      event.headers['x-forwarded-for'] ||
      event.headers['client-ip'] ||
      '0.0.0.0';

    if (!voiture_id) {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: 'error', message: 'voiture_id manquant' })
      };
    }

    // (1) Récup info voiture + chauffeur
    const { data: car, error: carErr } = await supabase
      .from('voitures')
      .select('id, immatriculation, display_driver_name, owner_user_id')
      .eq('id', voiture_id)
      .single();

    if (carErr || !car) {
      return {
        statusCode: 404,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: 'error', message: 'Voiture introuvable' })
      };
    }

    // Essayer de récupérer nom/prenom du profil propriétaire (si besoin)
    let nom = null, prenom = null;
    if (car.owner_user_id) {
      const { data: prof } = await supabase
        .from('profiles')
        .select('nom, prenom')
        .eq('id', car.owner_user_id)
        .maybeSingle();
      nom = prof?.nom || null;
      prenom = prof?.prenom || null;
    }

    // Construire un affichage "Prénom Nom" par défaut si pas de display_driver_name
    const displayChauffeur =
      car.display_driver_name ||
      [prenom, nom].filter(Boolean).join(' ') ||
      '—';

    // Reçu "standard"
    const receipt = {
      voiture:   { immatriculation: car.immatriculation },
      chauffeur: { nom, prenom, display: displayChauffeur },
      date,
      time: heure,
      valid_month: mois_validite
    };

    // (2) Anti-spam 15 min par (voiture_id + ip)
    const now = new Date();
    const { data: lastScan } = await supabase
      .from('passagers')
      .select('created_at')
      .eq('voiture_id', voiture_id)
      .eq('ip', ip)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (lastScan) {
      const diffMinutes = (now - new Date(lastScan.created_at)) / 60000;
      if (diffMinutes < 15) {
        return {
          statusCode: 200,
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ status: 'too_soon', receipt })
        };
      }
    }

    // (3) Mode check-only → pas d'insertion
    if (isCheckOnly) {
      return {
        statusCode: 200,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: 'ok', receipt })
      };
    }

    // (4) Insertion en base
    const { error: insErr } = await supabase.from('passagers').insert([{
      voiture_id,
      date,
      heure,
      montant,
      uuid,
      ip,
      mois_validite,
      nombre_passagers: 1
    }]);

    if (insErr) {
      return {
        statusCode: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: 'error', message: insErr.message })
      };
    }

    // (5) OK → renvoyer reçu
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'inserted', receipt })
    };

  } catch (e) {
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'error', message: e.message })
    };
  }
};
