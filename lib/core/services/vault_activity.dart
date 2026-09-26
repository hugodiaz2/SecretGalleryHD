/// Shared across service instances in the UI isolate.
/// A backup must never replace a vault while a transfer still uses its records.
class VaultActivity {
  static int transfers = 0;
  static bool backup = false;
}