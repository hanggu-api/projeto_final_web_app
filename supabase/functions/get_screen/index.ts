import { createServiceClient, resolveUser } from '../_shared/auth.ts'
import { corsHeaders, handleCors } from '../_shared/cors.ts'

interface ScreenRequest {
  screen_key: string
  app_version?: string
  patch_version?: string
  platform?: string
  role?: string
  locale?: string
  environment?: string
  feature_set?: Record<string, boolean>
  context?: Record<string, unknown>
}

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req)
  if (corsResponse) return corsResponse

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const user = await resolveUser(authHeader)
    if (!user) return json({ error: 'Não autenticado' }, 401)

    const body: ScreenRequest = await req.json()
    const screenKey = body.screen_key?.trim()
    if (!screenKey) return json({ error: 'screen_key obrigatório' }, 400)

    const platform    = body.platform    ?? 'unknown'
    const role        = body.role        ?? 'guest'
    const appVersion  = body.app_version ?? '0'
    const patchVersion = body.patch_version ?? 'store'
    const environment = body.environment ?? 'production'
    const locale      = body.locale      ?? 'pt-BR'

    const client = createServiceClient()

    // 1. Kill switch global
    const { data: globalKS } = await client
      .from('app_configs')
      .select('value')
      .eq('key', 'kill_switch.remote_ui.global')
      .eq('is_active', true)
      .maybeSingle()

    if (globalKS?.value === 'true') {
      return json(nativeScreen(screenKey, 'kill_switch_global'))
    }

    // 2. Kill switch da tela
    const { data: screenKS } = await client
      .from('app_configs')
      .select('value')
      .eq('key', `kill_switch.remote_ui.${screenKey}`)
      .eq('is_active', true)
      .maybeSingle()

    if (screenKS?.value === 'true') {
      return json(nativeScreen(screenKey, 'kill_switch_screen'))
    }

    // 3. Flag da tela
    const { data: screenFlag } = await client
      .from('app_configs')
      .select('value')
      .eq('key', `flag.remote_ui.${screenKey}.enabled`)
      .eq('is_active', true)
      .maybeSingle()

    if (screenFlag?.value === 'false') {
      return json(nativeScreen(screenKey, 'flag_disabled'))
    }

    // 4. Publicação ativa
    const { data: publication } = await client
      .from('remote_screen_publications')
      .select(`
        id, revision, full_schema, variant_id,
        remote_screen_variants ( role_scope, platform_scope, status_scope, commands_used )
      `)
      .eq('screen_key', screenKey)
      .eq('is_active', true)
      .order('id', { ascending: false })
      .limit(1)
      .maybeSingle()

    if (!publication?.full_schema) {
      return json(nativeScreen(screenKey, 'no_publication'))
    }

    const schema  = publication.full_schema as Record<string, unknown>
    const variant = publication.remote_screen_variants as Record<string, unknown> | null

    return json({
      screen: {
        version: 1,
        screen: screenKey,
        revision: publication.revision,
        ttl_seconds: 300,
        features: {
          enabled: true,
          kill_switch: false,
          flags: body.feature_set ?? {},
        },
        layout: (schema.layout as Record<string, unknown>) ?? {},
        components: (schema.components as unknown[]) ?? [],
        fallback_policy: { mode: 'use_cache_then_native', allow_cache: true },
        commands_used: (variant?.commands_used as string[]) ?? [],
        meta: {
          trace_id: crypto.randomUUID(),
          schema_version: 1,
          source_table: 'remote_screen_publications',
          publication_id: publication.id,
          platform, role, app_version: appVersion,
          patch_version: patchVersion, environment, locale,
          resolved_at: new Date().toISOString(),
        },
      },
    })
  } catch (err) {
    console.error('[get_screen] Erro interno:', err)
    return json({ error: 'Erro interno do servidor' }, 500)
  }
})

function nativeScreen(screenKey: string, reason: string) {
  return {
    screen: {
      version: 1, screen: screenKey, revision: 'native-fallback',
      ttl_seconds: 0,
      features: { enabled: false, kill_switch: true, flags: {} },
      layout: {}, components: [],
      fallback_policy: { mode: 'use_native', allow_cache: false },
      commands_used: [],
      meta: { reason, resolved_at: new Date().toISOString() },
    },
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
