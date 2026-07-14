// api/create-preference.js
// Vercel Serverless Function: crea una preferencia de pago de Mercado Pago (Checkout Pro)
// y devuelve la URL de checkout. El Access Token NUNCA se expone al navegador: vive
// solo aca, en el servidor, leido desde una variable de entorno.

import { MercadoPagoConfig, Preference } from 'mercadopago';

const client = new MercadoPagoConfig({
  accessToken: process.env.MP_ACCESS_TOKEN,
});

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Metodo no permitido' });
  }

  try {
    const { items } = req.body || {};

    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'El carrito esta vacio' });
    }

    const mpItems = items.map((i) => ({
      title: String(i.title || 'Producto').slice(0, 250),
      quantity: Number(i.quantity) || 1,
      unit_price: Number(i.unit_price) || 0,
      currency_id: 'ARS',
    }));

    const siteUrl = process.env.SITE_URL;

    const preferenceBody = {
      items: mpItems,
      statement_descriptor: 'GREEN WITCH GROW',
    };

    if (siteUrl) {
      preferenceBody.back_urls = {
        success: `${siteUrl}/?pago=exito`,
        failure: `${siteUrl}/?pago=fallido`,
        pending: `${siteUrl}/?pago=pendiente`,
      };
      preferenceBody.auto_return = 'approved';
    }

    const preference = new Preference(client);
    const result = await preference.create({ body: preferenceBody });

    return res.status(200).json({
      id: result.id,
      init_point: result.init_point,
      sandbox_init_point: result.sandbox_init_point,
    });
  } catch (err) {
    console.error('Error creando preferencia de Mercado Pago:', err);
    return res.status(500).json({ error: 'No se pudo crear la preferencia de pago' });
  }
}
