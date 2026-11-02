// مساعد Claude لمدير المكتب (Supabase Edge Function: claude-assistant).
//
// • يقرأ ملخص المنظومة عبر الدالة ai_context بصلاحية المستخدم نفسه؛ قاعدة البيانات ترفض كل من ليس مدير المكتب.
// • مفتاح Anthropic سرّ في Supabase باسم ANTHROPIC_API_KEY (Edge Functions ← Secrets) ولا يصل إلى التطبيق.
// • لا يعدّل أي بيانات، ويُسجَّل كل سؤال في سجل التدقيق عبر ai_log.
//
// النشر: من لوحة Supabase ← Edge Functions ← Deploy a new function ← Via Editor، بالاسم claude-assistant
// (مع إبقاء «Verify JWT» مفعّلاً)، أو: supabase functions deploy claude-assistant
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

const MODEL_RE = /^[a-z0-9][a-z0-9.\-]{2,60}$/;
const DEFAULT_MODEL = "claude-sonnet-5-5";

type Turn = { role: "user" | "assistant"; content: string };

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { code: "method", error: "الطلب يكون بـ POST" });

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return reply(401, { code: "forbidden", error: "سجّل الدخول أولاً" });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") || req.headers.get("apikey") || "";
  const db = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // المحادثة: أدوار صحيحة، ونص محدود، وتبدأ وتنتهي بسؤال المستخدم، ويُدمج المتتالي من الدور نفسه
  let body: { messages?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    return reply(400, { code: "bad_request", error: "طلب غير صالح" });
  }
  const raw = Array.isArray(body.messages) ? body.messages.slice(-24) : [];
  const turns: Turn[] = [];
  for (const m of raw) {
    const r = (m as { role?: unknown })?.role;
    const c = (m as { content?: unknown })?.content;
    const role = r === "assistant" ? "assistant" : r === "user" ? "user" : null;
    const text = typeof c === "string" ? c.trim().slice(0, 8000) : "";
    if (!role || !text) continue;
    const last = turns[turns.length - 1];
    if (last && last.role === role) last.content += "\n\n" + text;
    else turns.push({ role, content: text });
  }
  while (turns.length && turns[0].role !== "user") turns.shift();
  if (!turns.length || turns[turns.length - 1].role !== "user") {
    return reply(400, { code: "bad_request", error: "اكتب سؤالك" });
  }

  // ملخص المنظومة بصلاحية المستخدم (مدير المكتب وحده، ومع تشغيل المساعد)
  const { data: ctx, error: ctxErr } = await db.rpc("ai_context");
  if (ctxErr) {
    const msg = ctxErr.message ?? "";
    const disabled = msg.includes("متوقف");
    return reply(disabled ? 409 : 403, { code: disabled ? "disabled" : "forbidden", error: msg });
  }

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return reply(503, { code: "missing_key", error: "لم يُضف مفتاح Anthropic بعد (ANTHROPIC_API_KEY)" });

  const context = (ctx ?? {}) as Record<string, unknown>;
  const model = typeof context.model === "string" && MODEL_RE.test(context.model) ? context.model : DEFAULT_MODEL;
  const extra = typeof context.instructions === "string" ? context.instructions.trim() : "";
  let snapshot = JSON.stringify(context);
  if (snapshot.length > 180000) snapshot = snapshot.slice(0, 180000) + "…";
  const today = new Date().toISOString().slice(0, 10);

  const system = [
    `أنت مساعد مدير المكتب داخل «منظومة متابعة الدورة المستندية» في ${context.org ?? "مكتب الشؤون الهندسية"}. تاريخ اليوم ${today}.`,
    "أجب بالعربية الفصحى الواضحة والموجزة، بنص عادي دون جداول Markdown؛ استخدم «•» للقوائم، والأرقام بفواصل الآلاف مع العملة.",
    "اعتمد فقط على ملخص المنظومة المرفق. لا تخترع أرقاماً أو أسماء أو تواريخ؛ وإن لم تكفِ البيانات فقل ذلك صراحة واذكر ما يلزم إدخاله.",
    "المفاهيم: العقد (contract) قد يضم أعمال عدة شركات (works) برقم عقد واحد. لكل عقد مهندسون من أربعة أنواع: sup مشرف، qty حصر، fol متابعة، saf سلامة، ومن كل نوع أكثر من مهندس، لكلٍّ رقم تكليفه (assign_no).",
    "contract_value هي قيمة الأعمال التعاقدية، وexecuted_value قيمة الأعمال المنفذة. الضمان الابتدائي والنهائي يُحسبان من قيمة الأعمال المنفذة بالنسب في guarantee_rates.",
    "الدورة المستندية مراحل ونماذج (forms)؛ progress_pct نسبة الإنجاز، وnext_form المستند التالي المطلوب، وpending_requests طلبات تنتظر اعتماد المدير.",
    "لا تستطيع تعديل أي بيانات. عند الحاجة اشرح للمدير أين يعدّلها داخل المنظومة: صفحة العقد (الأعمال، المهندسون، المالية، النماذج)، أو لوحة التحكم، أو «التخصيص والتطوير».",
    "عند طلب تطوير أو ميزة: قدّم اقتراحاً محدداً قابلاً للتنفيذ، عنوانه في السطر الأول، ثم الفائدة وخطوات التنفيذ، ليحفظه المدير «فكرة تطوير».",
    "اذكر رقم العقد (أو رقم التكليف إن لم يوجد) عند الحديث عن أي عقد.",
    extra ? `تعليمات دائمة من مدير المكتب:\n${extra}` : "",
    `ملخص المنظومة الآن (JSON):\n${snapshot}`,
  ].filter(Boolean).join("\n\n");

  let res: Response;
  try {
    res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        model,
        max_tokens: 2048,
        // الملخص ثابت أثناء المحادثة: تخزينه مؤقتاً يخفض التكلفة والزمن
        system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
        messages: turns,
      }),
    });
  } catch (e) {
    return reply(502, { code: "anthropic", error: `تعذّر الاتصال بخدمة Claude: ${(e as Error).message}` });
  }

  // deno-lint-ignore no-explicit-any
  const out: any = await res.json().catch(() => ({}));
  if (!res.ok) {
    return reply(502, { code: "anthropic", error: out?.error?.message ?? `HTTP ${res.status}` });
  }

  const text = Array.isArray(out?.content)
    ? out.content
      // deno-lint-ignore no-explicit-any
      .filter((b: any) => b?.type === "text" && typeof b.text === "string")
      // deno-lint-ignore no-explicit-any
      .map((b: any) => b.text)
      .join("\n")
      .trim()
    : "";
  const usage = {
    input_tokens: (out?.usage?.input_tokens ?? 0) + (out?.usage?.cache_read_input_tokens ?? 0) +
      (out?.usage?.cache_creation_input_tokens ?? 0),
    output_tokens: out?.usage?.output_tokens ?? 0,
  };
  const used = typeof out?.model === "string" ? out.model : model;

  await db.rpc("ai_log", {
    p_model: used,
    p_input_tokens: usage.input_tokens,
    p_output_tokens: usage.output_tokens,
    p_question_chars: turns[turns.length - 1].content.length,
  });

  return reply(200, {
    text: text || "لم يصل رد من Claude. أعد صياغة السؤال.",
    model: used,
    usage,
    stop_reason: out?.stop_reason ?? null,
  });
});
