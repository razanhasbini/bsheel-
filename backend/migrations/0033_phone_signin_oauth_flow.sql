BEGIN;

-- Which of CAMARA's two Number Verification V1 flows this attempt was
-- started with.
--
-- The choice is made when the authorization URL is built (fast flow uses
-- Nokia's fast_flow_csp_auth_endpoint as the authorization base; standard
-- flow uses authorization_endpoint) and it dictates how the final verify
-- call must be made — fast passes code+state, standard passes a Bearer
-- token the backend obtained itself. The two are not interchangeable at the
-- callback.
--
-- It is recorded rather than re-derived because the metadata it comes from
-- is cached for an hour: a cache refresh landing between the redirect out
-- and the callback back could otherwise flip the flow mid-attempt and
-- produce a verify call that contradicts the authorization request.
--
-- Nullable with a 'standard' default read at the callback: rows created
-- before this migration were all standard-flow.
ALTER TABLE phone_signin_states
  ADD COLUMN IF NOT EXISTS oauth_flow text
  CHECK (oauth_flow IN ('fast', 'standard'));

COMMENT ON COLUMN phone_signin_states.oauth_flow IS
  'CAMARA Number Verification V1 flow used for this attempt: fast (code+state to verify) or standard (Bearer token to verify).';

COMMIT;
