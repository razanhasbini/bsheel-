-- Seed admin user: admin@admin.com
-- Auth user must already exist in auth.users (created via Supabase Dashboard)

INSERT INTO public.profiles (id, username, display_name)
VALUES (
  '9a01d5fa-f32e-4e1e-9ca1-5ebca556e8bd',
  'admin',
  'Admin'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.admins (user_id, role)
VALUES (
  '9a01d5fa-f32e-4e1e-9ca1-5ebca556e8bd',
  'super_admin'
)
ON CONFLICT (user_id) DO NOTHING;
