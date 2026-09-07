-- RLS smoke tests
-- Run these manually to verify policies work correctly

-- Test: Unauthenticated users cannot read profiles
-- set role anon;
-- select count(*) from public.profiles; -- should return 0 or error

-- Test: Authenticated users can read profiles
-- set role authenticated;
-- set request.jwt.claims to '{"sub": "USER_UUID"}';
-- select count(*) from public.profiles; -- should return all profiles

-- Test: Users can only update own profile
-- set role authenticated;
-- set request.jwt.claims to '{"sub": "USER_UUID_1"}';
-- update public.profiles set bio = 'updated' where id = 'USER_UUID_2'; -- should fail
-- update public.profiles set bio = 'updated' where id = 'USER_UUID_1'; -- should succeed

-- TODO: Add more RLS tests for each table
