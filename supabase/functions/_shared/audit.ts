import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export interface AuditEntry {
  user_uid: string | null
  screen_key: string
  command_key: string
  component_id?: string | null
  revision?: string | null
  store_version?: string | null
  patch_version?: string | null
  platform?: string | null
  role?: string | null
  arguments?: Record<string, unknown>
  entity_ids?: Record<string, unknown>
  result_success?: boolean | null
  result_message?: string | null
}

export async function writeAuditLog(
  client: SupabaseClient,
  entry: AuditEntry,
): Promise<void> {
  try {
    await client.from('remote_ui_audit_log').insert(entry)
  } catch (err) {
    console.warn('[audit] Falha ao gravar audit log:', err)
  }
}
