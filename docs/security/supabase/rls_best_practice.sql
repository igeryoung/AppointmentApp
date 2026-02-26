-- ScheduleNote Supabase RLS Best-Practice Policy Set
--
-- Apply this in Supabase SQL Editor after importing server/schema.sql.
-- This script assumes client access uses Supabase Auth (auth.uid()).
--
-- Important:
-- 1) Enable Anonymous provider in Supabase Auth if you use anonymous sign-in.
-- 2) Do NOT use service_role in the app client.

BEGIN;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Hardening: remove legacy broad grants before re-granting least privilege.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM authenticated;

-- Helper predicates -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_can_read_book(p_book_uuid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.books b
    WHERE b.book_uuid = p_book_uuid
      AND b.is_deleted = false
      AND b.device_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.book_device_access a
    JOIN public.books b ON b.book_uuid = a.book_uuid
    WHERE a.book_uuid = p_book_uuid
      AND a.device_id = auth.uid()
      AND b.is_deleted = false
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_can_write_book(p_book_uuid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.books b
    WHERE b.book_uuid = p_book_uuid
      AND b.is_deleted = false
      AND b.device_id = auth.uid()
  )
  OR EXISTS (
    SELECT 1
    FROM public.book_device_access a
    JOIN public.books b ON b.book_uuid = a.book_uuid
    WHERE a.book_uuid = p_book_uuid
      AND a.device_id = auth.uid()
      AND a.access_type IN ('owner', 'editor')
      AND b.is_deleted = false
  );
$$;

CREATE OR REPLACE FUNCTION public.fn_is_book_owner(p_book_uuid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.books b
    WHERE b.book_uuid = p_book_uuid
      AND b.is_deleted = false
      AND b.device_id = auth.uid()
  );
$$;

-- RLS enablement -------------------------------------------------------------
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.book_device_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.schedule_drawings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.charge_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sync_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.devices FORCE ROW LEVEL SECURITY;
ALTER TABLE public.books FORCE ROW LEVEL SECURITY;
ALTER TABLE public.book_device_access FORCE ROW LEVEL SECURITY;
ALTER TABLE public.events FORCE ROW LEVEL SECURITY;
ALTER TABLE public.records FORCE ROW LEVEL SECURITY;
ALTER TABLE public.notes FORCE ROW LEVEL SECURITY;
ALTER TABLE public.schedule_drawings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.charge_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.sync_log FORCE ROW LEVEL SECURITY;

-- devices --------------------------------------------------------------------
DROP POLICY IF EXISTS devices_select_self ON public.devices;
DROP POLICY IF EXISTS devices_insert_self ON public.devices;
DROP POLICY IF EXISTS devices_update_self ON public.devices;

CREATE POLICY devices_select_self
ON public.devices
FOR SELECT
USING (id = auth.uid());

CREATE POLICY devices_insert_self
ON public.devices
FOR INSERT
WITH CHECK (id = auth.uid());

CREATE POLICY devices_update_self
ON public.devices
FOR UPDATE
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- books ----------------------------------------------------------------------
DROP POLICY IF EXISTS books_select_access ON public.books;
DROP POLICY IF EXISTS books_insert_owner ON public.books;
DROP POLICY IF EXISTS books_update_owner ON public.books;
DROP POLICY IF EXISTS books_delete_owner ON public.books;

CREATE POLICY books_select_access
ON public.books
FOR SELECT
USING (public.fn_can_read_book(book_uuid));

CREATE POLICY books_insert_owner
ON public.books
FOR INSERT
WITH CHECK (device_id = auth.uid());

CREATE POLICY books_update_owner
ON public.books
FOR UPDATE
USING (public.fn_is_book_owner(book_uuid))
WITH CHECK (device_id = auth.uid());

CREATE POLICY books_delete_owner
ON public.books
FOR DELETE
USING (public.fn_is_book_owner(book_uuid));

-- book_device_access ----------------------------------------------------------
DROP POLICY IF EXISTS bda_select_access ON public.book_device_access;
DROP POLICY IF EXISTS bda_insert_owner ON public.book_device_access;
DROP POLICY IF EXISTS bda_update_owner ON public.book_device_access;
DROP POLICY IF EXISTS bda_delete_owner ON public.book_device_access;

CREATE POLICY bda_select_access
ON public.book_device_access
FOR SELECT
USING (
  device_id = auth.uid()
  OR public.fn_is_book_owner(book_uuid)
);

CREATE POLICY bda_insert_owner
ON public.book_device_access
FOR INSERT
WITH CHECK (public.fn_is_book_owner(book_uuid));

CREATE POLICY bda_update_owner
ON public.book_device_access
FOR UPDATE
USING (public.fn_is_book_owner(book_uuid))
WITH CHECK (public.fn_is_book_owner(book_uuid));

CREATE POLICY bda_delete_owner
ON public.book_device_access
FOR DELETE
USING (public.fn_is_book_owner(book_uuid));

-- events ---------------------------------------------------------------------
DROP POLICY IF EXISTS events_select_access ON public.events;
DROP POLICY IF EXISTS events_insert_access ON public.events;
DROP POLICY IF EXISTS events_update_access ON public.events;
DROP POLICY IF EXISTS events_delete_access ON public.events;

CREATE POLICY events_select_access
ON public.events
FOR SELECT
USING (public.fn_can_read_book(book_uuid));

CREATE POLICY events_insert_access
ON public.events
FOR INSERT
WITH CHECK (public.fn_can_write_book(book_uuid));

CREATE POLICY events_update_access
ON public.events
FOR UPDATE
USING (public.fn_can_write_book(book_uuid))
WITH CHECK (public.fn_can_write_book(book_uuid));

CREATE POLICY events_delete_access
ON public.events
FOR DELETE
USING (public.fn_can_write_book(book_uuid));

-- schedule_drawings -----------------------------------------------------------
DROP POLICY IF EXISTS drawings_select_access ON public.schedule_drawings;
DROP POLICY IF EXISTS drawings_insert_access ON public.schedule_drawings;
DROP POLICY IF EXISTS drawings_update_access ON public.schedule_drawings;
DROP POLICY IF EXISTS drawings_delete_access ON public.schedule_drawings;

CREATE POLICY drawings_select_access
ON public.schedule_drawings
FOR SELECT
USING (public.fn_can_read_book(book_uuid));

CREATE POLICY drawings_insert_access
ON public.schedule_drawings
FOR INSERT
WITH CHECK (public.fn_can_write_book(book_uuid));

CREATE POLICY drawings_update_access
ON public.schedule_drawings
FOR UPDATE
USING (public.fn_can_write_book(book_uuid))
WITH CHECK (public.fn_can_write_book(book_uuid));

CREATE POLICY drawings_delete_access
ON public.schedule_drawings
FOR DELETE
USING (public.fn_can_write_book(book_uuid));

-- records --------------------------------------------------------------------
DROP POLICY IF EXISTS records_select_access ON public.records;
DROP POLICY IF EXISTS records_insert_authenticated ON public.records;
DROP POLICY IF EXISTS records_update_access ON public.records;
DROP POLICY IF EXISTS records_delete_access ON public.records;

CREATE POLICY records_select_access
ON public.records
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = records.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_read_book(e.book_uuid)
  )
);

-- Needed because event creation may insert record before event row exists.
CREATE POLICY records_insert_authenticated
ON public.records
FOR INSERT
WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY records_update_access
ON public.records
FOR UPDATE
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = records.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = records.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
);

CREATE POLICY records_delete_access
ON public.records
FOR DELETE
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = records.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
);

-- notes ----------------------------------------------------------------------
DROP POLICY IF EXISTS notes_select_access ON public.notes;
DROP POLICY IF EXISTS notes_insert_access ON public.notes;
DROP POLICY IF EXISTS notes_update_access ON public.notes;
DROP POLICY IF EXISTS notes_delete_access ON public.notes;

CREATE POLICY notes_select_access
ON public.notes
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = notes.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_read_book(e.book_uuid)
  )
);

CREATE POLICY notes_insert_access
ON public.notes
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = notes.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
);

CREATE POLICY notes_update_access
ON public.notes
FOR UPDATE
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = notes.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = notes.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
);

CREATE POLICY notes_delete_access
ON public.notes
FOR DELETE
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = notes.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
);

-- charge_items ----------------------------------------------------------------
DROP POLICY IF EXISTS charge_items_select_access ON public.charge_items;
DROP POLICY IF EXISTS charge_items_insert_access ON public.charge_items;
DROP POLICY IF EXISTS charge_items_update_access ON public.charge_items;
DROP POLICY IF EXISTS charge_items_delete_access ON public.charge_items;

CREATE POLICY charge_items_select_access
ON public.charge_items
FOR SELECT
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = charge_items.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_read_book(e.book_uuid)
  )
);

CREATE POLICY charge_items_insert_access
ON public.charge_items
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = charge_items.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
);

CREATE POLICY charge_items_update_access
ON public.charge_items
FOR UPDATE
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = charge_items.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = charge_items.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
);

CREATE POLICY charge_items_delete_access
ON public.charge_items
FOR DELETE
USING (
  EXISTS (
    SELECT 1
    FROM public.events e
    WHERE e.record_uuid = charge_items.record_uuid
      AND e.is_deleted = false
      AND public.fn_can_write_book(e.book_uuid)
  )
);

-- sync_log: no client policies on purpose ------------------------------------
DROP POLICY IF EXISTS sync_log_no_client_access ON public.sync_log;

-- Grants for authenticated clients -------------------------------------------
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.devices TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.books TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.book_device_access TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.events TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.records TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notes TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.schedule_drawings TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.charge_items TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

COMMIT;
