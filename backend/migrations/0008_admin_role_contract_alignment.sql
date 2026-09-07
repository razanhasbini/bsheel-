-- The legacy product has exactly two privileged roles. Fold the temporary
-- migration-only `admin` value into super_admin before removing it.
CREATE TYPE admin_role_v2 AS ENUM ('moderator', 'super_admin');

ALTER TABLE admins ALTER COLUMN role DROP DEFAULT;
ALTER TABLE admins ALTER COLUMN role TYPE admin_role_v2
USING (
  CASE role::text
    WHEN 'admin' THEN 'super_admin'
    ELSE role::text
  END
)::admin_role_v2;
ALTER TABLE admins ALTER COLUMN role SET DEFAULT 'moderator'::admin_role_v2;

DROP TYPE admin_role;
ALTER TYPE admin_role_v2 RENAME TO admin_role;
