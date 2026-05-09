import { createServiceClient, resolveUser } from '../_shared/auth.ts'
import { corsHeaders, handleCors } from '../_shared/cors.ts'

interface AvailableServicesRequest {
  provider_user_id: string
  include_emergency?: boolean
  limit?: number
}

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req)
  if (corsResponse) return corsResponse

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const user = await resolveUser(authHeader)
    if (!user) return json({ error: 'Não autenticado' }, 401)

    const body: AvailableServicesRequest = await req.json()
    const providerUserId = body.provider_user_id?.toString().trim()
    if (!providerUserId) return json({ error: 'provider_user_id obrigatório' }, 400)

    const client = createServiceClient()
    const limit  = Math.min(body.limit ?? 30, 50)

    // 1. Profissões do prestador
    const { data: professionRows } = await client
      .from('provider_professions')
      .select('profession_id, professions(name, service_type)')
      .eq('provider_user_id', providerUserId)

    const professionNames: string[] = (professionRows ?? [])
      .map((r: any) => r.professions?.name?.toLowerCase().trim())
      .filter(Boolean)

    // 2. Serviços abertos
    const openStatuses = [
      'pending','open_for_schedule','searching',
      'searching_provider','search_provider','waiting_provider',
    ]

    const { data: rawServices } = await client
      .from('service_requests_new')
      .select(`
        id, status, profession, description, address,
        price_estimated, price_upfront, latitude, longitude,
        category_id, client_id, created_at,
        service_categories!category_id(name)
      `)
      .in('status', openStatuses)
      .is('provider_id', null)
      .order('created_at', { ascending: false })
      .limit(limit)

    if (!rawServices || rawServices.length === 0) {
      return json({ services: [], total: 0 })
    }

    // 3. Filtro por profissão — backend decide elegibilidade
    const filtered = rawServices.filter((s: any) => {
      if (professionNames.length === 0) return true
      const sp = (s.profession ?? s.service_categories?.name ?? '').toLowerCase().trim()
      if (!sp) return true
      return professionNames.some((p: string) => sp.includes(p) || p.includes(sp))
    })

    // 4. Filtra serviços em fila privada de despacho
    const serviceIds = filtered.map((s: any) => s.id?.toString()).filter(Boolean)

    const [{ data: queueRows }, { data: notifRows }] = await Promise.all([
      client.from('service_dispatch_queue')
        .select('service_id').in('service_id', serviceIds).neq('status', 'done'),
      client.from('notificacao_de_servicos')
        .select('service_id').in('service_id', serviceIds).in('status', ['queued','notified']),
    ])

    const blockedIds = new Set([
      ...(queueRows ?? []).map((r: any) => r.service_id?.toString()),
      ...(notifRows ?? []).map((r: any) => r.service_id?.toString()),
    ])

    const publicServices = filtered.filter((s: any) => !blockedIds.has(s.id?.toString()))

    // 5. Enriquece com provider_amount — backend aplica comissão
    const enriched = publicServices.map((s: any) => {
      const price = parseFloat(s.price_estimated ?? '0') || 0
      return {
        ...s,
        category_name: s.service_categories?.name ?? null,
        provider_amount: parseFloat((price * 0.85).toFixed(2)),
        service_categories: undefined,
      }
    })

    return json({
      services: enriched,
      total: enriched.length,
      blocked_count: blockedIds.size,
      profession_filter: professionNames,
    })
  } catch (err) {
    console.error('[get-available-services] Erro:', err)
    return json({ error: 'Erro interno' }, 500)
  }
})

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
