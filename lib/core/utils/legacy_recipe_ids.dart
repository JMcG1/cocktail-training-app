const String legacyCloverClubId = 'clover-club';
const String raspberryMartiniId = 'raspberry-martini';

const Map<String, String> _legacyCocktailIdAliases = {
  legacyCloverClubId: raspberryMartiniId,
};

String normalizeCocktailId(String id) {
  final trimmed = id.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }
  return _legacyCocktailIdAliases[trimmed] ?? trimmed;
}

Iterable<String> cocktailIdCandidates(String id) sync* {
  final normalized = normalizeCocktailId(id);
  if (normalized.isEmpty) {
    return;
  }
  yield normalized;
  for (final entry in _legacyCocktailIdAliases.entries) {
    if (entry.value == normalized) {
      yield entry.key;
    }
  }
}
