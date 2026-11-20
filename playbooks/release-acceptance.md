# Playbook: release acceptance

## Goal
Prove a release artifact is built and its native components are packaged.

## Steps
1. Run native regression tests and Dart/Kotlin analyzers/tests.
2. Build Android debug APK, release APK, split ABI APKs and AAB where required.
3. Inspect APK/AAB contents for Jolt, XPBD and SplatKit native libraries for each shipped ABI.
4. Check ELF/ZIP alignment and dependency/license provenance.
5. Run cold-start, resume/pause, load/failure, disposal and soak tests on target devices.
6. Record exact commit, workflow run, artifact and device evidence.

## Acceptance
All required CI stages pass; expected native libraries are packaged; device-specific camera/physics/Vulkan tests pass. CI alone is not production acceptance.
