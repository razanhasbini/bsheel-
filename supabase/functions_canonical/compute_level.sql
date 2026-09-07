-- Single canonical level formula. ARC-016. Latest migration: 0132.
-- See app_repositories tests for the matching client-side expectation.
CREATE OR REPLACE FUNCTION public.compute_level(p_xp integer)
RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT greatest(1, greatest(0, coalesce(p_xp, 0)) / 100 + 1);
$$;
GRANT EXECUTE ON FUNCTION public.compute_level(integer) TO anon, authenticated, service_role;
