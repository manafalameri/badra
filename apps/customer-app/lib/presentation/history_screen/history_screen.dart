import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import './widgets/history_list_widget.dart';
import '../../core/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/badra_luxury_toast.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _activeFilter = 'all';
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasLoadedAll = false;
  final int _limit = 10;
  int _offset = 0;
  DateTime? _rangeFrom;
  DateTime? _rangeTo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _rangeFrom = null;
      _rangeTo = null;
      _offset = 0;
      _hasLoadedAll = false;
    });

    try {
      final data = await SupabaseService.getMyTransactionsFast();
      setState(() {
        _transactions = data;
        _offset = data.length;
        _hasLoadedAll = data.length < _limit;
        _isLoading = false;
      });
    } catch (e) {
      final message = e.toString();
      if (mounted) {
        BadraLuxuryToast.show(
          context,
          'حدث خطأ عند تحميل البيانات: $message',
          type: BadraToastType.error,
          duration: const Duration(seconds: 4),
        );
      }
      setState(() {
        _error = message;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreTransactions() async {
    if (_isLoadingMore || _hasLoadedAll) return;
    setState(() {
      _isLoadingMore = true;
      _error = null;
    });

    try {
      final result = await SupabaseService.getMyTransactionsPaginated(
        limit: _limit,
        offset: _offset,
      );

      final count = result['total_count'] as int;
      final page = (result['transactions'] as List)
          .cast<Map<String, dynamic>>();

      setState(() {
        _transactions.addAll(page);
        _offset += page.length;
        _hasLoadedAll = _offset >= count || page.length < _limit;
        _isLoadingMore = false;
      });
    } catch (e) {
      final message = e.toString();
      if (mounted) {
        BadraLuxuryToast.show(
          context,
          'حدث خطأ عند تحميل المزيد: $message',
          type: BadraToastType.error,
          duration: const Duration(seconds: 4),
        );
      }
      setState(() {
        _error = message;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _fetchTransactionsByDateRange(DateTime from, DateTime to) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _rangeFrom = from;
      _rangeTo = to;
      _offset = 0;
      _hasLoadedAll = false;
    });

    try {
      final data = await SupabaseService.getMyTransactionsByDateRange(
        from: from,
        to: to,
      );

      setState(() {
        _transactions = data;
        _offset = data.length;
        _hasLoadedAll = true;
        _isLoading = false;
      });
    } catch (e) {
      final message = e.toString();
      if (mounted) {
        BadraLuxuryToast.show(
          context,
          'حدث خطأ عند البحث بالتاريخ: $message',
          type: BadraToastType.error,
          duration: const Duration(seconds: 4),
        );
      }
      setState(() {
        _error = message;
        _isLoading = false;
      });
    }
  }

  Future<void> _showDateRangeDialog() async {
    final now = DateTime.now();
    DateTime from = _rangeFrom ?? now.subtract(const Duration(days: 30));
    DateTime to = _rangeTo ?? now;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('جميع المعاملات'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('اختر الفترة الزمنية:'),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: from,
                        firstDate: DateTime(now.year - 3),
                        lastDate: now,
                      );
                      if (selected != null) {
                        setState(() => from = selected);
                      }
                    },
                    child: Text('من: ${_formatDateLabel(from)}'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: to,
                        firstDate: DateTime(now.year - 3),
                        lastDate: now.add(const Duration(days: 1)),
                      );
                      if (selected != null) {
                        setState(() => to = selected);
                      }
                    },
                    child: Text('إلى: ${_formatDateLabel(to)}'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (to.isBefore(from)) {
                      BadraLuxuryToast.show(
                        context,
                        'يجب أن يكون تاريخ النهاية بعد تاريخ البداية.',
                        type: BadraToastType.warning,
                      );
                      return;
                    }
                    Navigator.of(context).pop();
                    _fetchTransactionsByDateRange(from, to);
                  },
                  child: const Text('عرض'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDateLabel(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> get _filtered {
    switch (_activeFilter) {
      case 'incoming':
        return _transactions.where((t) => t['is_in'] == 1).toList();
      case 'outgoing':
        return _transactions.where((t) => t['is_in'] == 0).toList();
      default:
        return _transactions;
    }
  }

  Map<String, int> get _counts => {
    'all': _transactions.length,
    'incoming': _transactions.where((t) => t['is_in'] == 1).length,
    'outgoing': _transactions.where((t) => t['is_in'] == 0).length,
  };

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundDeep,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              _buildFilterBar(),
              if (_rangeFrom != null && _rangeTo != null)
                _buildDateRangeNotice(),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadTransactions,
                  color: AppTheme.emeraldPrimary,
                  backgroundColor: AppTheme.surfaceDark,
                  displacement: 40,
                  child: _isLoading
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          children: const [
                            SizedBox(height: 200),
                            Center(child: CircularProgressIndicator()),
                          ],
                        )
                      : _error != null
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          children: [
                            const SizedBox(height: 200),
                            Center(child: Text('خطأ: $_error')),
                          ],
                        )
                      : HistoryListWidget(transactions: _filtered),
                ),
              ),
              _buildLoadMoreControl(),
              _buildAllTransactionsButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سجل المعاملات',
                  style: GoogleFonts.sora(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 4),
                Text(
                  'جميع عملياتك المالية',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard.withAlpha(153),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.emeraldMuted.withAlpha(77),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = [
      {'key': 'all', 'label': 'الكل'},
      {'key': 'incoming', 'label': 'شحن'},
      {'key': 'outgoing', 'label': 'دفع'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        textDirection: TextDirection.rtl,
        children: filters.map((f) {
          final isActive = _activeFilter == f['key'];
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => setState(() => _activeFilter = f['key']!),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.emeraldPrimary
                        : AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isActive)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(
                        f['label']!,
                        textDirection: TextDirection.rtl,
                        style: GoogleFonts.sora(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isActive
                              ? Colors.white
                              : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_counts[f['key']] ?? 0}',
                        textDirection: TextDirection.rtl,
                        style: GoogleFonts.sora(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isActive ? Colors.white70 : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLoadMoreControl() {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_rangeFrom != null && _rangeTo != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(
          'عرض نتائج الفترة المحددة فقط',
          textDirection: TextDirection.rtl,
          style: GoogleFonts.sora(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }

    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final showMoreButton = !_hasLoadedAll && _transactions.isNotEmpty;
    if (!showMoreButton) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard.withAlpha(180),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.textMuted.withAlpha(90)),
          ),
          child: Text(
            'لا يوجد معاملات أكثر',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F9D58), Color(0xFF00C853)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color.fromRGBO(0, 0, 0, 0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _loadMoreTransactions,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                textDirection: TextDirection.rtl,
                children: [
                  Text(
                    'المزيد من المعاملات',
                    textDirection: TextDirection.rtl,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.expand_more_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateRangeNotice() {
    if (_rangeFrom == null || _rangeTo == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Expanded(
            child: Text(
              'المعاملات من ${_formatDateLabel(_rangeFrom!)} إلى ${_formatDateLabel(_rangeTo!)}',
              textDirection: TextDirection.rtl,
              style: GoogleFonts.sora(fontSize: 12, color: AppTheme.textMuted),
            ),
          ),
          if (_transactions.isNotEmpty)
            Text(
              'الموجودة: ${_transactions.length}',
              textDirection: TextDirection.rtl,
              style: GoogleFonts.sora(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllTransactionsButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppTheme.backgroundMid,
        border: Border(
          top: BorderSide(
            color: AppTheme.emeraldPrimary.withAlpha(30),
            width: 1,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _showDateRangeDialog,
          icon: const Icon(Icons.date_range, size: 18),
          label: Text(
            'جميع المعاملات',
            textDirection: TextDirection.rtl,
            style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.emeraldPrimary,
            foregroundColor: AppTheme.backgroundDeep,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  // Note: Date parsing/format helpers removed — transaction card uses raw date string now.
}
