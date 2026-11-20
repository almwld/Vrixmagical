/// Small, deterministic registry for in-flight cloud-anchor uploads.
///
/// The pending entry must be inserted before awaiting the platform request:
/// native completion can arrive before that Future resolves.
class PendingAnchorUploadQueue<T> {
  PendingAnchorUploadQueue(this._items);

  final List<T> _items;

  bool add(T value, {required String Function(T value) nameOf}) {
    final name = nameOf(value);
    if (name.isEmpty || _items.any((item) => nameOf(item) == name)) {
      return false;
    }
    _items.add(value);
    return true;
  }

  T? take(String name, {required String Function(T value) nameOf}) {
    final index = _items.indexWhere((item) => nameOf(item) == name);
    if (index < 0) return null;
    return _items.removeAt(index);
  }

  bool remove(String name, {required String Function(T value) nameOf}) {
    final index = _items.indexWhere((item) => nameOf(item) == name);
    if (index < 0) return false;
    _items.removeAt(index);
    return true;
  }
}
