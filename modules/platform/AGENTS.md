# Working on platform

Read [module notes](README.md) and [C17](../../docs/design/03-conventions.md#c17-platform-source-sets)
before editing source sets, build scripts or FFI.

Place runnable module tests in the appropriate product set (`linux`, `darwin`,
`windows`); common/intermediate-set tests are silently skipped by cjpm
([K16](../../docs/sdk-issues.md#k16)). Cross-OS type checking does not run those tests.
