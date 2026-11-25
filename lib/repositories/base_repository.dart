import 'package:supabase_flutter/supabase_flutter.dart';

/// Common Supabase client accessor for all repositories. Keeping this in one
/// place makes it possible to swap the backend client in tests later.
abstract class BaseRepository {
  SupabaseClient get client => Supabase.instance.client;
}
