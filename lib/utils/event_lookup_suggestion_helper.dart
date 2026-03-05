import '../repositories/event_repository.dart';

typedef NameSuggestionFetcher = Future<List<String>> Function(String prefix);
typedef RecordSuggestionFetcher =
    Future<List<NameRecordPair>> Function(String prefix, {String? namePrefix});

/// Shared suggestion behavior for event-name / record-number lookups.
///
/// Strategy:
/// - Fetch by first typed character (or empty prefix for focused record field).
/// - Cache fetched suggestion sets.
/// - Filter in-memory for current query.
class EventLookupSuggestionHelper {
  List<String> _cachedNameSuggestions = const [];
  String? _nameFetchPrefix;

  List<NameRecordPair> _cachedRecordSuggestions = const [];
  String? _recordFetchPrefix;
  String? _recordNameConstraint;

  static String normalize(String value) => value.trim().toLowerCase();

  void resetNameCache() {
    _cachedNameSuggestions = const [];
    _nameFetchPrefix = null;
  }

  void resetRecordCache() {
    _cachedRecordSuggestions = const [];
    _recordFetchPrefix = null;
    _recordNameConstraint = null;
  }

  List<String> _filterNameSuggestions(List<String> suggestions, String query) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    return suggestions
        .where((name) => normalize(name).startsWith(normalizedQuery))
        .toList();
  }

  List<NameRecordPair> _filterRecordSuggestions(
    List<NameRecordPair> suggestions,
    String query, {
    String? nameConstraint,
  }) {
    final normalizedQuery = normalize(query);
    final normalizedNameConstraint = nameConstraint == null
        ? null
        : normalize(nameConstraint);

    return suggestions.where((pair) {
      if (normalizedQuery.isNotEmpty &&
          !normalize(pair.recordNumber).startsWith(normalizedQuery)) {
        return false;
      }
      if (normalizedNameConstraint != null &&
          normalizedNameConstraint.isNotEmpty) {
        return normalize(pair.name).startsWith(normalizedNameConstraint);
      }
      return true;
    }).toList();
  }

  Future<List<String>> getNameSuggestions({
    required String query,
    required NameSuggestionFetcher fetcher,
  }) async {
    final normalized = normalize(query);
    if (normalized.isEmpty) {
      resetNameCache();
      return const [];
    }

    final fetchPrefix = normalized[0];
    final shouldFetch =
        _nameFetchPrefix != fetchPrefix || _cachedNameSuggestions.isEmpty;
    if (shouldFetch) {
      _cachedNameSuggestions = await fetcher(fetchPrefix);
      _nameFetchPrefix = fetchPrefix;
    }

    return _filterNameSuggestions(_cachedNameSuggestions, normalized);
  }

  Future<List<NameRecordPair>> getRecordSuggestions({
    required String query,
    String? nameConstraint,
    required RecordSuggestionFetcher fetcher,
  }) async {
    final normalized = normalize(query);
    final normalizedNameConstraint = nameConstraint == null
        ? null
        : normalize(nameConstraint);

    if (normalized.isEmpty &&
        (normalizedNameConstraint == null ||
            normalizedNameConstraint.isEmpty)) {
      resetRecordCache();
      return const [];
    }

    final fetchPrefix = normalized.isEmpty ? '' : normalized[0];
    final shouldFetch =
        _cachedRecordSuggestions.isEmpty ||
        (_recordNameConstraint ?? '') != (normalizedNameConstraint ?? '') ||
        (_recordFetchPrefix != null &&
            _recordFetchPrefix!.isNotEmpty &&
            _recordFetchPrefix != fetchPrefix);
    if (shouldFetch) {
      _cachedRecordSuggestions = await fetcher(
        fetchPrefix,
        namePrefix: normalizedNameConstraint,
      );
      _recordFetchPrefix = fetchPrefix;
      _recordNameConstraint = normalizedNameConstraint;
    }

    return _filterRecordSuggestions(
      _cachedRecordSuggestions,
      normalized,
      nameConstraint: normalizedNameConstraint,
    );
  }

  Future<List<NameRecordPair>> getRecordSuggestionsOnFocus({
    String? nameConstraint,
    required RecordSuggestionFetcher fetcher,
  }) async {
    final normalizedNameConstraint = nameConstraint == null
        ? null
        : normalize(nameConstraint);
    if (normalizedNameConstraint == null || normalizedNameConstraint.isEmpty) {
      return const [];
    }

    final shouldFetch =
        _cachedRecordSuggestions.isEmpty ||
        (_recordNameConstraint ?? '') != normalizedNameConstraint;
    if (shouldFetch) {
      _cachedRecordSuggestions = await fetcher(
        '',
        namePrefix: normalizedNameConstraint,
      );
      _recordFetchPrefix = '';
      _recordNameConstraint = normalizedNameConstraint;
    }

    return _filterRecordSuggestions(
      _cachedRecordSuggestions,
      '',
      nameConstraint: normalizedNameConstraint,
    );
  }
}
