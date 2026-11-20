# ⚡ دليل نشر وتهيئة خادم وقاعدة بيانات بَذْرَة (Supabase Backend Setup Guide)

> **دليل هندسي رسمي لتشغيل واستنساخ البنية التحتية الخلفية لمنظومة بَذْرَة المالية (Badra FinTech Platform) على أي مشروع سحابي جديد في Supabase خلال دقائق معدودة وبأعلى معايير الأمان.**

---

## 🏗️ 1. المعمارية الهندسية وقاعدة البيانات (System Architecture)

تعتمد منظومة **بَذْرَة** على معمارية أمنية متقدمة من نوع **(Database-First Security)**:
1. **فصل طبقة البيانات:** الجداول الحساسة معزولة ومحمية بسياسات الأمان الصفية **Row Level Security (RLS)** لمنع أي وصول أو تلاعب مباشر.
2. **العمليات الذرية (ACID Transactions & RPC Functions):** تنفيذ العمليات المالية (التحويلات، السداد، الشحن، التجميد المؤقت) يتم حصراً عبر دوال الخادم المشفرة (`PostgreSQL RPC Functions`) لمنع تضارب العمليات (`Race Conditions`) وضمان عدم خصم أو إضافة أي مبلغ إلا بعد المصادقة الثنائية.
3. **الدوال السحابية (Edge Functions):** تشغيل دوال `Deno / TypeScript` على شبكة الحافة لمعالجة المدفوعات الحساسة والتواصل مع بوابات الدفع والبنوك.

---

## 🚀 2. خيارات التشغيل والنشر (Deployment Options)

اختر الطريقة الأنسب لك من الطريقتين التاليتين:

---

### 🟢 الطريقة الأولى: النشر الآلي بضغطة زر واحدة (الموصى بها للمطورين عبر CLI)

هذه الطريقة تقرأ كافة ملفات التهجير (66 Migration Files) بالترتيب الزمني الصحيح تلقائياً دون أي تدخل يدوي:

#### المتطلبات:
* تثبيت [Supabase CLI](https://supabase.com/docs/guides/cli):
  ```bash
  npm install -g supabase
  # أو عبر Scoop (Windows):
  scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
  scoop install supabase
  ```

#### خطوات النشر:
```bash
# 1. تسجيل الدخول إلى حسابك في Supabase
supabase login

# 2. ربط المجلد بمشروعك السحابي الجديد (احصل على Reference ID من إعدادات مشروعك في لوحة Supabase)
supabase link --project-ref <your-project-id>

# 3. دفع وتطبيق كافة الجداول والـ RPCs والسياسات بالترتيب الزمني الصحيح
supabase db push

# 4. نشر دوال الـ Edge Functions السحابية
supabase functions deploy process-badra-payment
supabase functions deploy request-payment
supabase functions deploy approve-payment-signature
supabase functions deploy send-fcm-notification
```

---

### 🔵 الطريقة الثانية: النسخ واللصق في المتصفح عبر (SQL Editor)

إذا كنت تفضل عدم استخدام الـ CLI، اتبع هذا الترتيب الصارم المكون من 3 خطوات لمنع أي خطأ في التبعيات:

#### 1️⃣ الخطوة الأولى: تفعيل الإضافات والمخطط الخاص (Extensions & Schemas)
افتح **SQL Editor** في لوحة تحكم مشروعك الجديد، والصق الكود التالي واضغط **Run**:
```sql
-- 1. تفعيل الإضافات الأساسية للتشفير والمعرفات الفريدة
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

-- 2. إنشاء المخطط المعزول للحركات المالية الحساسة
CREATE SCHEMA IF NOT EXISTS "badra_core";
ALTER SCHEMA "badra_core" OWNER TO "postgres";
```

#### 2️⃣ الخطوة الثانية: تطبيق البنية التحتية الشاملة (`schema.sql`)
1. افتح الملف المجمع المرفق في هذا المجلد: [`backend/schema.sql`](./schema.sql).
2. انسخ المحتوى بالكامل (الملف مرتب هندسياً ومختبر 100% ليُبنى دفعة واحدة).
3. الصقه في **SQL Editor** واضغط **Run**.
4. **النتيجة:** ستجد كافة الجداول، العلاقات، الفهارس الذكية، وسياسات الأمان الـ RLS، ودوال الـ RPC قد أُنشئت بنجاح بدون أدنى خطأ.

#### 3️⃣ الخطوة الثالثة: ضبط مفاتيح التطبيق
انسخ من إعدادات مشروعك في لوحة Supabase (`Project Settings -> API`):
* `Project URL`
* `anon public key`
وضعهما في ملف `.env` الخاص بكل من تطبيق الزبائن وتطبيق الأدمن.

---

## 🛡️ 3. جداول ودوال الأمان المركزية (Core Security Tables & RPCs)

| العنصر | النوع | الوظيفة الهندسية |
| :--- | :--- | :--- |
| `badra_core.wallets` | جدول مركزي | إدارة أرصدة محافظ العملاء والمشرفين مع أقفال صفية مشروطة |
| `badra_core.transactions` | جدول مركزي | سجل العمليات المالي الدائم غير القابل للتعديل (Audit Ledger) |
| `badra_core.deposit_requests` | جدول عمليات | تتبع إيصالات الشحن اليدوي والتحويلات البنكية للمطابقة |
| `badra_core.discount_codes` | جدول عروض | قسائم التخفيض ونسب الخصم الآمنة مع عدادات الاستخدام |
| `process_badra_payment()` | دالة خادم (RPC) | التحقق من صحة التوقيع الرقمي وتنفيذ النقل الذري للأموال |
| `request_payment()` | دالة خادم (RPC) | إنشاء طلب دفع مع رمز أمان مؤقت ومفتاح عدم تكرار (Idempotency) |
| `redeem_coupon_and_pay()` | دالة خادم (RPC) | تطبيق الخصم وإجراء الدفع في معاملة واحدة غير قابلة للتجزئة |

---

## ✅ 4. التحقق واختبار الجاهزية (Verification Checklist)
- [ ] ظهور كافة الجداول في قسم **Table Editor** في لوحة Supabase.
- [ ] ظهور علامة القفل الخضراء (RLS Enabled) على كافة جداول النظام.
- [ ] تفعيل صلاحيات الـ `SECURITY DEFINER` لدوال الـ RPC لتنفيذ العمليات بأعلى أمان.
- [ ] وصول طلبات التست من تطبيق الـ Flutter بنجاح واستجابة فورية أقل من 100ms.
