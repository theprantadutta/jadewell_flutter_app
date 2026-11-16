import 'api_client.dart';
import 'api_result.dart';

// ---------------------------------------------------------------------------
// Models (snake_case JSON). Parsing is lenient about optional fields and
// strict about the ones the UI can't do without; a malformed body becomes
// ApiFailure.badResponse, never an exception.
// ---------------------------------------------------------------------------

/// One row of a leaderboard. On the weekly board [stars] and [timeMs] are
/// totals across the week's verified dailies.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    required this.stars,
    required this.timeMs,
    this.isMe = false,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        rank: (j['rank'] as num).toInt(),
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String,
        avatarColor: j['avatar_color'] as String?,
        stars: (j['stars'] as num).toInt(),
        timeMs: (j['time_ms'] as num).toInt(),
        isMe: j['is_me'] as bool? ?? false,
      );

  final int rank;
  final String userId;
  final String displayName;

  /// `#RRGGBB`, or null (the UI derives a pastel from the name).
  final String? avatarColor;
  final int stars;
  final int timeMs;
  final bool isMe;
}

/// The caller's own standing (present once they have a ranked result).
class LeaderboardMe {
  const LeaderboardMe({required this.entry, this.topPercent});

  factory LeaderboardMe.fromJson(Map<String, dynamic> j) => LeaderboardMe(
        entry: LeaderboardEntry.fromJson({...j, 'is_me': true}),
        topPercent: (j['top_percent'] as num?)?.toInt(),
      );

  final LeaderboardEntry entry;

  /// "Top N%": 1…100, rounded up by the server. Null when too few players.
  final int? topPercent;
}

class LeaderboardPage {
  const LeaderboardPage({required this.entries, this.me, this.totalPlayers = 0, this.layoutId});

  factory LeaderboardPage.fromJson(Map<String, dynamic> j) => LeaderboardPage(
        entries: [
          for (final e in (j['entries'] as List<dynamic>? ?? const []))
            LeaderboardEntry.fromJson(e as Map<String, dynamic>),
        ],
        me: j['me'] == null ? null : LeaderboardMe.fromJson(j['me'] as Map<String, dynamic>),
        totalPlayers: (j['total_players'] as num?)?.toInt() ?? 0,
        layoutId: j['layout_id'] as String?,
      );

  /// Ranked by the server (stars desc, then time asc); shown as is.
  final List<LeaderboardEntry> entries;
  final LeaderboardMe? me;
  final int totalPlayers;

  /// The daily's layout (daily and friends boards).
  final String? layoutId;

  bool get isEmpty => entries.isEmpty;
}

/// A public player summary (friends, requests, lookup).
class PlayerSummary {
  const PlayerSummary({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarColor,
    this.friendCode,
  });

  factory PlayerSummary.fromJson(Map<String, dynamic> j) => PlayerSummary(
        userId: j['user_id'] as String,
        displayName: j['display_name'] as String,
        username: j['username'] as String?,
        avatarColor: j['avatar_color'] as String?,
        friendCode: j['friend_code'] as String?,
      );

  final String userId;
  final String displayName;
  final String? username;
  final String? avatarColor;
  final String? friendCode;
}

class Friend {
  const Friend({required this.player, this.since});

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(
        player: PlayerSummary.fromJson(j),
        since: DateTime.tryParse(j['since'] as String? ?? ''),
      );

  final PlayerSummary player;
  final DateTime? since;

  String get userId => player.userId;
}

enum FriendRequestStatus { pending, accepted, declined }

class FriendRequest {
  const FriendRequest({required this.id, required this.player, this.status = FriendRequestStatus.pending, this.createdAt});

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
        id: j['id'] as String,
        player: PlayerSummary.fromJson(j['user'] as Map<String, dynamic>),
        status: FriendRequestStatus.values.asNameMap()[j['status'] as String? ?? 'pending'] ??
            FriendRequestStatus.pending,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
      );

  final String id;

  /// The other person (the sender for incoming, the recipient for outgoing).
  final PlayerSummary player;
  final FriendRequestStatus status;
  final DateTime? createdAt;
}

class FriendRequests {
  const FriendRequests({this.incoming = const [], this.outgoing = const []});

  factory FriendRequests.fromJson(Map<String, dynamic> j) => FriendRequests(
        incoming: [
          for (final r in (j['incoming'] as List<dynamic>? ?? const []))
            FriendRequest.fromJson(r as Map<String, dynamic>),
        ],
        outgoing: [
          for (final r in (j['outgoing'] as List<dynamic>? ?? const []))
            FriendRequest.fromJson(r as Map<String, dynamic>),
        ],
      );

  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;
}

// ---------------------------------------------------------------------------
// Friend codes
// ---------------------------------------------------------------------------

/// `JW-XXXXXX` codes: 6 Crockford base32 characters (digits and uppercase
/// letters without I, L, O, U). Mirrors the backend's FriendCodeGenerator.
abstract final class FriendCodes {
  static const prefix = 'JW-';
  static const bodyLength = 6;
  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static final _canonical = RegExp(r'^JW-[0-9A-HJKMNP-TV-Z]{6}$');

  static bool isValid(String? code) => code != null && _canonical.hasMatch(code);

  /// Canonical code for what a player typed or pasted, or null if it can't
  /// be one. Accepts lowercase, spaces, a missing prefix or hyphen, an
  /// invite link, and the Crockford look-alikes (O→0, I/L→1).
  static String? normalize(String? input) {
    if (input == null) return null;
    var s = input.trim();
    final link = RegExp(r'/f/([^/?#\s]+)').firstMatch(s);
    if (link != null) s = link.group(1)!;
    var compact = s.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    if (compact.startsWith('JW') && compact.length == bodyLength + 2) compact = compact.substring(2);
    if (compact.length != bodyLength) return null;
    final body = compact.replaceAll('O', '0').replaceAll('I', '1').replaceAll('L', '1');
    for (final c in body.split('')) {
      if (!alphabet.contains(c)) return null;
    }
    return '$prefix$body';
  }

  /// Display form while typing: uppercase, look-alikes mapped, characters
  /// outside the alphabet dropped, `JW-` added once there's a body.
  static String formatPartial(String input) {
    var compact = input.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    // The player may be typing the prefix themselves.
    if (compact == 'J') return 'J';
    if (compact == 'JW') return prefix;
    if (compact.startsWith('JW')) compact = compact.substring(2);
    final buf = StringBuffer();
    for (final c in compact.split('')) {
      final mapped = switch (c) { 'O' => '0', 'I' || 'L' => '1', _ => c };
      if (alphabet.contains(mapped) && buf.length < bodyLength) buf.write(mapped);
    }
    return buf.isEmpty ? '' : '$prefix$buf';
  }

  static String inviteLink(String code) => 'https://jadewell.pranta.dev/f/$code';
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

/// UTC `YYYY-MM-DD` for [utc]'s calendar day.
String utcDateKey(DateTime utc) {
  final d = utc.toUtc();
  return '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
}

/// ISO-8601 week of [utc]'s UTC calendar day, as `YYYY-Www` (e.g. 2026-W47).
String isoWeekKey(DateTime utc) {
  final u = utc.toUtc();
  final d = DateTime.utc(u.year, u.month, u.day);
  // Thursday of this week decides the year.
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final jan1 = DateTime.utc(thursday.year);
  final week = (thursday.difference(jan1).inDays ~/ 7) + 1;
  return '${thursday.year}-W${_two(week)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------

/// Leaderboard and friends endpoints (backend ARCHITECTURE §4). Every call
/// returns an [ApiResult]; a 404 while the backend lacks an endpoint is just
/// another failure the UI shows as "not available yet".
class SocialApi {
  SocialApi(this._client);

  final ApiClient _client;

  Future<ApiResult<LeaderboardPage>> dailyLeaderboard(String date, {int limit = 50}) async =>
      _parse(await _client.get('/leaderboards/daily/$date?limit=$limit'), LeaderboardPage.fromJson);

  Future<ApiResult<LeaderboardPage>> weeklyLeaderboard(String isoWeek, {int limit = 50}) async =>
      _parse(await _client.get('/leaderboards/weekly/$isoWeek?limit=$limit'), LeaderboardPage.fromJson);

  Future<ApiResult<LeaderboardPage>> friendsLeaderboard(String date) async =>
      _parse(await _client.get('/leaderboards/friends/$date'), LeaderboardPage.fromJson);

  Future<ApiResult<List<Friend>>> friends() async => _parse(
        await _client.get('/friends'),
        (j) => [for (final f in (j['friends'] as List<dynamic>)) Friend.fromJson(f as Map<String, dynamic>)],
      );

  Future<ApiResult<FriendRequests>> requests() async =>
      _parse(await _client.get('/friends/requests'), FriendRequests.fromJson);

  /// Sends a request. If they had already asked you, the server accepts both
  /// ways and returns status `accepted`.
  Future<ApiResult<FriendRequest>> sendRequest(String friendCode) async => _parse(
        await _client.post('/friends/requests', body: {'friend_code': friendCode}),
        FriendRequest.fromJson,
      );

  Future<ApiResult<Friend>> accept(String requestId) async =>
      _parse(await _client.post('/friends/requests/$requestId/accept'), Friend.fromJson);

  Future<ApiResult<void>> decline(String requestId) async =>
      _ignore(await _client.post('/friends/requests/$requestId/decline'));

  /// Withdraws one of your outgoing requests.
  Future<ApiResult<void>> cancel(String requestId) async =>
      _ignore(await _client.delete('/friends/requests/$requestId'));

  Future<ApiResult<void>> remove(String userId) async => _ignore(await _client.delete('/friends/$userId'));

  Future<ApiResult<PlayerSummary>> lookup(String friendCode) async =>
      _parse(await _client.get('/friends/lookup/$friendCode'), PlayerSummary.fromJson);

  static ApiResult<T> _parse<T>(ApiResult<Map<String, dynamic>> r, T Function(Map<String, dynamic>) f) {
    if (!r.isSuccess) return ApiResult.failed(r.failure!, statusCode: r.statusCode, message: r.message);
    try {
      return ApiResult.success(f(r.value!), statusCode: r.statusCode);
    } on Object {
      return ApiResult.failed(ApiFailure.badResponse, statusCode: r.statusCode);
    }
  }

  static ApiResult<void> _ignore(ApiResult<Map<String, dynamic>> r) => r.isSuccess
      ? ApiResult<void>.success(null, statusCode: r.statusCode)
      : ApiResult.failed(r.failure!, statusCode: r.statusCode, message: r.message);
}
