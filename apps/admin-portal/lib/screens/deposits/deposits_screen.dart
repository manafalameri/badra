import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'widgets/manual_deposit_card.dart';
import 'widgets/deposit_history_list.dart';

class DepositsScreen extends StatefulWidget {
  const DepositsScreen({super.key});

  @override
  State<DepositsScreen> createState() => _DepositsScreenState();
}

class _DepositsScreenState extends State<DepositsScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  static const int _pageSize = 20;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _records = [];
        _offset = 0;
        _hasMore = true;
        _isLoading = true;
      });
    }

    try {
      final newRecords = await SupabaseService.getDepositRecords(
        limit: _pageSize,
        offset: _offset,
      );
      
      if (!mounted) return;
      
      setState(() {
        if (refresh) {
          _records = newRecords;
        } else {
          _records.addAll(newRecords);
        }
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = newRecords.length >= _pageSize;
        if (_hasMore) _offset += _pageSize;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => _loadRecords(refresh: true),
        color: AppColors.primary,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 120,
              pinned: true,
              backgroundColor: AppColors.primary,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: SafeArea(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF1a237e),
                          Color(0xFF1565C0),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'الإيداعات',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_records.length} إيداع',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  ManualDepositCard(
                    existingRecords: _records,
                    onSuccess: () => _loadRecords(refresh: true),
                  ),
                  const SizedBox(height: 24),
                  const SectionTitle(title: 'سجل الإيداعات'),
                  const SizedBox(height: 12),
                  if (_isLoading && _records.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    )
                  else
                    DepositHistoryList(
                      records: _records,
                      onLoadMore: _loadMore,
                      isLoadingMore: _isLoadingMore,
                      hasMore: _hasMore,
                    ),
                  const SizedBox(height: 24),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}