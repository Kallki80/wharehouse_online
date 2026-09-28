import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';

/// Result of a single paginated API call.
class AdminPageResult {
  final bool success;
  final List<Map<String, dynamic>> rows;
  final int total;
  final bool hasMore;
  final int page;
  final bool paginated;
  final String? error;

  const AdminPageResult({
    required this.success,
    required this.rows,
    required this.total,
    required this.hasMore,
    required this.page,
    required this.paginated,
    this.error,
  });

  factory AdminPageResult.failure(int page, String error) => AdminPageResult(
        success: false,
        rows: const [],
        total: 0,
        hasMore: false,
        page: page,
        paginated: true,
        error: error,
      );
}

/// Result of a "fetch everything" call used for Excel exports.
class AdminFetchAllResult {
  final List<Map<String, dynamic>> rows;
  final bool truncated;
  final String? error;

  const AdminFetchAllResult({
    required this.rows,
    this.truncated = false,
    this.error,
  });
}

/// Describes one (page of a) data request.
class AdminDataQuery {
  final String endpoint;
  final int page;
  final int limit;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? search;
  final Map<String, String> extraParams;

  const AdminDataQuery({
    required this.endpoint,
    this.page = 1,
    this.limit = 50,
    this.startDate,
    this.endDate,
    this.search,
    this.extraParams = const {},
  });
}

/// Shared paging / export / date-range helpers for the admin section.
class AdminDataPager {
  AdminDataPager._();

  static const List<String> dateKeys = [
    'date',
    'ctrl_date',
    'expected_date',
    'date_of_dispatch',
    'record_date',
    'payment_date',
  ];

  /// `yyyy-MM-dd`, the format every backend date filter expects.
  static String formatApiDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// First parsable date value of a row (null when the table has no date).
  static DateTime? rowDate(Map<String, dynamic> row) {
    for (final key in dateKeys) {
      final value = row[key];
      if (value == null) continue;
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Client side safety net for exports: keeps rows without a date untouched so
  /// tables that have no date column are never wiped out by a date filter.
  static List<Map<String, dynamic>> filterByDateRange(
    List<Map<String, dynamic>> rows,
    DateTime? start,
    DateTime? end,
  ) {
    if (start == null && end == null) return rows;
    final startBound =
        start == null ? null : DateTime(start.year, start.month, start.day);
    final endBound = end == null
        ? null
        : DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return rows.where((row) {
      final date = rowDate(row);
      if (date == null) return true;
      if (startBound != null && date.isBefore(startBound)) return false;
      if (endBound != null && date.isAfter(endBound)) return false;
      return true;
    }).toList();
  }

  static Uri buildUri(AdminDataQuery query) {
    final params = <String, String>{
      'page': query.page.toString(),
      'limit': query.limit.toString(),
    };
    if (query.startDate != null) {
      params['start_date'] = formatApiDate(query.startDate!);
    }
    if (query.endDate != null) {
      params['end_date'] = formatApiDate(query.endDate!);
    }
    if (query.search != null && query.search!.trim().isNotEmpty) {
      params['search'] = query.search!.trim();
    }
    params.addAll(query.extraParams);
    return Uri.parse('$apiBaseUrl${query.endpoint}').replace(queryParameters: params);
  }

  /// Loads one page. Handles both the paginated envelope
  /// (`{data, total, has_more, ...}`) and legacy plain-list responses.
  // static Future<AdminPageResult> fetchPage(
  //   AdminDataQuery query, {
  //   Duration timeout = const Duration(seconds: 25),
  // }) async {
  //   final uri = buildUri(query);
  //   debugPrint('AdminDataPager: GET $uri');
  //   String? lastError;

  //   for (int attempt = 0; attempt <= 1; attempt++) {
  //     try {
  //       final response = await http.get(uri).timeout(timeout);
  //       if (response.statusCode != 200) {
  //         lastError = 'HTTP ${response.statusCode}: ${_preview(response.body)}';
  //       } else {
  //         final decoded = json.decode(response.body);
  //         return parseResponse(decoded, query.page);
  //       }
  //     } catch (e) {
  //       lastError = e.toString();
  //       if (attempt == 0) {
  //         await Future.delayed(const Duration(seconds: 2));
  //       }
  //     }
  //   }
  //   debugPrint('AdminDataPager: request failed -> $lastError');
  //   return AdminPageResult.failure(query.page, lastError ?? 'Unknown error');
  // }



  static Future<AdminPageResult> fetchPage(
    AdminDataQuery query, {
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final uri = buildUri(query);
    debugPrint('AdminDataPager: GET $uri');
    String? lastError;

    for (int attempt = 0; attempt <= 1; attempt++) {
      try {
        final response = await http.get(uri).timeout(timeout);

        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode}: ${_preview(response.body)}';
        } else {
          final decoded = json.decode(response.body);

          final parsed = parseResponse(
            decoded,
            query.page,
            query.limit,
          );

          // Extra safety:
          // If backend gives total records, use total + current page size
          // to determine whether another page exists.
          if (parsed.success && parsed.paginated) {
            final calculatedHasMore =
                parsed.total > (query.page * query.limit);

            return AdminPageResult(
              success: true,
              rows: parsed.rows,
              total: parsed.total,
              hasMore: calculatedHasMore || parsed.hasMore,
              page: parsed.page,
              paginated: parsed.paginated,
              error: parsed.error,
            );
          }

          return parsed;
        }
      } catch (e) {
        lastError = e.toString();

        if (attempt == 0) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    debugPrint('AdminDataPager: request failed -> $lastError');

    return AdminPageResult.failure(
      query.page,
      lastError ?? 'Unknown error',
    );
  }






  /// Parses a decoded API body into a page result.
  // @visibleForTesting
  // static AdminPageResult parseResponse(dynamic decoded, int requestedPage) {
  //   if (decoded is Map && decoded['data'] is List) {
  //     final rows = toRows(decoded['data'] as List);
  //     final hasMore = decoded['has_more'] == true;
  //     return AdminPageResult(
  //       success: true,
  //       rows: rows,
  //       total: (decoded['total'] as num?)?.toInt() ?? rows.length,
  //       hasMore: hasMore,
  //       page: (decoded['page'] as num?)?.toInt() ?? requestedPage,
  //       paginated: decoded.containsKey('has_more'),
  //     );
  //   }
  //   if (decoded is List) {
  //     final rows = toRows(decoded);
  //     return AdminPageResult(
  //       success: true,
  //       rows: rows,
  //       total: rows.length,
  //       hasMore: false,
  //       page: requestedPage,
  //       paginated: false,
  //     );
  //   }
  //   return AdminPageResult.failure(requestedPage, 'Unexpected response format');
  // }


  @visibleForTesting
  static AdminPageResult parseResponse(
    dynamic decoded,
    int requestedPage, [
    int requestedLimit = 50,
  ]) {
    if (decoded is Map && decoded['data'] is List) {
      final rows = toRows(decoded['data'] as List);

      final total =
          (decoded['total'] as num?)?.toInt() ?? rows.length;

      // Backend's value, if present.
      final backendHasMore = decoded['has_more'] == true;

      // Calculate ourselves using total + page + limit.
      //
      // Example:
      // page 1, limit 30, total 500
      // 500 > 30 => more pages
      //
      // page 17, limit 30, total 500
      // 500 > 510 => no more pages
      final calculatedHasMore =
          total > (requestedPage * requestedLimit);

      final hasMore = backendHasMore || calculatedHasMore;

      debugPrint(
        'AdminDataPager: page=$requestedPage '
        'rows=${rows.length} '
        'total=$total '
        'backendHasMore=$backendHasMore '
        'calculatedHasMore=$calculatedHasMore '
        'hasMore=$hasMore',
      );

      return AdminPageResult(
        success: true,
        rows: rows,
        total: total,
        hasMore: hasMore,
        page: (decoded['page'] as num?)?.toInt() ?? requestedPage,
        paginated: decoded.containsKey('has_more') || decoded.containsKey('total'),
      );
    }

    if (decoded is List) {
      final rows = toRows(decoded);

      return AdminPageResult(
        success: true,
        rows: rows,
        total: rows.length,
        hasMore: false,
        page: requestedPage,
        paginated: false,
      );
    }

    return AdminPageResult.failure(
      requestedPage,
      'Unexpected response format',
    );
  }

  /// Fetches every matching row by walking the endpoint page by page.
  /// Used by the Excel exports so they always contain the full data set.
  static Future<AdminFetchAllResult> fetchAll({
    required String endpoint,
    int pageSize = 1000,
    DateTime? startDate,
    DateTime? endDate,
    String? search,
    Map<String, String> extraParams = const {},
    int maxRows = 200000,
  }) async {
    final rows = <Map<String, dynamic>>[];
    int page = 1;
    bool truncated = false;

    while (true) {
      final result = await fetchPage(AdminDataQuery(
        endpoint: endpoint,
        page: page,
        limit: pageSize,
        startDate: startDate,
        endDate: endDate,
        search: search,
        extraParams: extraParams,
      ));

      if (!result.success) {
        return AdminFetchAllResult(rows: rows, truncated: truncated, error: result.error);
      }

      rows.addAll(result.rows);

      if (rows.length >= maxRows) {
        truncated = rows.length > maxRows;
        if (truncated) rows.removeRange(maxRows, rows.length);
        break;
      }
      // Plain list responses (or the last page) mean we are done.
      if (!result.paginated || !result.hasMore || result.rows.isEmpty) break;
      page++;
    }

    return AdminFetchAllResult(rows: rows, truncated: truncated);
  }

  /// Counts the rows of [table] inside the date range (server side).
  static Future<int?> countByDateRange({
    required String table,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final uri = Uri.parse('$apiBaseUrl/count_by_date_range').replace(queryParameters: {
        'table_name': table,
        'start_date': formatApiDate(start),
        'end_date': formatApiDate(end),
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final decoded = json.decode(response.body);
      return (decoded is Map) ? (decoded['count'] as num?)?.toInt() ?? 0 : null;
    } catch (e) {
      debugPrint('AdminDataPager: countByDateRange failed: $e');
      return null;
    }
  }

  /// Deletes every row of [table] inside the date range. Returns deleted count.
  static Future<int?> deleteByDateRange({
    required String table,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/delete_by_date_range'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'table_name': table,
              'start_date': formatApiDate(start),
              'end_date': formatApiDate(end),
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return null;
      final decoded = json.decode(response.body);
      return (decoded is Map) ? (decoded['deleted'] as num?)?.toInt() ?? 0 : null;
    } catch (e) {
      debugPrint('AdminDataPager: deleteByDateRange failed: $e');
      return null;
    }
  }

  static List<Map<String, dynamic>> toRows(List<dynamic> dataList) {
    return dataList.map((item) {
      if (item is Map) return Map<String, dynamic>.from(item);
      if (item is String) return <String, dynamic>{'id': item, 'name': item};
      return <String, dynamic>{};
    }).toList();
  }

  static String _preview(String body) =>
      body.length > 200 ? body.substring(0, 200) : body;
}

/// Sliding window over server pages kept in memory for a virtualized table.
///
/// The window holds the contiguous page range `[firstPage..lastPage]`. Once
/// more than [maxPages] pages are loaded, the oldest page is evicted from the
/// front (dynamic page loader: scrolling down frees the top page). When a
/// previous page is prepended and the window becomes too tall again, the
/// newest page is evicted from the back instead.
///
/// All mutations operate directly on the caller's row list so the caller can
/// keep passing the same list to a `ListView`/`AdminVirtualTable`.
class AdminPageWindow {
  AdminPageWindow({this.maxPages = 3});

  /// Maximum number of pages kept in memory at once.
  final int maxPages;

  /// Row count of every loaded page; index 0 belongs to [firstPage].
  final List<int> _pageSizes = [];

  /// First / last page currently materialized in the caller's row list.
  /// [lastPage] is 0 while the window is empty.
  int firstPage = 1;
  int lastPage = 0;

  int get pageCount => _pageSizes.length;

  /// True while there is an unloadable page above [firstPage].
  bool get canLoadPrevious => firstPage > 1;

  /// Page to request when refilling the top of the window.
  int get prevFirstPage => firstPage - 1;

  /// Drops all bookkeeping (the caller clears its row list separately).
  void resetAll() {
    _pageSizes.clear();
    firstPage = 1;
    lastPage = 0;
  }

  /// Replaces the window with a single fresh page.
  void reset({required int page, required int rowCount}) {
    resetAll();
    recordAppend(page: page, rowCount: rowCount);
  }

  void recordAppend({required int page, required int rowCount}) {
    _pageSizes.add(rowCount);
    lastPage = page;
  }

  void recordPrepend({required int page, required int rowCount}) {
    _pageSizes.insert(0, rowCount);
    firstPage = page;
  }

  /// Evicts the oldest pages from [rows] until at most [maxPages] pages
  /// remain. Returns how many rows were removed from the front (for scroll
  /// compensation via [compensateTopChange]).
  int evictFront(List<Map<String, dynamic>> rows) {
    int removed = 0;
    while (_pageSizes.length > maxPages) {
      final n = _pageSizes.removeAt(0);
      firstPage++;
      if (n > 0 && n <= rows.length) {
        rows.removeRange(0, n);
        removed += n;
      }
    }
    return removed;
  }

  /// Evicts the newest pages from [rows] until at most [maxPages] pages
  /// remain (always keeps the first page). Returns the number of pages
  /// evicted — the caller should re-enable "has more" then, because those
  /// rows exist again on the server after the window's new last page.
  int evictBack(List<Map<String, dynamic>> rows) {
    int evicted = 0;
    while (_pageSizes.length > maxPages && _pageSizes.length > 1) {
      final n = _pageSizes.removeLast();
      lastPage--;
      if (n > 0 && n <= rows.length) {
        rows.removeRange(rows.length - n, rows.length);
      }
      evicted++;
    }
    return evicted;
  }

  /// Keeps the viewport anchored when [deltaRows] rows (positive = inserted,
  /// negative = removed) changed at the TOP of a fixed-[rowHeight] list.
  /// Must be called in the same frame as the row mutation so the rebuild and
  /// the scroll jump are applied together (no visible jump).
  static void compensateTopChange(
      ScrollController controller, int deltaRows, double rowHeight) {
    if (deltaRows == 0 || !controller.hasClients) return;
    final target = controller.position.pixels + deltaRows * rowHeight;
    controller.jumpTo(target < 0 ? 0 : target);
  }
}

