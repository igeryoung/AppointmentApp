-- Account-based device recovery migration.
-- Run this in the Supabase SQL editor before deploying the account-auth server.

BEGIN;

CREATE TABLE IF NOT EXISTS public.accounts
(
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    username text COLLATE pg_catalog."default" NOT NULL,
    password_hash text COLLATE pg_catalog."default" NOT NULL,
    password_salt text COLLATE pg_catalog."default" NOT NULL,
    password_iterations integer NOT NULL DEFAULT 120000,
    account_role text COLLATE pg_catalog."default" NOT NULL DEFAULT 'read'::text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT accounts_pkey PRIMARY KEY (id),
    CONSTRAINT accounts_username_key UNIQUE (username),
    CONSTRAINT accounts_account_role_check CHECK (account_role = ANY (ARRAY['read'::text, 'write'::text]))
);

CREATE TABLE IF NOT EXISTS public.account_book_access
(
    book_uuid uuid NOT NULL,
    account_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT account_book_access_pkey PRIMARY KEY (book_uuid, account_id)
);

ALTER TABLE public.devices
    ADD COLUMN IF NOT EXISTS account_id uuid;

ALTER TABLE public.books
    ADD COLUMN IF NOT EXISTS owner_account_id uuid;

ALTER TABLE public.books
    DROP CONSTRAINT IF EXISTS books_device_id_fkey,
    ALTER COLUMN device_id DROP NOT NULL,
    ADD CONSTRAINT books_device_id_fkey FOREIGN KEY (device_id)
    REFERENCES public.devices (id)
    ON DELETE SET NULL;

ALTER TABLE public.account_book_access
    DROP CONSTRAINT IF EXISTS account_book_access_account_id_fkey,
    ADD CONSTRAINT account_book_access_account_id_fkey FOREIGN KEY (account_id)
    REFERENCES public.accounts (id)
    ON DELETE CASCADE;

ALTER TABLE public.account_book_access
    DROP CONSTRAINT IF EXISTS account_book_access_book_uuid_fkey,
    ADD CONSTRAINT account_book_access_book_uuid_fkey FOREIGN KEY (book_uuid)
    REFERENCES public.books (book_uuid)
    ON DELETE CASCADE;

ALTER TABLE public.devices
    DROP CONSTRAINT IF EXISTS devices_account_id_fkey,
    ADD CONSTRAINT devices_account_id_fkey FOREIGN KEY (account_id)
    REFERENCES public.accounts (id)
    ON DELETE SET NULL;

ALTER TABLE public.books
    DROP CONSTRAINT IF EXISTS books_owner_account_id_fkey,
    ADD CONSTRAINT books_owner_account_id_fkey FOREIGN KEY (owner_account_id)
    REFERENCES public.accounts (id)
    ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_devices_account_id
    ON public.devices(account_id);
CREATE INDEX IF NOT EXISTS idx_books_owner_account_id
    ON public.books(owner_account_id);
CREATE INDEX IF NOT EXISTS idx_account_book_access_account_id
    ON public.account_book_access(account_id);

COMMIT;
