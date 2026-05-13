class FirestorePaths {
  const FirestorePaths._();

  static String venue(String venueId) => 'venues/$venueId';
  static String recipes(String venueId) => '${venue(venueId)}/recipes';
  static String recipeDrafts(String venueId) => '${venue(venueId)}/recipeDrafts';
  static String ingredients(String venueId) => '${venue(venueId)}/ingredients';
  static String stockConcernSessions(String venueId) =>
      '${venue(venueId)}/stockConcernSessions';
  static String bartenderSales(String venueId) => '${venue(venueId)}/bartenderSales';
  static String quizSessions(String venueId) => '${venue(venueId)}/quizSessions';
  static String quizAttempts(String venueId) => '${venue(venueId)}/quizAttempts';
  static String trendSummaries(String venueId) => '${venue(venueId)}/trendSummaries';
  static String users() => 'users';
}
