import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_repository.dart';

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AdminRoleEnum?> getCurrentUserRole() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from(Tables.admins)
        .select('${AdminColumns.id}, ${AdminColumns.role}')
        .eq(AdminColumns.userId, uid)
        .maybeSingle();
    if (row == null) return null;
    return AdminRoleEnum.fromDbString(row[AdminColumns.role]?.toString());
  }
}
