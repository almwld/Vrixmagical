import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'soft_body_contract.dart';

typedef _CreateNative = Pointer<Void> Function(
  Pointer<Float>, Int32, Pointer<Uint32>, Int32,
  Float, Float, Float, Float, Float, Int32, Int32,
);
typedef _CreateDart = Pointer<Void> Function(
  Pointer<Float>, int, Pointer<Uint32>, int,
  double, double, double, double, double, int, int,
);
typedef _StepNative = Int32 Function(Pointer<Void>, Float);
typedef _StepDart = int Function(Pointer<Void>, double);
typedef _TargetNative = Int32 Function(Pointer<Void>, Int32, Pointer<Float>, Float);
typedef _TargetDart = int Function(Pointer<Void>, int, Pointer<Float>, double);
typedef _ClearTargetNative = Int32 Function(Pointer<Void>, Int32);
typedef _ClearTargetDart = int Function(Pointer<Void>, int);
typedef _ReadNative = Int32 Function(Pointer<Void>, Pointer<Float>, Pointer<Float>, Int32);
typedef _ReadDart = int Function(Pointer<Void>, Pointer<Float>, Pointer<Float>, int);
typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);
typedef _NameNative = Pointer<Char> Function();
typedef _NameDart = Pointer<Char> Function();

/// Dart FFI adapter for the pinned PositionBasedDynamics XPBD/FEM implementation.
/// Android arm64 is the supported runtime target; no Dart fallback solver exists.
class VrixSoftBodyFfiEngine implements VrixSoftBodyEngine {
  VrixSoftBodyFfiEngine._(DynamicLibrary library)
      : _create = library.lookupFunction<_CreateNative, _CreateDart>('vrix_soft_body_create'),
        _step = library.lookupFunction<_StepNative, _StepDart>('vrix_soft_body_step'),
        _setTarget = library.lookupFunction<_TargetNative, _TargetDart>('vrix_soft_body_set_point_target'),
        _clearTarget = library.lookupFunction<_ClearTargetNative, _ClearTargetDart>('vrix_soft_body_clear_point_target'),
        _readState = library.lookupFunction<_ReadNative, _ReadDart>('vrix_soft_body_read_state'),
        _destroy = library.lookupFunction<_DestroyNative, _DestroyDart>('vrix_soft_body_destroy'),
        backendName = library.lookupFunction<_NameNative, _NameDart>('vrix_soft_body_backend_name')().cast<Utf8>().toDartString();

  factory VrixSoftBodyFfiEngine.open({DynamicLibrary? library}) {
    final loaded = library ?? _openPlatformLibrary();
    return VrixSoftBodyFfiEngine._(loaded);
  }

  static DynamicLibrary _openPlatformLibrary() {
    if (Platform.isAndroid || Platform.isLinux) {
      return DynamicLibrary.open('libvrix_soft_body.so');
    }
    throw UnsupportedError('VRIX XPBD native backend currently supports Android arm64 only.');
  }

  final _CreateDart _create;
  final _StepDart _step;
  final _TargetDart _setTarget;
  final _ClearTargetDart _clearTarget;
  final _ReadDart _readState;
  final _DestroyDart _destroy;
  final String backendName;
  final Map<int, int> _vertexCounts = <int, int>{};
  bool _disposed = false;

  @override
  SoftBodyBackendStatus get status => _disposed ? SoftBodyBackendStatus.disposed : SoftBodyBackendStatus.ready;

  @override
  SoftBodyHandle createBody({
    required SoftBodyMeshData mesh,
    required SoftBodyMaterial material,
    required SoftBodySolverConfig config,
  }) {
    _ensureActive();
    mesh.validate();
    material.validate();
    config.validate();
    final positions = calloc<Float>(mesh.positions.length);
    final tetrahedra = calloc<Uint32>(mesh.tetrahedronIndices.length);
    try {
      for (var i = 0; i < mesh.positions.length; i++) {
        positions[i] = mesh.positions[i];
      }
      for (var i = 0; i < mesh.tetrahedronIndices.length; i++) {
        tetrahedra[i] = mesh.tetrahedronIndices[i];
      }
      final pointer = _create(
        positions, mesh.vertexCount, tetrahedra, mesh.tetrahedronCount,
        material.densityKgPerM3, material.youngsModulusPa,
        material.poissonRatio, material.damping,
        config.fixedTimeStepSeconds, config.solverIterations, config.maxSubSteps,
      );
      if (pointer.address == 0) {
        throw StateError('Native XPBD rejected the tetrahedral mesh or material settings.');
      }
      _vertexCounts[pointer.address] = mesh.vertexCount;
      return SoftBodyHandle.fromNative(pointer.address);
    } finally {
      calloc.free(positions);
      calloc.free(tetrahedra);
    }
  }

  @override
  void step(double deltaSeconds) {
    _ensureActive();
    if (!deltaSeconds.isFinite || deltaSeconds < 0) {
      throw ArgumentError.value(deltaSeconds, 'deltaSeconds');
    }
    for (final address in _vertexCounts.keys.toList(growable: false)) {
      if (_step(Pointer<Void>.fromAddress(address), deltaSeconds) < 0) {
        throw StateError('Native XPBD step failed for body $address.');
      }
    }
  }

  @override
  void setPointTarget({
    required SoftBodyHandle body,
    required int vertexIndex,
    required List<double> targetObjectPosition,
    double compliance = 0,
  }) {
    _ensureActive();
    final count = _requireBody(body);
    if (vertexIndex < 0 || vertexIndex >= count) {
      throw RangeError.value(vertexIndex, 'vertexIndex');
    }
    if (targetObjectPosition.length != 3 ||
        targetObjectPosition.any((value) => !value.isFinite) ||
        !compliance.isFinite || compliance < 0) {
      throw ArgumentError('Target must be finite XYZ with non-negative compliance.');
    }
    final target = calloc<Float>(3);
    try {
      for (var i = 0; i < 3; i++) {
        target[i] = targetObjectPosition[i];
      }
      if (_setTarget(Pointer<Void>.fromAddress(body.value), vertexIndex, target, compliance) == 0) {
        throw StateError('Native XPBD rejected the point target.');
      }
    } finally {
      calloc.free(target);
    }
  }

  /// Clears a hand/touch target without destroying the simulated body.
  void clearPointTarget({required SoftBodyHandle body, required int vertexIndex}) {
    _ensureActive();
    final count = _requireBody(body);
    if (vertexIndex < 0 || vertexIndex >= count) {
      throw RangeError.value(vertexIndex, 'vertexIndex');
    }
    if (_clearTarget(Pointer<Void>.fromAddress(body.value), vertexIndex) == 0) {
      throw StateError('Native XPBD could not clear the point target.');
    }
  }

  @override
  SoftBodyState readState(SoftBodyHandle body) {
    _ensureActive();
    final count = _requireBody(body);
    final positions = calloc<Float>(count * 3);
    final velocities = calloc<Float>(count * 3);
    try {
      final read = _readState(Pointer<Void>.fromAddress(body.value), positions, velocities, count);
      if (read != count) {
        throw StateError('Native XPBD returned an incomplete state buffer.');
      }
      return SoftBodyState(
        positions: positions.asTypedList(count * 3).map((v) => v.toDouble()).toList(),
        velocities: velocities.asTypedList(count * 3).map((v) => v.toDouble()).toList(),
      );
    } finally {
      calloc.free(positions);
      calloc.free(velocities);
    }
  }

  @override
  void removeBody(SoftBodyHandle body) {
    _ensureActive();
    if (_vertexCounts.remove(body.value) == null) return;
    _destroy(Pointer<Void>.fromAddress(body.value));
  }

  @override
  void dispose() {
    if (_disposed) return;
    for (final address in _vertexCounts.keys.toList(growable: false)) {
      _destroy(Pointer<Void>.fromAddress(address));
    }
    _vertexCounts.clear();
    _disposed = true;
  }

  int _requireBody(SoftBodyHandle body) {
    final count = _vertexCounts[body.value];
    if (count == null) {
      throw StateError('Unknown or disposed soft-body handle ${body.value}.');
    }
    return count;
  }

  void _ensureActive() {
    if (_disposed) throw StateError('The VRIX XPBD engine has been disposed.');
  }
}
