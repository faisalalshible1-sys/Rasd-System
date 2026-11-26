// قراءة نص مقايسة PDF للاستيراد (Supabase Edge Function: boq-extract) — الإصدار 1.5.0.
//
// • تعيد نصوص كل صفحة بمواضعها {s, x, y, w, h} (x يسار القطعة، y من أعلى الصفحة)، ويكوّن التطبيق منها الصفوف
//   والأعمدة ويعرضها للمراجعة والتصحيح قبل الحفظ (lib/boq_import.dart). لا تحفظ شيئاً ولا تكتب في قاعدة البيانات.
// • الهوية: بوابة الخدمة («Verify JWT with legacy secret») يرضيها مفتاح الربط العام في Authorization، ورمز جلسة
//   المستخدم يصل في x-user-token فتتحقق منه الدالة، ثم من صلاحيته في إعداد المقايسات بالدالة doc_can_edit.
// • الحدود: 10 ميجابايت للملف، و80 صفحة.
// النشر: supabase functions deploy boq-extract (أو من لوحة Supabase ← Edge Functions بالاسم نفسه).
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { getDocumentProxy } from "npm:unpdf@0.12.1";

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-user-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_BYTES = 10 * 1024 * 1024;
const MAX_PAGES = 80;

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

const round = (v: number) => Math.round(v * 10) / 10;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { error: "الطلب غير مسموح" });

  const token = req.headers.get("x-user-token") ?? "";
  if (!token) return reply(401, { error: "سجّل الدخول أولاً" });
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const sb = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: who, error: authError } = await sb.auth.getUser(token);
  if (authError || !who?.user) return reply(401, { error: "انتهت الجلسة؛ سجّل الدخول من جديد" });
  const { data: allowed, error: permError } = await sb.rpc("doc_can_edit", { p_kind: "boq", p_project: null });
  if (permError || allowed !== true) {
    return reply(403, { error: "استيراد المقايسات لمن يعدّ المقايسات (مكتب المدير ومكتب العقود ورئيسا الشؤون الفنية والمطابقة والاستلام)" });
  }

  let bytes: Uint8Array;
  try {
    const body = await req.json();
    const b64 = typeof body?.pdf === "string" ? body.pdf : "";
    if (!b64) return reply(400, { error: "لم يصل ملف PDF" });
    if (b64.length > Math.ceil(MAX_BYTES / 3) * 4 + 8) return reply(413, { error: "الملف أكبر من 10 ميجابايت" });
    const bin = atob(b64);
    bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  } catch {
    return reply(400, { error: "بيانات الملف غير صالحة" });
  }
  // ‎%PDF في أول الملف
  if (bytes.length < 5 || bytes[0] !== 0x25 || bytes[1] !== 0x50 || bytes[2] !== 0x44 || bytes[3] !== 0x46) {
    return reply(400, { error: "الملف ليس PDF" });
  }

  try {
    const pdf = await getDocumentProxy(bytes);
    const n = Math.min(pdf.numPages, MAX_PAGES);
    const pages: { w: number; h: number; items: { s: string; x: number; y: number; w: number; h: number }[] }[] = [];
    for (let p = 1; p <= n; p++) {
      const page = await pdf.getPage(p);
      const vp = page.getViewport({ scale: 1 });
      const content = await page.getTextContent();
      const items = [];
      for (const it of content.items as { str?: string; transform?: number[]; width?: number; height?: number }[]) {
        const s = (it.str ?? "").normalize("NFKC").replace(/\s+/g, " ");
        if (!s.trim() || !it.transform) continue;
        const h = it.height || Math.abs(it.transform[3]) || 10;
        items.push({
          s,
          x: round(it.transform[4]),
          // y من أعلى الصفحة إلى أعلى السطر تقريباً
          y: round(vp.height - it.transform[5] - h),
          w: round(it.width ?? 0),
          h: round(h),
        });
      }
      pages.push({ w: round(vp.width), h: round(vp.height), items });
      page.cleanup();
    }
    return reply(200, { pages, total: pdf.numPages, truncated: pdf.numPages > n });
  } catch (_e) {
    return reply(422, { error: "تعذّرت قراءة ملف PDF؛ قد يكون محمياً أو تالفاً. صدّر المقايسة إلى Excel واستوردها." });
  }
});
