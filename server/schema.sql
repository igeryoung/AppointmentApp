--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4 (Postgres.app)
-- Dumped by pg_dump version 16.4 (Postgres.app)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: increment_version(); Type: FUNCTION; Schema: public; Owner: yangping
--

CREATE FUNCTION public.increment_version() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.version = OLD.version + 1;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.increment_version() OWNER TO yangping;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: yangping
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO yangping;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: book_backups; Type: TABLE; Schema: public; Owner: yangping
--

CREATE TABLE public.book_backups (
    id integer NOT NULL,
    backup_name character varying(255) NOT NULL,
    device_id uuid NOT NULL,
    backup_data jsonb,
    backup_size integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    restored_at timestamp without time zone,
    is_deleted boolean DEFAULT false,
    book_uuid uuid,
    backup_path text,
    backup_size_bytes bigint,
    backup_type character varying(50) DEFAULT 'full'::character varying,
    status character varying(50) DEFAULT 'completed'::character varying,
    error_message text,
    restored_by_device_id uuid
);


ALTER TABLE public.book_backups OWNER TO yangping;

--
-- Name: TABLE book_backups; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON TABLE public.book_backups IS 'Book backups table - uses book_uuid (UUID) to identify books. The book_id column has been removed.';


--
-- Name: COLUMN book_backups.backup_data; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.book_backups.backup_data IS 'JSONB backup (legacy) - new backups should use backup_path';


--
-- Name: COLUMN book_backups.backup_size; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.book_backups.backup_size IS 'Total size of backup data in bytes';


--
-- Name: COLUMN book_backups.book_uuid; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.book_backups.book_uuid IS 'Globally unique book identifier (UUID). This is the authoritative identifier for books across all devices. Always use this for queries instead of book_id.';


--
-- Name: COLUMN book_backups.backup_path; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.book_backups.backup_path IS 'Relative path from backup root directory (for file-based backups)';


--
-- Name: COLUMN book_backups.backup_type; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.book_backups.backup_type IS 'full: complete backup, incremental: changes only (future)';


--
-- Name: COLUMN book_backups.status; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.book_backups.status IS 'in_progress, completed, failed - tracks async backup operations';


--
-- Name: book_backups_id_seq; Type: SEQUENCE; Schema: public; Owner: yangping
--

CREATE SEQUENCE public.book_backups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.book_backups_id_seq OWNER TO yangping;

--
-- Name: book_backups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: yangping
--

ALTER SEQUENCE public.book_backups_id_seq OWNED BY public.book_backups.id;


--
-- Name: books; Type: TABLE; Schema: public; Owner: yangping
--

CREATE TABLE public.books (
    device_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    archived_at timestamp without time zone,
    synced_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false,
    book_uuid uuid NOT NULL
);


ALTER TABLE public.books OWNER TO yangping;

--
-- Name: TABLE books; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON TABLE public.books IS 'Books table - book_uuid (UUID) is the PRIMARY KEY. The auto-increment id column has been removed. All references to books use book_uuid.';


--
-- Name: COLUMN books.synced_at; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.books.synced_at IS 'Last time this record was synced to server';


--
-- Name: COLUMN books.version; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.books.version IS 'Incremented on each update for conflict detection';


--
-- Name: COLUMN books.is_deleted; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.books.is_deleted IS 'Soft delete flag for sync purposes';


--
-- Name: COLUMN books.book_uuid; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.books.book_uuid IS 'PRIMARY KEY - Globally unique book identifier across all devices.';


--
-- Name: devices; Type: TABLE; Schema: public; Owner: yangping
--

CREATE TABLE public.devices (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    device_name character varying(255) NOT NULL,
    device_token character varying(512) NOT NULL,
    platform character varying(50),
    registered_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_sync_at timestamp without time zone,
    is_active boolean DEFAULT true
);


ALTER TABLE public.devices OWNER TO yangping;

--
-- Name: TABLE devices; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON TABLE public.devices IS 'Tracks all registered devices for sync';


--
-- Name: events; Type: TABLE; Schema: public; Owner: yangping
--

CREATE TABLE public.events (
    id integer NOT NULL,
    device_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    record_number character varying(100) NOT NULL,
    event_type character varying(100) NOT NULL,
    start_time timestamp without time zone NOT NULL,
    end_time timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    is_removed boolean DEFAULT false,
    removal_reason text,
    original_event_id integer,
    new_event_id integer,
    synced_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false,
    book_uuid uuid NOT NULL
);


ALTER TABLE public.events OWNER TO yangping;

--
-- Name: TABLE events; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON TABLE public.events IS 'Events table - uses book_uuid (UUID) to reference books. The book_id column has been removed.';


--
-- Name: events_id_seq; Type: SEQUENCE; Schema: public; Owner: yangping
--

CREATE SEQUENCE public.events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.events_id_seq OWNER TO yangping;

--
-- Name: events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: yangping
--

ALTER SEQUENCE public.events_id_seq OWNED BY public.events.id;


--
-- Name: notes; Type: TABLE; Schema: public; Owner: yangping
--

CREATE TABLE public.notes (
    id integer NOT NULL,
    event_id integer NOT NULL,
    device_id uuid NOT NULL,
    strokes_data text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    synced_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false,
    person_name_normalized text,
    record_number_normalized text,
    locked_by_device_id text,
    locked_at timestamp without time zone
);


ALTER TABLE public.notes OWNER TO yangping;

--
-- Name: TABLE notes; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON TABLE public.notes IS 'Handwriting-only notes linked to events';


--
-- Name: COLUMN notes.person_name_normalized; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.notes.person_name_normalized IS 'Normalized (trimmed, lowercase) person name for shared notes';


--
-- Name: COLUMN notes.record_number_normalized; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.notes.record_number_normalized IS 'Normalized (trimmed, lowercase) record number for shared notes';


--
-- Name: COLUMN notes.locked_by_device_id; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.notes.locked_by_device_id IS 'Device ID that currently holds the edit lock (NULL = unlocked)';


--
-- Name: COLUMN notes.locked_at; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON COLUMN public.notes.locked_at IS 'Timestamp when lock was acquired (NULL = unlocked)';


--
-- Name: notes_id_seq; Type: SEQUENCE; Schema: public; Owner: yangping
--

CREATE SEQUENCE public.notes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notes_id_seq OWNER TO yangping;

--
-- Name: notes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: yangping
--

ALTER SEQUENCE public.notes_id_seq OWNED BY public.notes.id;


--
-- Name: schedule_drawings; Type: TABLE; Schema: public; Owner: yangping
--

CREATE TABLE public.schedule_drawings (
    id integer NOT NULL,
    device_id uuid NOT NULL,
    date timestamp without time zone NOT NULL,
    view_mode integer NOT NULL,
    strokes_data text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    synced_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    is_deleted boolean DEFAULT false,
    book_uuid uuid NOT NULL
);


ALTER TABLE public.schedule_drawings OWNER TO yangping;

--
-- Name: TABLE schedule_drawings; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON TABLE public.schedule_drawings IS 'Schedule drawings table - uses book_uuid (UUID) to reference books. The book_id column has been removed.';


--
-- Name: schedule_drawings_id_seq; Type: SEQUENCE; Schema: public; Owner: yangping
--

CREATE SEQUENCE public.schedule_drawings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.schedule_drawings_id_seq OWNER TO yangping;

--
-- Name: schedule_drawings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: yangping
--

ALTER SEQUENCE public.schedule_drawings_id_seq OWNED BY public.schedule_drawings.id;


--
-- Name: sync_log; Type: TABLE; Schema: public; Owner: yangping
--

CREATE TABLE public.sync_log (
    id integer NOT NULL,
    device_id uuid NOT NULL,
    operation character varying(50) NOT NULL,
    table_name character varying(50) NOT NULL,
    record_id integer,
    status character varying(50) NOT NULL,
    error_message text,
    changes_count integer DEFAULT 0,
    synced_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


ALTER TABLE public.sync_log OWNER TO yangping;

--
-- Name: TABLE sync_log; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON TABLE public.sync_log IS 'Audit trail of all sync operations';


--
-- Name: sync_log_id_seq; Type: SEQUENCE; Schema: public; Owner: yangping
--

CREATE SEQUENCE public.sync_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.sync_log_id_seq OWNER TO yangping;

--
-- Name: sync_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: yangping
--

ALTER SEQUENCE public.sync_log_id_seq OWNED BY public.sync_log.id;


--
-- Name: book_backups id; Type: DEFAULT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.book_backups ALTER COLUMN id SET DEFAULT nextval('public.book_backups_id_seq'::regclass);


--
-- Name: events id; Type: DEFAULT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.events ALTER COLUMN id SET DEFAULT nextval('public.events_id_seq'::regclass);


--
-- Name: notes id; Type: DEFAULT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.notes ALTER COLUMN id SET DEFAULT nextval('public.notes_id_seq'::regclass);


--
-- Name: schedule_drawings id; Type: DEFAULT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.schedule_drawings ALTER COLUMN id SET DEFAULT nextval('public.schedule_drawings_id_seq'::regclass);


--
-- Name: sync_log id; Type: DEFAULT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.sync_log ALTER COLUMN id SET DEFAULT nextval('public.sync_log_id_seq'::regclass);


--
-- Name: book_backups book_backups_pkey; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.book_backups
    ADD CONSTRAINT book_backups_pkey PRIMARY KEY (id);


--
-- Name: books books_book_uuid_key; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_book_uuid_key UNIQUE (book_uuid);


--
-- Name: books books_pkey; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_pkey PRIMARY KEY (book_uuid);


--
-- Name: devices devices_device_token_key; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_device_token_key UNIQUE (device_token);


--
-- Name: devices devices_pkey; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: notes notes_event_id_key; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_event_id_key UNIQUE (event_id);


--
-- Name: notes notes_pkey; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_pkey PRIMARY KEY (id);


--
-- Name: schedule_drawings schedule_drawings_pkey; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.schedule_drawings
    ADD CONSTRAINT schedule_drawings_pkey PRIMARY KEY (id);


--
-- Name: sync_log sync_log_pkey; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.sync_log
    ADD CONSTRAINT sync_log_pkey PRIMARY KEY (id);


--
-- Name: schedule_drawings unique_book_uuid_date_view; Type: CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.schedule_drawings
    ADD CONSTRAINT unique_book_uuid_date_view UNIQUE (book_uuid, date, view_mode);


--
-- Name: idx_book_backups_created; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_book_backups_created ON public.book_backups USING btree (created_at);


--
-- Name: idx_book_backups_deleted; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_book_backups_deleted ON public.book_backups USING btree (is_deleted) WHERE (is_deleted = false);


--
-- Name: idx_book_backups_device; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_book_backups_device ON public.book_backups USING btree (device_id);


--
-- Name: idx_book_backups_device_uuid; Type: INDEX; Schema: public; Owner: yangping
--

CREATE UNIQUE INDEX idx_book_backups_device_uuid ON public.book_backups USING btree (device_id, book_uuid) WHERE (is_deleted = false);


--
-- Name: INDEX idx_book_backups_device_uuid; Type: COMMENT; Schema: public; Owner: yangping
--

COMMENT ON INDEX public.idx_book_backups_device_uuid IS 'Ensures one active backup per book per device';


--
-- Name: idx_book_backups_status; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_book_backups_status ON public.book_backups USING btree (status) WHERE ((status)::text <> 'completed'::text);


--
-- Name: idx_book_backups_uuid; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_book_backups_uuid ON public.book_backups USING btree (book_uuid) WHERE (is_deleted = false);


--
-- Name: idx_books_device; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_books_device ON public.books USING btree (device_id);


--
-- Name: idx_books_uuid; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_books_uuid ON public.books USING btree (book_uuid);


--
-- Name: idx_devices_last_sync; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_devices_last_sync ON public.devices USING btree (last_sync_at);


--
-- Name: idx_devices_token; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_devices_token ON public.devices USING btree (device_token);


--
-- Name: idx_drawings_book_uuid; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_drawings_book_uuid ON public.schedule_drawings USING btree (book_uuid);


--
-- Name: idx_drawings_book_uuid_date_view; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_drawings_book_uuid_date_view ON public.schedule_drawings USING btree (book_uuid, date, view_mode);


--
-- Name: idx_events_book_uuid; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_events_book_uuid ON public.events USING btree (book_uuid);


--
-- Name: idx_events_book_uuid_time; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_events_book_uuid_time ON public.events USING btree (book_uuid, start_time);


--
-- Name: idx_events_device; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_events_device ON public.events USING btree (device_id);


--
-- Name: idx_events_start_time; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_events_start_time ON public.events USING btree (start_time);


--
-- Name: idx_notes_device; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_notes_device ON public.notes USING btree (device_id);


--
-- Name: idx_notes_event; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_notes_event ON public.notes USING btree (event_id);


--
-- Name: idx_notes_locked_by; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_notes_locked_by ON public.notes USING btree (locked_by_device_id);


--
-- Name: idx_notes_person_key; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_notes_person_key ON public.notes USING btree (person_name_normalized, record_number_normalized);


--
-- Name: idx_notes_updated; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_notes_updated ON public.notes USING btree (updated_at DESC);


--
-- Name: idx_schedule_drawings_device; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_schedule_drawings_device ON public.schedule_drawings USING btree (device_id);


--
-- Name: idx_sync_log_device; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_sync_log_device ON public.sync_log USING btree (device_id);


--
-- Name: idx_sync_log_status; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_sync_log_status ON public.sync_log USING btree (status);


--
-- Name: idx_sync_log_synced; Type: INDEX; Schema: public; Owner: yangping
--

CREATE INDEX idx_sync_log_synced ON public.sync_log USING btree (synced_at);


--
-- Name: books increment_books_version; Type: TRIGGER; Schema: public; Owner: yangping
--

CREATE TRIGGER increment_books_version BEFORE UPDATE ON public.books FOR EACH ROW EXECUTE FUNCTION public.increment_version();


--
-- Name: events increment_events_version; Type: TRIGGER; Schema: public; Owner: yangping
--

CREATE TRIGGER increment_events_version BEFORE UPDATE ON public.events FOR EACH ROW EXECUTE FUNCTION public.increment_version();


--
-- Name: notes increment_notes_version; Type: TRIGGER; Schema: public; Owner: yangping
--

CREATE TRIGGER increment_notes_version BEFORE UPDATE ON public.notes FOR EACH ROW EXECUTE FUNCTION public.increment_version();


--
-- Name: schedule_drawings increment_schedule_drawings_version; Type: TRIGGER; Schema: public; Owner: yangping
--

CREATE TRIGGER increment_schedule_drawings_version BEFORE UPDATE ON public.schedule_drawings FOR EACH ROW EXECUTE FUNCTION public.increment_version();


--
-- Name: books update_books_updated_at; Type: TRIGGER; Schema: public; Owner: yangping
--

CREATE TRIGGER update_books_updated_at BEFORE UPDATE ON public.books FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: events update_events_updated_at; Type: TRIGGER; Schema: public; Owner: yangping
--

CREATE TRIGGER update_events_updated_at BEFORE UPDATE ON public.events FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: notes update_notes_updated_at; Type: TRIGGER; Schema: public; Owner: yangping
--

CREATE TRIGGER update_notes_updated_at BEFORE UPDATE ON public.notes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: schedule_drawings update_schedule_drawings_updated_at; Type: TRIGGER; Schema: public; Owner: yangping
--

CREATE TRIGGER update_schedule_drawings_updated_at BEFORE UPDATE ON public.schedule_drawings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: book_backups book_backups_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.book_backups
    ADD CONSTRAINT book_backups_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- Name: books books_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- Name: events events_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- Name: events events_new_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_new_event_id_fkey FOREIGN KEY (new_event_id) REFERENCES public.events(id);


--
-- Name: events events_original_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_original_event_id_fkey FOREIGN KEY (original_event_id) REFERENCES public.events(id);


--
-- Name: schedule_drawings fk_drawings_book_uuid; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.schedule_drawings
    ADD CONSTRAINT fk_drawings_book_uuid FOREIGN KEY (book_uuid) REFERENCES public.books(book_uuid) ON DELETE CASCADE;


--
-- Name: events fk_events_book_uuid; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_events_book_uuid FOREIGN KEY (book_uuid) REFERENCES public.books(book_uuid) ON DELETE CASCADE;


--
-- Name: notes notes_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- Name: notes notes_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;


--
-- Name: schedule_drawings schedule_drawings_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.schedule_drawings
    ADD CONSTRAINT schedule_drawings_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- Name: sync_log sync_log_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: yangping
--

ALTER TABLE ONLY public.sync_log
    ADD CONSTRAINT sync_log_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

