// Netlify serverless function — persistent shared order storage for
// Dastaan-e-Kitab, backed by Netlify Blobs (built into every Netlify site,
// no external database needed).
//
// Blobs live outside your deployed code, in their own storage bucket tied
// to the *site*, not to any particular deploy. So deleting/replacing
// index.html (e.g. to add new books) and redeploying NEVER touches this
// data — every order ever placed stays exactly where it was.
//
// GET  /.netlify/functions/orders   -> { orders: { key: order, ... } }
// POST /.netlify/functions/orders   -> body: { key, order } -> saves one order

import { getStore } from '@netlify/blobs';

export default async (req, context) => {
  const store = getStore('dastaan-e-kitab-orders');

  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };

  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method === 'GET') {
    try {
      const { blobs } = await store.list();
      const orders = {};
      for (const b of blobs) {
        try {
          const value = await store.get(b.key, { type: 'json' });
          if (value) orders[b.key] = value;
        } catch (e) {
          // skip a single unreadable entry rather than failing the whole request
        }
      }
      return new Response(JSON.stringify({ orders }), {
        status: 200,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      });
    } catch (err) {
      return new Response(JSON.stringify({ orders: {}, error: String(err) }), {
        status: 200,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      });
    }
  }

  if (req.method === 'POST') {
    try {
      const body = await req.json();
      const { key, order } = body || {};
      if (!key || typeof key !== 'string' || !order || typeof order !== 'object') {
        return new Response(JSON.stringify({ ok: false, error: 'Missing key or order' }), {
          status: 400,
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
        });
      }
      await store.setJSON(key, order);
      return new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      });
    } catch (err) {
      return new Response(JSON.stringify({ ok: false, error: String(err) }), {
        status: 400,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      });
    }
  }

  return new Response('Method not allowed', { status: 405, headers: corsHeaders });
};

export const config = {
  path: '/.netlify/functions/orders',
};
