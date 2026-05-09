# mobile_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## CI Quality Gate (No Direct Supabase)

This repo enforces that new Dart changes do not introduce direct Supabase table/RPC/storage access.

### Local run

```bash
./tool/check_no_direct_supabase.sh --changed
./tool/ci_quality_gate.sh
```

### CI command

Use this command in your CI pipeline:

```bash
./tool/ci_quality_gate.sh
```

### Notes

- `check_no_direct_supabase.sh --changed` checks only changed Dart files (recommended for incremental migration).
- `check_no_direct_supabase.sh --all` audits the full codebase and will currently fail while legacy code still exists.
