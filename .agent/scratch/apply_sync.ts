import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const url = Deno.env.get("SUPABASE_URL") || "";
const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";

const admin = createClient(url, serviceRole);

const sql = `
-- Sincronização de status entre service_requests e agendamento_servico
CREATE OR REPLACE FUNCTION public.sync_service_status_to_agendamento()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.agendamento_servico
    SET 
        status = NEW.status,
        updated_at = NOW()
    WHERE id = NEW.id 
      AND (status IS DISTINCT FROM NEW.status);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_service_status_to_agendamento ON public.service_requests;
CREATE TRIGGER trg_sync_service_status_to_agendamento
AFTER UPDATE OF status ON public.service_requests
FOR EACH ROW
EXECUTE FUNCTION public.sync_service_status_to_agendamento();

CREATE OR REPLACE FUNCTION public.sync_agendamento_status_to_requests()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.service_requests
    SET 
        status = NEW.status,
        status_updated_at = NOW()
    WHERE id = NEW.id
      AND (status IS DISTINCT FROM NEW.status);
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_agendamento_status_to_requests ON public.agendamento_servico;
CREATE TRIGGER trg_sync_agendamento_status_to_requests
AFTER UPDATE OF status ON public.agendamento_servico
FOR EACH ROW
EXECUTE FUNCTION public.sync_agendamento_status_to_requests();
`;

console.log("Applying SQL migration...");
const { error } = await admin.rpc("exec_sql", { sql_string: sql });

if (error) {
    console.error("Error applying migration via RPC:", error);
    // fallback: try direct query if RPC doesn't exist
    const { error: rawErr } = await admin.from("_ignore").select("*").limit(0); // dummy to check connection
    console.log("Connection check error:", rawErr);
} else {
    console.log("Migration applied successfully!");
}
