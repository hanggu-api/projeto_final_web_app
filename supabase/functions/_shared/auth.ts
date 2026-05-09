import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export function createServiceClient() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )
}

export function createUserClient(authHeader: string) {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )
}

export async function resolveUser(authHeader: string) {
  const client = createUserClient(authHeader)
  const { data: { user }, error } = await client.auth.getUser()
  if (error || !user) return null
  return user
}
