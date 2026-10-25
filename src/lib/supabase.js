import { createClient } from '@supabase/supabase-js';

export function createSupabaseClient() {
  const url = import.meta.env.VITE_SUPABASE_URL?.trim();
  const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim();

  if (!url && !publishableKey) return { client: null, error: '' };
  if (!url || !publishableKey) {
    return { client: null, error: 'Set both VITE_SUPABASE_URL and VITE_SUPABASE_PUBLISHABLE_KEY to enable cloud sync.' };
  }

  try {
    const parsedUrl = new URL(url);
    if (!['http:', 'https:'].includes(parsedUrl.protocol)) throw new Error('Use an http or https project URL.');
    return {
      client: createClient(url, publishableKey, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
      }),
      error: '',
    };
  } catch (error) {
    return { client: null, error: error?.message || 'The Supabase project URL or publishable key is invalid.' };
  }
}
