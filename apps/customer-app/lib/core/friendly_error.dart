/// تنظيف وتنقية الأخطاء — يحوّل أي خطأ تقني (Supabase / شبكة / نظام)
/// إلى جملة عربية بسيطة ومفهومة، دون أي رموز أو مصطلحات إنجليزية.
String friendlyError(Object? raw) {
  String text = raw?.toString() ?? '';

  // إزالة بادئة Exception
  if (text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length);
  }

  // استخراج رسالة PostgrestException(message: ...)
  final postgrest = RegExp(r'PostgrestException\(message:\s*([^,\)]+)')
      .firstMatch(text);
  if (postgrest != null) {
    text = postgrest.group(1)!.trim();
  }

  // استخراج رسالة AuthException(message: ...)
  final auth = RegExp(r'AuthException\(message:\s*([^,\)]+)')
      .firstMatch(text);
  if (auth != null) {
    text = auth.group(1)!.trim();
  }

  final lower = text.toLowerCase();

  // 1) كثرة المحاولات / الحظر المؤقت (Rate Limit / 429)
  if (text.contains('429') ||
      lower.contains('rate limit') ||
      lower.contains('too many request') ||
      lower.contains('retry exceeded') ||
      lower.contains('exceeded the limit')) {
    return 'تم إيقاف المحاولات مؤقتاً لكثرة الطلبات، يرجى الانتظار بضع دقائق والمحاولة مجدداً.';
  }

  // 2) بيانات الدخول غير صحيحة (Invalid Login / 400 / 401)
  if (lower.contains('invalid login credentials') ||
      lower.contains('invalid api key') ||
      lower.contains('invalid username') ||
      lower.contains('invalid password') ||
      lower.contains('invalid email') ||
      lower.contains('password recovery') ||
      lower.contains('email not confirmed') ||
      lower.contains('phone not confirmed') ||
      lower.contains('user not found') ||
      ((text.contains('400') || text.contains('401')) &&
          (lower.contains('credential') ||
              lower.contains('login') ||
              lower.contains('password') ||
              lower.contains('sign in') ||
              lower.contains('authentication')))) {
    return 'رقم الهاتف أو كلمة المرور غير صحيحة.';
  }

  // 3) الشبكة / انقطاع الإنترنت (SocketException / Timeout / Offline)
  if (lower.contains('socketexception') ||
      lower.contains('network exception') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('connection closed') ||
      lower.contains('connection timed out') ||
      lower.contains('timed out') ||
      lower.contains('timeout') ||
      lower.contains('network is unreachable') ||
      lower.contains('host unreachable') ||
      lower.contains('failed to connect') ||
      lower.contains('offline') ||
      lower.contains('no internet') ||
      lower.contains('clientexception with socketexception')) {
    return 'تعذر الاتصال بالشبكة، تأكد من اتصالك بالإنترنت.';
  }

  // 4) انتهاء الجلسة / عدم التوثيق (JWT Expired / Unauthorized)
  if (lower.contains('jwt') ||
      lower.contains('expired token') ||
      lower.contains('token expired') ||
      lower.contains('invalid access token') ||
      lower.contains('invalid refresh token') ||
      lower.contains('auth session missing') ||
      lower.contains('session missing') ||
      lower.contains('session expired') ||
      lower.contains('user not authenticated') ||
      lower.contains('not authenticated') ||
      lower.contains('sign in required') ||
      lower.contains('session has expired')) {
    return 'انتهت الجلسة، يرجى تسجيل الدخول مجدداً.';
  }

  // 5) الصلاحيات (RLS / Permission Denied / 403)
  if (text.contains('403') ||
      lower.contains('permission denied') ||
      lower.contains('row-level security') ||
      lower.contains('row level security') ||
      lower.contains('policy violation') ||
      lower.contains('access denied') ||
      lower.contains('forbidden')) {
    return 'عفواً، لا تملك الصلاحية لإتمام هذا الإجراء.';
  }

  // 6) خطأ في الخادم (Internal Server Error / 500+)
  if (text.contains('500') ||
      text.contains('502') ||
      text.contains('503') ||
      text.contains('504') ||
      lower.contains('internal server error') ||
      lower.contains('server error') ||
      lower.contains('something went wrong') ||
      lower.contains('unexpected response')) {
    return 'حدث خطأ في الخادم، يرجى المحاولة لاحقاً.';
  }

  // 7) الحساب مسجل مسبقاً
  if (lower.contains('already registered') ||
      lower.contains('already exists') ||
      lower.contains('user exists')) {
    return 'هذا الحساب مسجل مسبقاً، يمكنك تسجيل الدخول مباشرة.';
  }

  // النص المتبقي عربي → يعرض كما هو
  if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) {
    return text.trim();
  }

  // 8) أي خطأ غامض أو غير معرف (عرض رسالة السيرفر الفعلية)
  if (text.isNotEmpty) {
    return text.trim();
  }
  return 'حدث خطأ غير متوقع، يرجى المحاولة مرة أخرى.';
}
