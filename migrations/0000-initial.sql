CREATE ROLE b3 WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS ENCRYPTED PASSWORD 'development';

CREATE DATABASE b3;

\c b3

GRANT USAGE ON SCHEMA public TO b3;

CREATE OR REPLACE FUNCTION public.tf_set_updated_at()
RETURNS TRIGGER AS
$$
    BEGIN
        NEW.updated_at := now();
        RETURN NEW;
    END;
$$
LANGUAGE 'plpgsql';

ALTER FUNCTION public.tf_set_updated_at OWNER TO lab;

GRANT EXECUTE ON FUNCTION public.tf_set_updated_at TO b3;

REVOKE ALL ON FUNCTION public.tf_set_updated_at FROM public;

CREATE TABLE public.t_audit (
    id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    run_at TIMESTAMP NOT NULL DEFAULT clock_timestamp(),
    database_user TEXT NOT NULL,
    application_user TEXT NOT NULL,
    origin_ip INET NOT NULL,
    schema TEXT NOT NULL,
    "table" TEXT NOT NULL,
    operation TEXT NOT NULL,
    query TEXT NOT NULL,
    request_id UUID,
    old JSONB,
    new JSONB
);

ALTER TABLE public.t_audit OWNER TO lab;

REVOKE ALL ON TABLE public.t_audit FROM public;

GRANT INSERT ON TABLE public.t_audit TO public;

CREATE OR REPLACE FUNCTION public.tf_add_audit()
RETURNS TRIGGER AS
$$
    DECLARE
        _old JSONB := NULL;
        _new JSONB := NULL;

        _user_id    TEXT := NULL;
        _request_id TEXT := NULL;

        _super      BOOLEAN := FALSE;
    BEGIN
        IF TG_OP = 'INSERT' THEN
            _new := to_jsonb(NEW.*);
        END IF;

        IF TG_OP = 'UPDATE' THEN
            _old := to_jsonb(OLD.*);
            _new := to_jsonb(NEW.*);
        END IF;

        IF TG_OP = 'DELETE' THEN
            _old := to_jsonb(OLD.*);
        END IF;

        BEGIN
            SHOW application.user_id    INTO _user_id;
            SHOW application.request_id INTO _request_id;
        EXCEPTION WHEN OTHERS THEN
            SHOW IS_SUPERUSER INTO _super;
            IF _super THEN
                _user_id := 'SUPER_USER';
                _request_id := NULL;
            ELSE
                RAISE EXCEPTION assert_failure USING HINT = 'unable to perform operations without the associated user/request';
            END IF;

        END;

        INSERT INTO public.t_audit(database_user, application_user, origin_ip, schema, "table", operation, query, request_id, old, new)
        VALUES (CURRENT_USER, _user_id,  COALESCE(inet_client_addr(), '127.0.0.1'::INET),  TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, current_query(), _request_id::UUID, _old, _new);

        IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
            RETURN NEW;
        END IF;

        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;

        RETURN NULL;
    END;
$$
LANGUAGE 'plpgsql';

ALTER FUNCTION public.tf_add_audit() OWNER TO lab;

REVOKE ALL ON FUNCTION public.tf_add_audit() FROM public;

GRANT EXECUTE ON FUNCTION public.tf_add_audit() TO public;

CREATE TABLE public.t_migration (
    id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP,
    name TEXT NOT NULL CHECK(char_length(name) BETWEEN 4 AND 128),
    rolled_back BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.t_migration
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM  NEW.*)
EXECUTE PROCEDURE public.tf_set_updated_at();

CREATE TRIGGER add_audit
BEFORE UPDATE OR DELETE OR INSERT ON public.t_migration
FOR EACH ROW
EXECUTE PROCEDURE public.tf_add_audit();

ALTER TABLE public.t_migration OWNER TO lab;

GRANT SELECT ON TABLE public.t_migration TO b3;

REVOKE ALL ON TABLE public.t_migration FROM public;

CREATE TABLE public.t_outgoing_message (
    id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP,
    sent_at TIMESTAMP,
    error TEXT,
    queue TEXT NOT NULL,
    payload JSONB NOT NULL
);

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.t_outgoing_message
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM  NEW.*)
EXECUTE PROCEDURE public.tf_set_updated_at();

CREATE TRIGGER add_audit
BEFORE UPDATE OR DELETE OR INSERT ON public.t_outgoing_message
FOR EACH ROW
EXECUTE PROCEDURE public.tf_add_audit();

ALTER TABLE public.t_outgoing_message OWNER TO lab;

GRANT SELECT, INSERT, UPDATE ON TABLE public.t_outgoing_message TO b3;

REVOKE ALL ON TABLE public.t_outgoing_message FROM public;

CREATE TABLE public.t_broker (
    id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP,
    code INTEGER NOT NULL,
    name TEXT NOT NULL CHECK(char_length(name) BETWEEN 4 AND 128)
);

CREATE UNIQUE INDEX t_broker_name_unique ON public.t_broker(name) WHERE deleted_at IS NULL;

ALTER TABLE public.t_broker OWNER TO lab;

GRANT SELECT, INSERT, UPDATE ON TABLE public.t_broker TO b3;

REVOKE ALL ON TABLE public.t_broker FROM public;

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.t_broker
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM  NEW.*)
EXECUTE PROCEDURE public.tf_set_updated_at();

CREATE TRIGGER add_audit
BEFORE UPDATE OR DELETE OR INSERT ON public.t_broker
FOR EACH ROW
EXECUTE PROCEDURE public.tf_add_audit();

CREATE TABLE public.t_broker_account (
    id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP,
    broker_id UUID NOT NULL REFERENCES public.t_broker,
    user_id UUID NOT NULL,
    number BIGINT NOT NULL
);

CREATE UNIQUE INDEX t_broker_account_number_broker_unique ON public.t_broker_account(number, broker_id) WHERE deleted_at IS NULL;

ALTER TABLE public.t_broker_account OWNER TO lab;

GRANT SELECT, INSERT, UPDATE ON TABLE public.t_broker_account TO b3;

REVOKE ALL ON TABLE public.t_broker_account FROM public;

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.t_broker_account
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM  NEW.*)
EXECUTE PROCEDURE public.tf_set_updated_at();

CREATE TRIGGER add_audit
BEFORE UPDATE OR DELETE OR INSERT ON public.t_broker_account
FOR EACH ROW
EXECUTE PROCEDURE public.tf_add_audit();

CREATE TABLE public.t_symbol (
    id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    fullname TEXT,
    kind SMALLINT,
    registry BIGINT,
    writer TEXT,
    price BIGINT,
    change INTEGER
);

CREATE UNIQUE INDEX t_symbol_code_unique ON public.t_symbol(code) WHERE deleted_at IS NULL;

ALTER TABLE public.t_symbol OWNER TO lab;

GRANT SELECT, INSERT, UPDATE ON TABLE public.t_symbol TO b3;

REVOKE ALL ON TABLE public.t_symbol FROM public;

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.t_symbol
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM  NEW.*)
EXECUTE PROCEDURE public.tf_set_updated_at();

CREATE TRIGGER add_audit
BEFORE UPDATE OR DELETE OR INSERT ON public.t_symbol
FOR EACH ROW
EXECUTE PROCEDURE public.tf_add_audit();

CREATE TABLE public.t_trade (
    id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP,
    user_id UUID NOT NULL,
    broker_account_id UUID NOT NULL REFERENCES public.t_broker_account(id),
    date DATE NOT NULL DEFAULT NOW(),
    operation SMALLINT NOT NULL DEFAULT 1,
    market_kind TEXT,
    symbol_id UUID NOT NULL REFERENCES public.t_symbol(id),
    amount BIGINT NOT NULL,
    value BIGINT NOT NULL
);

ALTER TABLE public.t_trade OWNER TO lab;

GRANT SELECT, INSERT, UPDATE ON TABLE public.t_trade TO b3;

REVOKE ALL ON TABLE public.t_trade FROM public;

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.t_trade
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM  NEW.*)
EXECUTE PROCEDURE public.tf_set_updated_at();

CREATE TRIGGER add_audit
BEFORE UPDATE OR DELETE OR INSERT ON public.t_trade
FOR EACH ROW
EXECUTE PROCEDURE public.tf_add_audit();

CREATE TABLE public.t_job (
    id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP,
    kind SMALLINT NOT NULL,
    payload JSONB NOT NULL,
    timeout SMALLINT NOT NULL DEFAULT 10,
    user_id UUID,
    started_at TIMESTAMP,
    finished_at TIMESTAMP,
    error TEXT
);

ALTER TABLE public.t_job OWNER TO lab;

GRANT SELECT, INSERT, UPDATE ON TABLE public.t_job TO b3;

REVOKE ALL ON TABLE public.t_job FROM public;

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.t_job
FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM  NEW.*)
EXECUTE PROCEDURE public.tf_set_updated_at();

CREATE TRIGGER add_audit
BEFORE UPDATE OR DELETE OR INSERT ON public.t_job
FOR EACH ROW
EXECUTE PROCEDURE public.tf_add_audit();

SET application.user_id TO 'migration';

INSERT INTO public.t_migration (name) VALUES ('0000');
