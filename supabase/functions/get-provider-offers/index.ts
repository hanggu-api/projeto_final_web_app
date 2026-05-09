import { createServiceClient, resolveUser } from '../_shared/auth.ts'
import { corsHeaders, handleCors } from '../_shared/cors.ts'

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req)
  if (corsResponse) return corsResponse

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const user = await resolveUser(authHeader)
    if (!user) return json({ error: 'Não autenticado' }, 401)

    const body = await req.json()
    const providerUserId = body.provider_user_id?.toString().trim()
    if (!providerUserId) return json({ error: 'provider_user_id obrigatório' }, 400)

    const client = createServiceClient()
    const now    = new Date().toISOString()

    // Ofertas ativas com deadline válido — backend valida, Flutter só exibe
    const { data: rows } = await client
      .from('notificacao_de_servicos')
      .select(`
        id, service_id, status, response_deadline_at,
        last_notified_at, ciclo_atual, queue_order
      `)
      .eq('provider_user_id', providerUserId)
      .eq('status', 'notified')
      .gt('response_deadline_at', now)
      .order('last_notified_at', { ascending: false })
      .limit(5)

    return json({
      offers: rows ?? [],
      total: (rows ?? []).length,
      checked_at: now,
    })
  } catch (err) {
    console.error('[get-provider-offers] Erro:', err)
    return json({ error: 'Erro interno' }, 500)
  }
})

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
