-- =============================================================================
-- HARDENING: fix mutable search_path on ip_subnet_v2 (database linter warning)
-- =============================================================================
-- ip_subnet_v2 only uses pg_catalog string functions (split_part, strpos), so
-- its search_path is pinned to pg_catalog. Other v2 lockout functions already
-- declare SET search_path = badra_core, public.
-- =============================================================================

CREATE OR REPLACE FUNCTION badra_core.ip_subnet_v2(p_ip TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog
AS $$
  SELECT
    CASE
      WHEN p_ip IS NULL OR p_ip = '' THEN ''
      WHEN strpos(p_ip, '.') = 0 THEN p_ip  -- IPv6: treat as its own key
      ELSE split_part(p_ip, '.', 1) || '.' || split_part(p_ip, '.', 2) || '.' || split_part(p_ip, '.', 3)
    END;
$$;
