import 'package:flutter_reality/models/ar_anchor.dart';
import 'package:flutter_reality/models/ar_node.dart';
import 'package:flutter_reality/src/generated/messages.g.dart';
import 'package:flutter_reality/utils/json_converters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

// Type definitions to enforce a consistent use of the API
/// Signature for [ARObjectManager.onNodeTap]: receives the names of the
/// nodes hit by a tap.
typedef NodeTapResultHandler = void Function(List<String> nodes);

/// Signature for [ARObjectManager.onPanStart]: receives the name of the node
/// that started being dragged.
typedef NodePanStartHandler = void Function(String node);

/// Signature for [ARObjectManager.onPanChange]: receives the name of the
/// node whose drag position was updated.
typedef NodePanChangeHandler = void Function(String node);

/// Signature for [ARObjectManager.onPanEnd]: receives the name of the node
/// that stopped being dragged and its resulting transform.
typedef NodePanEndHandler = void Function(String node, Matrix4 transform);

/// Signature for [ARObjectManager.onRotationStart]: receives the name of the
/// node that started being rotated.
typedef NodeRotationStartHandler = void Function(String node);

/// Signature for [ARObjectManager.onRotationChange]: receives the name of
/// the node whose rotation was updated.
typedef NodeRotationChangeHandler = void Function(String node);

/// Signature for [ARObjectManager.onRotationEnd]: receives the name of the
/// node that stopped being rotated and its resulting transform.
typedef NodeRotationEndHandler = void Function(String node, Matrix4 transform);

/// Signature for [ARObjectManager.onError]: receives a human-readable
/// description of a native node-related error.
typedef NodeErrorHandler = void Function(String error);

/// Manages the all node-related actions of an [ARView]
class ARObjectManager {
  late ARObjectHostApi _hostApi;
  final MethodChannel _meshChannel;

  /// Debugging status flag. If true, all platform calls are printed. Defaults to false.
  final bool debug;

  /// Callback function that is invoked when the platform detects a tap on a node
  NodeTapResultHandler? onNodeTap;

  /// Callback triggered when the user starts dragging a placed node.
  NodePanStartHandler? onPanStart;

  /// Callback triggered repeatedly while a placed node is being dragged.
  NodePanChangeHandler? onPanChange;

  /// Callback triggered when the user stops dragging a placed node.
  NodePanEndHandler? onPanEnd;

  /// Callback triggered when the user starts rotating a placed node.
  NodeRotationStartHandler? onRotationStart;

  /// Callback triggered repeatedly while a placed node is being rotated.
  NodeRotationChangeHandler? onRotationChange;

  /// Callback triggered when the user stops rotating a placed node.
  NodeRotationEndHandler? onRotationEnd;

  /// Callback that is triggered when the native platform reports a node-related error
  NodeErrorHandler? onError;
  final Map<String, VoidCallback> _transformListeners = {};

  /// Creates the object manager for the [ARView] platform view identified by
  /// [id]. Consumers normally receive an already-constructed instance
  /// through [ARViewCreatedCallback] rather than calling this directly.
  ARObjectManager(int id, {this.debug = false})
      : _meshChannel = MethodChannel('flutter_reality/mesh_$id') {
    final suffix = id.toString();
    _hostApi = ARObjectHostApi(messageChannelSuffix: suffix);
    ARObjectFlutterApi.setUp(_ObjectEventHandler(this),
        messageChannelSuffix: suffix);
    if (debug) {
      print("ARObjectManager initialized");
    }
  }

  /// Sets up the AR Object Manager
  Future<void> onInitialize() => _hostApi.initialize();

  /// Add given node to the given anchor of the underlying AR scene (or to its top-level if no anchor is given) and listen to any changes made to its transformation
  Future<bool?> addNode(ARNode node, {ARPlaneAnchor? planeAnchor}) async {
    try {
      _removeTransformListener(node);
      void listener() {
        _hostApi.transformationChanged(
          node.name,
          MatrixValueNotifierConverter()
              .toJson(node.transformNotifier)
              .cast<double>(),
        );
      }

      _transformListeners[node.name] = listener;
      node.transformNotifier.addListener(listener);
      if (planeAnchor != null) {
        planeAnchor.childNodes.add(node.name);
        final added = await _hostApi.addNodeToPlaneAnchor(
          _toNodeMessage(node),
          _toAnchorMessage(planeAnchor),
        );
        if (added != true) {
          _removeTransformListener(node);
        }
        return added;
      } else {
        final added = await _hostApi.addNode(_toNodeMessage(node));
        if (added != true) {
          _removeTransformListener(node);
        }
        return added;
      }
    } catch (e) {
      print('Error caught: ' + e.toString());
      _removeTransformListener(node);
      return false;
    }
  }

  /// Adds a renderer-backed deformable triangle mesh to this AR scene.
  ///
  /// Positions are packed XYZ values in object-local metres. Indices are
  /// triangle-list indices. The native Filament node owns the GPU buffers;
  /// callers update only the positions on subsequent frames.
  Future<bool> addDeformableMesh({
    required String id,
    required List<double> positions,
    required List<int> triangleIndices,
    required Matrix4 worldTransform,
    int color = 0xFF0A8F83,
    double metallic = 0.05,
    double roughness = 0.72,
  }) async {
    _validateDeformableMesh(
      id: id,
      positions: positions,
      triangleIndices: triangleIndices,
      worldTransform: worldTransform,
    );
    if (!metallic.isFinite || metallic < 0 || metallic > 1 ||
        !roughness.isFinite || roughness < 0 || roughness > 1) {
      throw ArgumentError('Deformable mesh PBR values must be in [0, 1].');
    }
    final added = await _meshChannel.invokeMethod<bool>('add', {
      'id': id,
      'positions': positions,
      'indices': triangleIndices,
      'transform': worldTransform.storage.toList(growable: false),
      'color': color,
      'metallic': metallic,
      'roughness': roughness,
    });
    return added ?? false;
  }

  /// Uploads a new XPBD surface frame to an existing AR mesh.
  ///
  /// Topology is immutable for the lifetime of a mesh; only vertex positions
  /// and its object transform may change. Keep uploads bounded (normally 10–15
  /// Hz on mobile) rather than sending every solver substep over the channel.
  Future<void> updateDeformableMesh({
    required String id,
    required List<double> positions,
    required Matrix4 worldTransform,
  }) async {
    if (id.trim().isEmpty || positions.isEmpty ||
        positions.length % 3 != 0 || positions.length ~/ 3 > 25000 ||
        positions.any((value) => !value.isFinite) ||
        worldTransform.storage.any((value) => !value.isFinite) ||
        worldTransform.determinant().abs() <= 1e-12) {
      throw ArgumentError('Invalid deformable mesh update frame.');
    }
    await _meshChannel.invokeMethod<void>('update', {
      'id': id,
      'positions': positions,
      'transform': worldTransform.storage.toList(growable: false),
    });
  }

  Future<void> removeDeformableMesh(String id) =>
      _meshChannel.invokeMethod<void>('remove', {'id': id});

  static void _validateDeformableMesh({
    required String id,
    required List<double> positions,
    required List<int> triangleIndices,
    required Matrix4 worldTransform,
  }) {
    if (id.trim().isEmpty ||
        positions.length < 12 ||
        positions.length % 3 != 0 ||
        positions.length ~/ 3 > 25000 ||
        triangleIndices.isEmpty ||
        triangleIndices.length % 3 != 0 ||
        triangleIndices.length > 150000 ||
        positions.any((value) => !value.isFinite) ||
        triangleIndices.any((index) =>
            index < 0 || index >= positions.length ~/ 3) ||
        worldTransform.storage.any((value) => !value.isFinite) ||
        worldTransform.determinant().abs() <= 1e-12) {
      throw ArgumentError('Invalid or over-budget deformable mesh buffers.');
    }
  }

  /// Remove given node from the AR Scene
  Future<void> removeNode(ARNode node) async {
    _removeTransformListener(node);
    await _hostApi.removeNode(node.name);
  }

  void _removeTransformListener(ARNode node) {
    final listener = _transformListeners.remove(node.name);
    if (listener != null) {
      node.transformNotifier.removeListener(listener);
    }
  }

  NodeMessage _toNodeMessage(ARNode node) {
    final map = node.toMap();
    return NodeMessage(
      type: map['type'] as int,
      name: map['name'] as String,
      transformation: (map['transformation'] as List).cast<double>(),
      uri: map['uri'] as String?,
      data: map['data'] as Map<String, dynamic>?,
    );
  }

  AnchorMessage _toAnchorMessage(ARPlaneAnchor anchor) {
    final map = anchor.toJson();
    return AnchorMessage(
      type: map['type'] as int,
      name: map['name'] as String,
      transformation: (map['transformation'] as List).cast<double>(),
      childNodes: (map['childNodes'] as List?)?.cast<String>(),
      cloudAnchorId: map['cloudanchorid'] as String?,
      ttl: map['ttl'] as int?,
    );
  }
}

/// Forwards Pigeon-generated `ARObjectFlutterApi` callbacks to
/// [ARObjectManager]'s public callback fields. Kept as a separate class
/// because the callback field names (`onError`, `onPanEnd`, ...) are
/// intentionally identical to the interface method names, which a class
/// can't both declare as a field and implement as a method.
class _ObjectEventHandler implements ARObjectFlutterApi {
  _ObjectEventHandler(this._manager);

  final ARObjectManager _manager;

  @override
  void onError(String message) {
    if (_manager.debug) {
      print(message);
    }
    _manager.onError?.call(message);
  }

  @override
  void onNodeTap(List<String?> names) {
    _manager.onNodeTap?.call(names.whereType<String>().toList());
  }

  @override
  void onPanStart(String name) => _manager.onPanStart?.call(name);

  @override
  void onPanChange(String name) => _manager.onPanChange?.call(name);

  @override
  void onPanEnd(NodeTransformEventMessage event) {
    _manager.onPanEnd?.call(
      event.name,
      MatrixConverter().fromJson(event.transform),
    );
  }

  @override
  void onRotationStart(String name) => _manager.onRotationStart?.call(name);

  @override
  void onRotationChange(String name) => _manager.onRotationChange?.call(name);

  @override
  void onRotationEnd(NodeTransformEventMessage event) {
    _manager.onRotationEnd?.call(
      event.name,
      MatrixConverter().fromJson(event.transform),
    );
  }
}
