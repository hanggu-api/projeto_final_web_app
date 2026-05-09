import { createServiceClient, resolveUser } from '../_shared/auth.ts'
import { corsHeaders, handleCors } from '../_shared/cors.ts'
import { isCommandAllowed } from '../_shared/command_registry.ts'
import { writeAuditLog } from '../_shared/audit.ts'

interface ActionRequest {
  action_type: string
  command_key: string
  screen_key: string
  component_id?: string
  arguments?: Record<string, unknown>
  entity_ids?: Record<string, unknown>
  store_version?: string
  patch_version?: string
  platform?: string
  role?: string
  revision?: string
}

Deno.serve(async (req: Request) => {
  const corsResponse = handleCors(req)
  if (corsResponse) return corsResponse

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const user = await resolveUser(authHeader)
    if (!user) return json({ success: false, message: 'Não autenticado' }, 401)

    const body: ActionRequest = await req.json()
    const commandKey = body.command_key?.trim()
    const screenKey  = body.screen_key?.trim()

    if (!commandKey || !screenKey) {
      return json({ success: false, message: 'command_key e screen_key são obrigatórios' }, 400)
    }

    if (!isCommandAllowed(commandKey)) {
      console.warn(`[post_action] Comando não permitido: ${commandKey}`)
      return json({ success: false, message: `Comando '${commandKey}' não reconhecido` }, 403)
    }

    const client   = createServiceClient()
    const args     = body.arguments  ?? {}
    const entityIds = body.entity_ids ?? {}

    // Verifica política no banco
    const { data: policy } = await client
      .from('remote_action_policies')
      .select('is_allowed')
      .eq('screen_key', screenKey)
      .eq('command_key', commandKey)
      .maybeSingle()

    if (policy && !policy.is_allowed) {
      await writeAuditLog(client, {
        user_uid: user.id, screen_key: screenKey, command_key: commandKey,
        component_id: body.component_id, revision: body.revision,
        store_version: body.store_version, patch_version: body.patch_version,
        platform: body.platform, role: body.role,
        arguments: args, entity_ids: entityIds,
        result_success: false, result_message: 'blocked_by_policy',
      })
      return json({ success: false, message: 'Ação não permitida neste contexto' }, 403)
    }

    const result = await executeCommand(commandKey, { user, client, args, entityIds, screenKey })

    await writeAuditLog(client, {
      user_uid: user.id, screen_key: screenKey, command_key: commandKey,
      component_id: body.component_id, revision: body.revision,
      store_version: body.store_version, patch_version: body.patch_version,
      platform: body.platform, role: body.role,
      arguments: args, entity_ids: entityIds,
      result_success: result.success, result_message: result.message ?? null,
    })

    return json(result)
  } catch (err) {
    console.error('[post_action] Erro interno:', err)
    return json({ success: false, message: 'Erro interno do servidor' }, 500)
  }
})

async function executeCommand(
  commandKey: string,
  ctx: { user: { id: string }; client: ReturnType<typeof createServiceClient>; args: Record<string, unknown>; entityIds: Record<string, unknown>; screenKey: string },
): Promise<ActionResponse> {
  const { user, client, args, entityIds } = ctx

  switch (commandKey) {
    case 'cancel_service_request': {
      const serviceId = entityIds['service_id']?.toString() ?? args['service_id']?.toString()
      if (!serviceId) return fail('service_id obrigatório para cancelar')
      const { data: service } = await client
        .from('service_requests_new').select('id,status').eq('id', serviceId).maybeSingle()
      if (!service) return fail('Serviço não encontrado')
      const terminal = ['completed','cancelled','canceled','refunded']
      if (terminal.includes(service.status)) return fail('Serviço já está em status terminal')
      await client.from('service_requests_new')
        .update({ status: 'cancelled', updated_at: new Date().toISOString() })
        .eq('id', serviceId)
      return ok('Serviço cancelado com sucesso', { refresh_screen: true, updated_state: { service_id: serviceId, status: 'cancelled' } })
    }

    case 'refresh_search_status': {
      const serviceId = entityIds['service_id']?.toString() ?? args['service_id']?.toString()
      if (!serviceId) return fail('service_id obrigatório')
      const { data: service } = await client
        .from('service_requests_new').select('id,status,provider_id').eq('id', serviceId).maybeSingle()
      if (!service) return fail('Serviço não encontrado')
      return ok('Status atualizado', { updated_state: { service_id: serviceId, status: service.status, provider_id: service.provider_id } })
    }

    case 'confirm_service_completion': {
      const serviceId = entityIds['service_id']?.toString() ?? args['service_id']?.toString()
      if (!serviceId) return fail('service_id obrigatório')
      await client.from('service_requests_new')
        .update({ status: 'completion_requested', updated_at: new Date().toISOString() })
        .eq('id', serviceId)
      return ok('Conclusão solicitada', { refresh_screen: true, updated_state: { service_id: serviceId, status: 'completion_requested' } })
    }

    case 'toggle_dispatch_availability': {
      const isAvailable = args['is_available'] as boolean ?? true
      await client.from('users')
        .update({ is_available: isAvailable, updated_at: new Date().toISOString() })
        .eq('supabase_uid', user.id)
      return ok(isAvailable ? 'Você está disponível' : 'Você está indisponível', { updated_state: { is_available: isAvailable } })
    }

    case 'accept_ride': {
      const serviceId = entityIds['service_id']?.toString() ?? args['service_id']?.toString()
      if (!serviceId) return fail('service_id obrigatório')
      const { data: service } = await client
        .from('service_requests_new').select('id,status').eq('id', serviceId).maybeSingle()
      if (!service) return fail('Serviço não encontrado')
      if (service.status !== 'searching') return fail('Serviço não está mais disponível para aceite')
      return ok('Aceite autorizado', { effects: [{ type: 'accept_service', service_id: serviceId }], updated_state: { service_id: serviceId } })
    }

    case 'reject_ride': {
      const serviceId = entityIds['service_id']?.toString() ?? args['service_id']?.toString()
      if (!serviceId) return fail('service_id obrigatório')
      return ok('Recusa registrada', { effects: [{ type: 'reject_service', service_id: serviceId }] })
    }

    case 'generate_platform_pix':
    case 'retry_pix_generation': {
      const serviceId = entityIds['service_id']?.toString() ?? args['service_id']?.toString()
      if (!serviceId) return fail('service_id obrigatório para gerar PIX')
      return ok('PIX autorizado', { effects: [{ type: 'generate_pix', service_id: serviceId }], updated_state: { service_id: serviceId } })
    }

    case 'confirm_direct_payment_intent': {
      const intentId = entityIds['intent_id']?.toString() ?? args['intent_id']?.toString()
      if (!intentId) return fail('intent_id obrigatório')
      return ok('Intenção confirmada', { updated_state: { intent_id: intentId, status: 'confirmed' } })
    }

    case 'open_provider_home':
    case 'open_service_tracking':
    case 'open_active_service':
    case 'return_home':
    case 'open_support':
    case 'show_search_details':
    case 'open_offer':
    case 'refresh_home':
    case 'show_command_feedback':
    case 'open_chat':
    case 'start_navigation':
    case 'open_pix_screen':
      return ok('Navegação autorizada', { effects: [{ type: 'navigate', command_key: commandKey, args }] })

    default:
      return fail(`Comando '${commandKey}' não implementado`)
  }
}

interface ActionResponse {
  success: boolean; message?: string; next_screen?: string
  refresh_screen?: boolean; updated_state?: Record<string, unknown>
  effects?: Record<string, unknown>[]; handled?: boolean
}

function ok(message: string, extra: Partial<ActionResponse> = {}): ActionResponse {
  return { success: true, message, handled: true, ...extra }
}
function fail(message: string): ActionResponse {
  return { success: false, message, handled: true }
}
function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
