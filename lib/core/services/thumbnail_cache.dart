import 'dart:async';
import 'dart:typed_data';

/// Small previews only: never retains the full decrypted originals.
class ThumbnailCache {
  static const maxBytes = 24 * 1024 * 1024;
  final Map<String, Uint8List> _cache = {};
  final Map<String, _ThumbnailJob> _jobs = {};
  final List<_ThumbnailJob> _pending = [];
  int _bytes = 0;
  int _active = 0;
  int _generation = 0;

  Uint8List? peek(String key) {
    final bytes = _cache.remove(key);
    if (bytes != null) _cache[key] = bytes;
    return bytes;
  }

  Future<Uint8List?> load(String key, Future<Uint8List?> Function() produce,
      {bool Function()? isNeeded}) {
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Future.value(cached);
    }
    final existing = _jobs[key];
    if (existing != null) {
      existing.consumers.add(isNeeded ?? () => true);
      return existing.result.future;
    }
    final job = _ThumbnailJob(key, produce, _generation);
    job.consumers.add(isNeeded ?? () => true);
    _jobs[key] = job;
    _pending.add(job);
    _drain();
    return job.result.future;
  }

  void clear() {
    _generation++;
    _cache.clear();
    _bytes = 0;
    for (final job in _pending) {
      job.result.complete(null);
    }
    _pending.clear();
    _jobs.clear();
  }

  void _drain() {
    while (_active < 2 && _pending.isNotEmpty) {
      // Recently requested cells belong to the user's current scroll position.
      final job = _pending.removeLast();
      if (!job.consumers.any((needed) => needed())) {
        _jobs.remove(job.key);
        job.result.complete(null);
        continue;
      }
      _active++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_ThumbnailJob job) async {
    Uint8List? bytes;
    try {
      bytes = await job.produce();
      if (job.generation != _generation) {
        bytes = null;
      } else if (bytes != null && bytes.lengthInBytes <= maxBytes) {
        while (_cache.isNotEmpty &&
            (_bytes + bytes.lengthInBytes > maxBytes || _cache.length >= 180)) {
          _bytes -= _cache.remove(_cache.keys.first)!.lengthInBytes;
        }
        _cache[job.key] = bytes;
        _bytes += bytes.lengthInBytes;
      }
    } catch (_) {
      bytes = null;
    } finally {
      if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
      job.result.complete(bytes);
      _active--;
      _drain();
    }
  }
}

class _ThumbnailJob {
  _ThumbnailJob(this.key, this.produce, this.generation);
  final String key;
  final Future<Uint8List?> Function() produce;
  final int generation;
  final result = Completer<Uint8List?>();
  final consumers = <bool Function()>[];
}
