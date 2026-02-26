-- ScheduleNote Supabase SQL Gateway for Dart SDK backend
--
-- Purpose:
-- - Keep existing SQL-centric server route/service logic intact
-- - Execute SQL through Supabase SDK (URL + KEY) via RPC calls
--
-- Security:
-- - This gateway executes arbitrary SQL text.
-- - Grant EXECUTE ONLY to service_role.
-- - Do NOT grant to anon/authenticated roles.

BEGIN;

CREATE OR REPLACE FUNCTION public.sn_query_sql(p_sql text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows jsonb;
BEGIN
  EXECUTE format(
    'SELECT COALESCE(jsonb_agg(to_jsonb(q)), ''[]''::jsonb) FROM (%s) q',
    p_sql
  )
  INTO v_rows;

  RETURN COALESCE(v_rows, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.sn_exec_sql(p_sql text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count bigint;
BEGIN
  EXECUTE p_sql;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN COALESCE(v_count, 0)::integer;
END;
$$;

REVOKE ALL ON FUNCTION public.sn_query_sql(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sn_exec_sql(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sn_query_sql(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.sn_exec_sql(text) TO service_role;

COMMIT;
