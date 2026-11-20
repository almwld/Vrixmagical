import 'package:flutter_reality/models/ar_anchor.dart';
import 'package:flutter_reality/src/generated/messages.g.dart';
import 'pending_anchor_upload_queue.dart';

// Type definitions to enforce a consistent use of the API
/// Signature for [ARAnchorManager.onAnchorUploaded]: receives the anchor
/// that was successfully uploaded to the Google Cloud Anchor API.
typedef AnchorUploadedHandler = void Function(ARAnchor arAnchor);

/// Signature for [ARAnchorManager.onAnchorDownloaded]: receives the
/// serialized anchor downloaded from the Google Cloud Anchor API and must
/// return the [ARAnchor] to add to the scene.
typedef AnchorDownloadedHandler = ARAnchor Function(
    Map<String, dynamic> serializedAnchor);

/// Signature for [ARAnchorManager.onError]: receives a human-readable
/// description of a native anchor-related error.
typedef AnchorErrorHandler = void Function(String error);

/// Handles all anchor-related functionality of an [ARView], including configuration and usage of collaborative sessions
class ARAnchorManager {
  late ARAnchorHostApi _hostApi;

  /// Debugging status flag. If true, all platform calls are printed. Defaults to false.
  final bool debug;

  /// Reference to all anchors that are being uploaded to the google cloud anchor API
  List<ARAnchor> pendingAnchors = [];
  late final PendingAnchorUploadQueue<ARAnchor> _pendingUploads =
      PendingAnchorUploadQueue<ARAnchor>(pendingAnchors);

  /// Callback that is triggered once an anchor has successfully been uploaded to the google cloud anchor API
  AnchorUploadedHandler? onAnchorUploaded;

  /// Callback that is triggered once an anchor has successfully been downloaded from the google cloud anchor API and resolved within the current scene
  AnchorDownloadedHandler? onAnchorDownloaded;

  /// Callback that is triggered when the native platform reports an anchor-related error
  AnchorErrorHandler? onError;

  /// Creates the anchor manager for the [ARView] platform view identified by
  /// [id]. Consumers normally receive an already-constructed instance
  /// through [ARViewCreatedCallback] rather than calling this directly.
  ARAnchorManager(int id, {this.debug = false}) {
    final suffix = id.toString();
    _hostApi = ARAnchorHostApi(messageChannelSuffix: suffix);
    ARAnchorFlutterApi.setUp(
      _AnchorEventHandler(this),
      messageChannelSuffix: suffix,
    );
    if (debug) {
      print("ARAnchorManager initialized");
    }
  }

  /// Activates collaborative AR mode (using Google Cloud Anchors)
  Future<void> initGoogleCloudAnchorMode() async {
    await _hostApi.initGoogleCloudAnchorMode();
  }

  /// Add given anchor to the underlying AR scene
  Future<bool?> addAnchor(ARAnchor anchor) async {
    try {
      return await _hostApi.addAnchor(_toAnchorMessage(anchor));
    } catch (e) {
      onError?.call('Unable to add AR anchor: $e');
      return false;
    }
  }

  /// Remove given anchor and all its children from the AR Scene
  Future<void> removeAnchor(ARAnchor anchor) async {
    _pendingUploads.remove(
      anchor.name,
      nameOf: (pending) => pending.name,
    );
    await _hostApi.removeAnchor(anchor.name);
  }

  /// Upload given anchor from the underlying AR scene to the Google Cloud Anchor API
  Future<bool?> uploadAnchor(ARAnchor anchor) async {
    // Register before awaiting the host call: its completion callback can race
    // ahead of the returned Future on a fast native upload.
    if (!_pendingUploads.add(
      anchor,
      nameOf: (pending) => pending.name,
    )) {
      onError?.call('An upload is already pending for anchor ${anchor.name}.');
      return false;
    }
    try {
      final response = await _hostApi.uploadAnchor(anchor.name);
      if (response != true) {
        _pendingUploads.remove(
          anchor.name,
          nameOf: (pending) => pending.name,
        );
      }
      return response;
    } catch (e) {
      _pendingUploads.remove(
        anchor.name,
        nameOf: (pending) => pending.name,
      );
      onError?.call('Unable to upload AR anchor: $e');
      return false;
    }
  }

  /// Try to download anchor with the given ID from the Google Cloud Anchor API and add it to the scene.
  Future<bool?> downloadAnchor(String cloudanchorid) async {
    try {
      return await _hostApi.downloadAnchor(cloudanchorid);
    } catch (e) {
      onError?.call('Unable to download cloud anchor: $e');
      return false;
    }
  }

  AnchorMessage _toAnchorMessage(ARAnchor anchor) {
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

/// Forwards Pigeon-generated `ARAnchorFlutterApi` callbacks to
/// [ARAnchorManager]'s public callback fields. Kept as a separate class
/// because the callback field names (`onError`, ...) are intentionally
/// identical to the interface method names, which a class can't both
/// declare as a field and implement as a method.
class _AnchorEventHandler implements ARAnchorFlutterApi {
  _AnchorEventHandler(this._manager);

  final ARAnchorManager _manager;

  @override
  void onError(String message) {
    if (_manager.debug) print(message);
    _manager.onError?.call(message);
  }

  @override
  void onCloudAnchorUploaded(CloudAnchorUploadedMessage event) {
    final currentAnchor = _manager._pendingUploads.take(
      event.name,
      nameOf: (element) => element.name,
    );
    // A late callback after removal, cancellation or a duplicate delivery is
    // harmless; never crash the AR session with List.first on an empty queue.
    if (currentAnchor == null) {
      if (_manager.debug) {
        print('Ignoring stale cloud-anchor completion for ${event.name}.');
      }
      return;
    }
    if (currentAnchor is! ARPlaneAnchor) {
      _manager.onError?.call(
        'Cloud-anchor upload completed for a non-plane anchor: ${event.name}.',
      );
      return;
    }
    currentAnchor.cloudanchorid = event.cloudAnchorId;
    try {
      _manager.onAnchorUploaded?.call(currentAnchor);
    } catch (error) {
      _manager.onError?.call('Cloud-anchor upload callback failed: $error');
    }
  }

  @override
  String onAnchorDownloadSuccess(AnchorMessage anchor) {
    final serializedAnchor = <String, dynamic>{
      'type': anchor.type,
      'name': anchor.name,
      'transformation': anchor.transformation,
      'childNodes': anchor.childNodes,
      'cloudanchorid': anchor.cloudAnchorId,
      'ttl': anchor.ttl,
    };
    final callback = _manager.onAnchorDownloaded;
    if (callback == null) return anchor.name;
    try {
      return callback(serializedAnchor).name;
    } catch (error) {
      _manager.onError?.call('Cloud-anchor download callback failed: $error');
      return anchor.name;
    }
  }
}
