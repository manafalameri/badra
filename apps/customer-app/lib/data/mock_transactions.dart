import '../core/string_utils.dart';

enum TransactionType { incoming, outgoing, service }

enum TxStatus { completed, pending, failed }

class TransactionModel {
  final String id;
  final String ref;
  final String shortRef;
  final String title;
  final double amount;
  final DateTime date;
  final TransactionType type;
  final TxStatus status;
  final String debtor;
  final String creditor;
  final String notes;
  final double? originalAmount;
  final double? discountAmount;

  TransactionModel({
    required this.id,
    required this.ref,
    this.shortRef = '',
    required this.title,
    required this.amount,
    required this.date,
    required this.type,
    required this.status,
    required this.debtor,
    required this.creditor,
    required this.notes,
    this.originalAmount,
    this.discountAmount,
  });

  static String computeShortRef(String ref, String id) {
    final target = ref.isNotEmpty ? ref : id;
    final digits = target.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 4) return digits.substring(digits.length - 4);
    if (target.length >= 4) return target.substring(target.length - 4);
    return target;
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    final rawId = (map['id'] ?? '').toString();
    final rawRef = (map['ref'] ?? '').toString();
    final rawShortRef = (map['short_ref'] ?? '').toString();
    final shortRef = rawShortRef.isNotEmpty
        ? rawShortRef
        : computeShortRef(rawRef, rawId);

    return TransactionModel(
      id: rawId.toLatinDigits(),
      ref: rawRef.toLatinDigits(),
      shortRef: shortRef.toLatinDigits(),
      title: (map['title'] as String).toLatinDigits(),
      amount: (map['amount'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      type: _typeFromString(map['type'] as String),
      status: _statusFromString(map['status'] as String),
      debtor: (map['debtor'] as String).toLatinDigits(),
      creditor: (map['creditor'] as String).toLatinDigits(),
      notes: (map['notes'] as String).toLatinDigits(),
      originalAmount: map['original_amount'] != null ? (map['original_amount'] as num).toDouble() : null,
      discountAmount: map['discount_amount'] != null ? (map['discount_amount'] as num).toDouble() : null,
    );
  }

  /// Flexible constructor to handle RPC/raw maps with different keys
  factory TransactionModel.fromFlexibleMap(Map<String, dynamic> map) {
    String id = (map['id'] ?? map['ref'] ?? '').toString();
    String ref = (map['ref'] ?? '').toString();
    String title = (map['title'] ?? map['store'] ?? map['ref'] ?? '')
        .toString();
    // amount can be num or string
    double amountVal = 0.0;
    try {
      final a = map['amount'];
      if (a is num) {
        amountVal = a.toDouble();
      } else if (a is String) {
        amountVal = double.tryParse(a.replaceAll(',', '')) ?? 0.0;
      }
    } catch (_) {}

    DateTime dateVal = DateTime.now();
    try {
      final d = map['date'] ?? map['created_at'];
      if (d is String) dateVal = DateTime.parse(d);
    } catch (_) {}

    String typeStr = (map['type'] ?? '')?.toString() ?? '';
    final isIn = map['is_in'];
    TransactionType typeVal;
    if (isIn != null) {
      try {
        typeVal = (isIn == 1 || isIn == true)
            ? TransactionType.incoming
            : TransactionType.outgoing;
      } catch (_) {
        typeVal = TransactionType.outgoing;
      }
    } else {
      typeVal = _typeFromString(typeStr);
    }

    String statusStr = (map['status'] ?? '')?.toString() ?? '';
    final statusVal = statusStr.isNotEmpty
        ? _statusFromString(statusStr)
        : TxStatus.completed;

    String debtor = (map['debtor'] ?? '')?.toString() ?? '';
    String creditor = (map['creditor'] ?? '')?.toString() ?? '';
    String notes = (map['notes'] ?? '')?.toString() ?? '';
    double? originalAmount;
    if (map['original_amount'] != null) {
      originalAmount = (map['original_amount'] as num).toDouble();
    }
    double? discountAmount;
    if (map['discount_amount'] != null) {
      discountAmount = (map['discount_amount'] as num).toDouble();
    }

    final rawShortRef = (map['short_ref'] ?? '').toString();
    final shortRef = rawShortRef.isNotEmpty
        ? rawShortRef
        : computeShortRef(ref, id);

    return TransactionModel(
      id: id.toLatinDigits(),
      ref: ref.toLatinDigits(),
      shortRef: shortRef.toLatinDigits(),
      title: title.toLatinDigits(),
      amount: amountVal,
      date: dateVal,
      type: typeVal,
      status: statusVal,
      debtor: debtor.toLatinDigits(),
      creditor: creditor.toLatinDigits(),
      notes: notes.toLatinDigits(),
      originalAmount: originalAmount,
      discountAmount: discountAmount,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'ref': ref,
    'short_ref': shortRef,
    'title': title,
    'amount': amount,
    'date': date.toIso8601String(),
    'type': type.name,
    'status': status.name,
    'debtor': debtor,
    'creditor': creditor,
    'notes': notes,
  };

  static TransactionType _typeFromString(String v) {
    switch (v) {
      case 'incoming':
        return TransactionType.incoming;
      case 'outgoing':
        return TransactionType.outgoing;
      case 'service':
        return TransactionType.service;
      default:
        return TransactionType.outgoing;
    }
  }

  static TxStatus _statusFromString(String v) {
    switch (v) {
      case 'completed':
        return TxStatus.completed;
      case 'pending':
        return TxStatus.pending;
      case 'failed':
        return TxStatus.failed;
      default:
        return TxStatus.completed;
    }
  }

  String get formattedAmount {
    final val = amount.toStringAsFixed(0);
    return _addCommas(val);
  }

  String get formattedDate {
    final months = [
      'يناير',
      'فبراير',
      'مارس',
      'إبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  String get fullDateTime {
    final months = [
      'يناير',
      'فبراير',
      'مارس',
      'إبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    final hour = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year} — $hour:$min';
  }

  static String _addCommas(String s) {
    final result = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) result.write(',');
      result.write(s[i]);
    }
    return result.toString();
  }
}

// â”€â”€ Mock Data â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class MockTransactions {
  static final List<Map<String, dynamic>> _maps = [
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ ظ،',
      'title': 'ط´ط­ظ† ط±طµظٹط¯ ط¹ط¨ط± ظ‚ظ†ط§ط© ط§ظ„ط´ط­ظ†',
      'amount': 85000,
      'date': '2026-05-03T09:14:00',
      'type': 'incoming',
      'status': 'completed',
      'debtor': 'ط£ط­ظ…ط¯ ظ…ط­ظ…ط¯ ط§ظ„ط´ط±ط¬ط¨ظٹ',
      'creditor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'notes': 'طھط³ظˆظٹط© ط­ط³ط§ط¨ ط´ظ‡ط± ط£ط¨ط±ظٹظ„',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ ظ¢',
      'title': 'ظپط§طھظˆط±ط© ط§ظ„ظƒظ‡ط±ط¨ط§ط،',
      'amount': 12400,
      'date': '2026-05-02T14:30:00',
      'type': 'outgoing',
      'status': 'completed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ط´ط±ظƒط© ظƒظ‡ط±ط¨ط§ط، ط§ظ„ظٹظ…ظ†',
      'notes': 'ظپط§طھظˆط±ط© ط¥ط¨ط±ظٹظ„ ظ¢ظ ظ¢ظ¦',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ ظ£',
      'title': 'ط±ط§طھط¨ ط´ظ‡ط± ط£ط¨ط±ظٹظ„',
      'amount': 320000,
      'date': '2026-05-01T08:00:00',
      'type': 'incoming',
      'status': 'completed',
      'debtor': 'ط´ط±ظƒط© ط§ظ„ط±ظٹط§ط¯ط© ظ„ظ„طھط¬ط§ط±ط©',
      'creditor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'notes': 'ط±ط§طھط¨ ط´ظ‡ط± ط£ط¨ط±ظٹظ„ ظ¢ظ ظ¢ظ¦',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ ظ¤',
      'title': 'ط¯ظپط¹ ط·ظ„ط¨ ظ…طھط¬ط± ط§ظ„ط£ظ†ط§ظ‚ط©',
      'amount': 45000,
      'date': '2026-04-30T16:45:00',
      'type': 'outgoing',
      'status': 'completed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ظ†ط§ط¯ظٹط© ط¹ظ„ظٹ ط§ظ„ظ‚ط­ط·ط§ظ†ظٹ',
      'notes': 'ط­طµط© ظ…ط´ط±ظˆط¹ ط§ظ„طھطµظ…ظٹظ…',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ ظ¥',
      'title': 'ط±ط³ظˆظ… ط®ط¯ظ…ط© ط¨ط°ط±ط©',
      'amount': 2500,
      'date': '2026-04-30T00:01:00',
      'type': 'service',
      'status': 'completed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ط¨ط°ط±ط© ظ„ظ„ط®ط¯ظ…ط§طھ ط§ظ„ظ…ط§ظ„ظٹط©',
      'notes': 'ط±ط³ظˆظ… ط§ظ„ط§ط´طھط±ط§ظƒ ط§ظ„ط´ظ‡ط±ظٹ â€” VIP',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ ظ¦',
      'title': 'ط´ط­ظ† ط±طµظٹط¯ ط¹ط¨ط± ظ‚ظ†ط§ط© ط§ظ„ط´ط­ظ†',
      'amount': 60000,
      'date': '2026-04-28T11:20:00',
      'type': 'incoming',
      'status': 'completed',
      'debtor': 'ط³ظ„ظ…ظ‰ ط¹ظ…ط± ط§ظ„ط¨ظƒط±ظٹ',
      'creditor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'notes': 'ط¯ظپط¹ط© ط£ظˆظ„ظ‰ ظ…ظ‚ط§ط¨ظ„ ط§ظ„ط§ط³طھط´ط§ط±ط©',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ ظ§',
      'title': 'ط´ط±ط§ط، ط¥ظ„ظƒطھط±ظˆظ†ظٹط§طھ',
      'amount': 38500,
      'date': '2026-04-27T15:00:00',
      'type': 'outgoing',
      'status': 'failed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ظ…طھط¬ط± ط§ظ„طھظ‚ظ†ظٹط© ط§ظ„ط°ظƒظٹط©',
      'notes': 'ظپط´ظ„ ط¨ط³ط¨ط¨ ط¹ط¯ظ… ظƒظپط§ظٹط© ط§ظ„ط±طµظٹط¯',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ ظ¨',
      'title': 'ط¯ظپط¹ ط·ظ„ط¨ ظ…طھط¬ط± ط£ظˆظ†ظ„ط§ظٹظ†',
      'amount': 150000,
      'date': '2026-04-26T09:30:00',
      'type': 'outgoing',
      'status': 'pending',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ط¹ط¨ط¯ط§ظ„ظ„ظ‡ ط§ظ„ط؛ط§ظ…ط¯ظٹ â€” ط§ظ„ط±ظٹط§ط¶',
      'notes': 'ط¯ظپط¹ ظ‚ظٹط¯ ط§ظ„ظ…ط±ط§ط¬ط¹ط©',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ ظ©',
      'title': 'ط§ط³طھط±ط¯ط§ط¯ ظ…ط¨ظ„ط؛',
      'amount': 18000,
      'date': '2026-04-25T13:10:00',
      'type': 'incoming',
      'status': 'completed',
      'debtor': 'ظ…طھط¬ط± ط§ظ„ط£ظ†ط§ظ‚ط© ط§ظ„ط­ط¯ظٹط«ط©',
      'creditor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'notes': 'ط§ط³طھط±ط¯ط§ط¯ ط·ظ„ط¨ ظ…ظ„ط؛ظٹ ط±ظ‚ظ… #ظ¤ظ¤ظ¢ظ،',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ ',
      'title': 'ظپط§طھظˆط±ط© ط§ظ„ط¥ظ†طھط±ظ†طھ',
      'amount': 8900,
      'date': '2026-04-24T10:00:00',
      'type': 'outgoing',
      'status': 'completed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ط´ط±ظƒط© ظٹظ…ظ† ظ†طھ',
      'notes': 'ط¨ط§ظ‚ط© ط§ظ„ط£ظ„ظٹط§ظپ ط§ظ„ط¶ظˆط¦ظٹط© â€” ط£ط¨ط±ظٹظ„',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ،',
      'title': 'ط´ط­ظ† ط±طµظٹط¯ ط¹ط¨ط± ظ‚ظ†ط§ط© ط§ظ„ط´ط­ظ†',
      'amount': 95000,
      'date': '2026-04-23T17:45:00',
      'type': 'incoming',
      'status': 'completed',
      'debtor': 'ظپظٹطµظ„ ظ†ط§طµط± ط§ظ„ظ…ظ‚ط±ظ…ظٹ',
      'creditor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'notes': 'ط³ط¯ط§ط¯ ط¯ظٹظ† ط³ط§ط¨ظ‚',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ¢',
      'title': 'ط¯ظپط¹ ط·ظ„ط¨ ظ…طھط¬ط± ط§ظ„ط£ظ†ط§ظ‚ط©',
      'amount': 27000,
      'date': '2026-04-22T12:00:00',
      'type': 'outgoing',
      'status': 'completed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ط±ظٹظ… ظ…ط­ظ…ط¯ ط§ظ„ط­ط¯ط§ط¯',
      'notes': 'ط¯ظپط¹ط© ظ…ظ‚ط§ط¨ظ„ ط®ط¯ظ…ط§طھ طھطµظ…ظٹظ… ط§ظ„ط¬ط±ط§ظپظٹظƒ',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ£',
      'title': 'طھط±ظ‚ظٹط© ط­ط³ط§ط¨ VIP',
      'amount': 15000,
      'date': '2026-04-21T08:30:00',
      'type': 'service',
      'status': 'completed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ط¨ط°ط±ط© ظ„ظ„ط®ط¯ظ…ط§طھ ط§ظ„ظ…ط§ظ„ظٹط©',
      'notes': 'طھط±ظ‚ظٹط© ط¥ظ„ظ‰ ط¹ط¶ظˆظٹط© VIP ظ„ظ…ط¯ط© ظ¦ ط£ط´ظ‡ط±',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ¤',
      'title': 'ط´ط­ظ† ط±طµظٹط¯ ظ…ظ† ط´ط±ظƒط© ط§ظ„ط±ظٹط§ط¯ط©',
      'amount': 75000,
      'date': '2026-04-20T14:00:00',
      'type': 'incoming',
      'status': 'completed',
      'debtor': 'ط´ط±ظƒط© ط§ظ„ط±ظٹط§ط¯ط© ظ„ظ„طھط¬ط§ط±ط©',
      'creditor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'notes': 'ط¹ظ…ظˆظ„ط© ظ…ط¨ظٹط¹ط§طھ ط§ظ„ط±ط¨ط¹ ط§ظ„ط£ظˆظ„',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ¥',
      'title': 'ط¯ظپط¹ ط¥ظٹط¬ط§ط± ط§ظ„ظ…ظƒطھط¨',
      'amount': 120000,
      'date': '2026-04-19T09:00:00',
      'type': 'outgoing',
      'status': 'completed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ظ…ظƒطھط¨ ط§ظ„ط¹ظ‚ط§ط±ط§طھ ط§ظ„ط°ظ‡ط¨ظٹط©',
      'notes': 'ط¥ظٹط¬ط§ط± ط´ظ‡ط± ظ…ط§ظٹظˆ ظ¢ظ ظ¢ظ¦',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ¦',
      'title': 'ط¯ظپط¹ ط·ظ„ط¨ ط¹ط§ط¬ظ„',
      'amount': 50000,
      'date': '2026-04-18T22:15:00',
      'type': 'outgoing',
      'status': 'failed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ط¹ظ…ط± ط³ط¹ظٹط¯ ط§ظ„ظ…ط·ط±ظٹ',
      'notes': 'ظپط´ظ„ ط§ظ„ط¯ظپط¹ â€” ط§ظ„ط­ط³ط§ط¨ ط؛ظٹط± ظ†ط´ط·',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ§',
      'title': 'ط´ط­ظ† ط±طµظٹط¯ ط¹ط¨ط± ظ‚ظ†ط§ط© ط§ظ„ط´ط­ظ†',
      'amount': 200000,
      'date': '2026-04-17T10:30:00',
      'type': 'incoming',
      'status': 'completed',
      'debtor': 'ظ‚ظ†ط§ط© ط§ظ„ط´ط­ظ† ط§ظ„ظ…ط¹طھظ…ط¯ط©',
      'creditor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'notes': 'ط´ط­ظ† ظˆط§ط±ط¯ ظ…ظ† ظ‚ظ†ط§ط© ظ…ط¹طھظ…ط¯ط©',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ¨',
      'title': 'ط§ط´طھط±ط§ظƒ ظ…ظ†طµط© ط±ظ‚ظ…ظٹط©',
      'amount': 6500,
      'date': '2026-04-16T00:00:00',
      'type': 'service',
      'status': 'completed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ظ…ظ†طµط© ط§ظ„ط£ط¹ظ…ط§ظ„ ط§ظ„ط±ظ‚ظ…ظٹط©',
      'notes': 'ط§ط´طھط±ط§ظƒ ط³ظ†ظˆظٹ â€” ط¨ط§ظ‚ط© ط§ظ„ط£ط¹ظ…ط§ظ„',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ،ظ©',
      'title': 'ط¯ظپط¹ ط·ظ„ط¨ ظ…طھط¬ط± ط§ظ„طھظ‚ظ†ظٹط©',
      'amount': 33000,
      'date': '2026-04-15T16:00:00',
      'type': 'outgoing',
      'status': 'completed',
      'debtor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'creditor': 'ط®ط§ظ„ط¯ ط¹ط¨ط¯ط§ظ„ظ„ظ‡ ط§ظ„ط²ط¨ظٹط¯ظٹ',
      'notes': 'ظ…ط³طھط­ظ‚ط§طھ ظ…ط´ط±ظˆط¹ ط§ظ„طھط·ظˆظٹط±',
    },
    {
      'id': 'TXN-ظ¢ظ ظ¢ظ¦-ظ ظ¢ظ ',
      'title': 'ظ…ظƒط§ظپط£ط© ط£ط¯ط§ط،',
      'amount': 110000,
      'date': '2026-04-14T08:00:00',
      'type': 'incoming',
      'status': 'completed',
      'debtor': 'ط´ط±ظƒط© ط§ظ„ط±ظٹط§ط¯ط© ظ„ظ„طھط¬ط§ط±ط©',
      'creditor': 'ظ…ط­ظ…ط¯ ط³ط§ظ„ظ… ط§ظ„ط¹ظ…ط±ظٹ',
      'notes': 'ظ…ظƒط§ظپط£ط© ط£ط¯ط§ط، ط§ظ„ط±ط¨ط¹ ط§ظ„ط£ظˆظ„ ظ¢ظ ظ¢ظ¦',
    },
  ];

  static late List<TransactionModel> _cached;
  static bool _initialized = false;

  static List<TransactionModel> get all {
    if (!_initialized) {
      _cached = _maps.map(TransactionModel.fromMap).toList();
      _initialized = true;
    }
    return _cached;
  }
}
