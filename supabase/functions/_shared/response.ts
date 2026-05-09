export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
}

export function ok(data: unknown, status = 200): Response {
  return new Response(JSON.stringify({ success: true, data }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

export function err(message: string, status = 400, code?: string): Response {
  return new Response(
    JSON.stringify({ success: false, error: { message, code: code ?? 'ERROR' } }),
    { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
}

export function notFound(resource = 'Resource'): Response {
  return err(`${resource} not found`, 404, 'NOT_FOUND')
}

export function unauthorized(): Response {
  return err('Unauthorized', 401, 'UNAUTHORIZED')
}

export function forbidden(): Response {
  return err('Forbidden', 403, 'FORBIDDEN')
}
