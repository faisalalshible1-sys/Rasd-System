// مساعد Claude لمدير المكتب (Supabase Edge Function: claude-assistant).
//
// • يقرأ ملخص المنظومة عبر الدالة ai_context بصلاحية المستخدم نفسه؛ قاعدة البيانات ترفض كل من ليس مدير المكتب.
// • مفتاح Anthropic سرّ في Supabase باسم ANTHROPIC_API_KEY (Edge Functions ← Secrets) ولا يصل إلى التطبيق.
// • لا يعدّل أي بيانات بنفسه: يقترح التعديلات بأدوات (tools) تعود إلى التطبيق بطاقاتٍ ينفّذها المدير بضغطة،
//   وقاعدة البيانات تتحقق من الصلاحيات عند التنفيذ. يُسجَّل كل سؤال في سجل التدقيق عبر ai_log.
//
// الهوية: بوابة الخدمة («Verify JWT with legacy secret» مفعّل) يرضيها مفتاح الربط العام في Authorization،
// ورمز جلسة المستخدم يصل في x-user-token وتتحقق منه قاعدة البيانات نفسها (ai_context ترفض كل من ليس مدير المكتب).
// النشر: من لوحة Supabase ← Edge Functions ← Deploy a new function ← Via Editor، بالاسم claude-assistant،
// أو: supabase functions deploy claude-assistant
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-user-token",
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

// أدوات الاقتراح: لا تُنفَّذ هنا؛ تعود إلى التطبيق ليعتمدها المدير
const money = { type: "number", minimum: 0 };
const day = { type: "string", description: "تاريخ بصيغة YYYY-MM-DD" };
const summary = { type: "string", description: "وصف عربي موجز للتعديل كما يراه المدير قبل اعتماده" };
const TOOLS = [
  {
    name: "propose_work_values",
    description: "اقتراح القيمة التعاقدية والمنفذ لبند (عمل) في عقد. استخدم معرّف البند من works[].id.",
    input_schema: {
      type: "object",
      properties: { work_id: { type: "string" }, contract_value: money, executed_value: money, summary },
      required: ["work_id", "summary"],
    },
  },
  {
    name: "propose_variation",
    description: "اقتراح أمر تغيير جديد (زيادة أو نقص) على عقد. معرّف العقد من contracts[].id.",
    input_schema: {
      type: "object",
      properties: {
        project_id: { type: "string" },
        kind: { type: "string", enum: ["add", "deduct"] },
        amount: { type: "number", exclusiveMinimum: 0 },
        title: { type: "string" },
        ref_no: { type: "string" },
        approved_on: day,
        work_id: { type: "string" },
        summary,
      },
      required: ["project_id", "kind", "amount", "title", "summary"],
    },
  },
  {
    name: "propose_extract",
    description: "اقتراح تسجيل مستخلص جديد لعقد بقيمته واستقطاعاته وحالته.",
    input_schema: {
      type: "object",
      properties: {
        project_id: { type: "string" },
        kind: { type: "string", enum: ["interim", "final"] },
        ref_no: { type: "string" },
        period_from: day,
        period_to: day,
        submitted_on: day,
        gross: money,
        retention: money,
        advance: money,
        penalties: money,
        taxes: money,
        other: money,
        status: { type: "string", enum: ["draft", "submitted", "approved", "referred", "paid", "rejected"] },
        approved_on: day,
        paid_amount: money,
        paid_on: day,
        summary,
      },
      required: ["project_id", "gross", "status", "summary"],
    },
  },
  {
    name: "propose_extract_status",
    description: "اقتراح تغيير حالة مستخلص قائم أو تسجيل دفعه. معرّف المستخلص من extract_list[].id.",
    input_schema: {
      type: "object",
      properties: {
        extract_id: { type: "string" },
        status: { type: "string", enum: ["draft", "submitted", "approved", "referred", "paid", "rejected"] },
        paid_amount: money,
        paid_on: day,
        approved_on: day,
        referred_on: day,
        referral_no: { type: "string", description: "رقم خطاب الإحالة للصرف أو أمر الصرف" },
        summary,
      },
      required: ["extract_id", "status", "summary"],
    },
  },
  {
    name: "propose_extract_payment",
    description: "اقتراح تسجيل دفعة (كاملة أو جزئية) على مستخلص معتمد أو محال للصرف في سجل دفعاته. لا تتجاوز المتبقي (net − paid). يصبح المستخلص «مدفوع» حين تكتمل دفعاته.",
    input_schema: {
      type: "object",
      properties: {
        extract_id: { type: "string" },
        amount: money,
        paid_on: day,
        method: { type: "string", enum: ["transfer", "cheque", "cash", "other"] },
        ref_no: { type: "string" },
        summary,
      },
      required: ["extract_id", "amount", "summary"],
    },
  },
  {
    name: "propose_contract_advance",
    description: "اقتراح تسجيل الدفعة المقدمة لعقد أو تعديلها (paid_on فارغ إن لم تُصرف بعد). لا تقل عما استُرد منها.",
    input_schema: {
      type: "object",
      properties: {
        project_id: { type: "string" },
        amount: money,
        paid_on: day,
        summary,
      },
      required: ["project_id", "amount", "summary"],
    },
  },
  {
    name: "propose_contract_no",
    description: "اقتراح رقم العقد لعقد.",
    input_schema: {
      type: "object",
      properties: { project_id: { type: "string" }, contract_no: { type: "string" }, summary },
      required: ["project_id", "contract_no", "summary"],
    },
  },
  {
    name: "propose_form_status",
    description: "اقتراح تغيير حالة نموذج في الدورة المستندية لعقد. مفتاح النموذج من forms[].key.",
    input_schema: {
      type: "object",
      properties: {
        project_id: { type: "string" },
        form_key: { type: "string" },
        status: { type: "string", enum: ["done", "wip", "todo", "na"] },
        summary,
      },
      required: ["project_id", "form_key", "status", "summary"],
    },
  },
  {
    name: "propose_setting",
    description: "اقتراح تعديل إعداد حي (مثل نسب الضمان finance.guarantee_initial_rate أو الإعلان ui.announcement أو المظهر ui.appearance).",
    input_schema: {
      type: "object",
      properties: { key: { type: "string" }, value: {}, summary },
      required: ["key", "value", "summary"],
    },
  },
  {
    name: "propose_idea",
    description: "حفظ اقتراح تطوير «فكرة تطوير» في قائمة الأفكار.",
    input_schema: {
      type: "object",
      properties: {
        title: { type: "string" },
        body: { type: "string" },
        category: { type: "string", enum: ["feature", "design", "data", "security", "bug", "other"] },
        priority: { type: "string", enum: ["low", "normal", "high", "urgent"] },
        summary,
      },
      required: ["title", "body", "summary"],
    },
  },
];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply(405, { code: "method", error: "الطلب يكون بـ POST" });

  // رمز جلسة المستخدم (منفصلاً عن مفتاح البوابة)، أو Authorization نفسه إن لم يُرسل
  const userToken = (req.headers.get("x-user-token") ?? "").trim();
  const auth = userToken ? `Bearer ${userToken}` : (req.headers.get("Authorization") ?? "");
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

  // المفتاح كما أُضيف، بعد إزالة المسافات والأسطر وعلامات الاقتباس التي تُنسخ معه أحياناً
  const key = (Deno.env.get("ANTHROPIC_API_KEY") ?? "").replace(/\s+/g, "").replace(/^["'`]+|["'`]+$/g, "");
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
    "المالية: لكل بند works[] قيمته التعاقدية والمنفذ منه؛ إن وُجدت قيم البنود فالقيمة التعاقدية مجموعها (value_source=items). أوامر التغيير variations تزيد أو تنقص القيمة، وadjusted_value القيمة بعد التغيير. المستخلصات extract_list: قيمة الأعمال (gross) والتأمين المحتجز (retention) والاستقطاعات الأخرى ومنها المخصصة (custom_deductions بأنواعها في finance_defaults.deduction_types) والصافي (net) والمدفوع (paid) ودفعاته (payments)؛ مسار المستخلص: مسودة ← مقدم ← معتمد ← محال للصرف (referred، بتاريخ referred_on ورقم referral_no) ← مدفوع؛ والمعتمد والمحال والمدفوع يحدد المنفذ (executed_source=extracts). الدفعة المقدمة للعقد (advance) تُسترد من المستخلصات (advance_recovery) حتى تكتمل، والنسب الافتراضية في finance_defaults. المتبقي من الأعمال = adjusted_value − executed_value، والمتبقي للدفع = adjusted_value − المدفوع.",
    "لا تنفّذ أي تعديل بنفسك. إذا طلب المدير تعديلاً أو رأيت تصحيحاً واضحاً، فاقترحه بأداة الاقتراح المناسبة (propose_*) بالمعرّفات الصحيحة من الملخص، مع summary عربي واضح؛ يظهر للمدير بطاقةً ينفّذها بضغطة، وتتحقق قاعدة البيانات من الصلاحيات. اقترح فقط ما تدعمه البيانات، ولا تخترع معرّفات. واذكر في نصك ما اقترحته ولماذا.",
    "لما لا توجد له أداة، اشرح للمدير أين يعدّله داخل المنظومة: صفحة العقد (الأعمال، المهندسون، المالية، المستخلصات، أوامر التغيير، النماذج)، أو صفحة «المالية»، أو لوحة التحكم، أو «التخصيص والتطوير».",
    "عند طلب تطوير أو ميزة: قدّم اقتراحاً محدداً قابلاً للتنفيذ (الفائدة وخطوات التنفيذ)، واقترح حفظه بأداة propose_idea.",
    "اذكر رقم العقد (أو رقم التكليف إن لم يوجد) عند الحديث عن أي عقد.",
    extra ? `تعليمات دائمة من مدير المكتب:\n${extra}` : "",
    `ملخص المنظومة الآن (JSON):\n${snapshot}`,
  ].filter(Boolean).join("\n\n");

  const payload = JSON.stringify({
    model,
    max_tokens: 4096,
    tools: TOOLS,
    tool_choice: { type: "auto" },
    // الملخص ثابت أثناء المحادثة: تخزينه مؤقتاً يخفض التكلفة والزمن
    system: [{ type: "text", text: system, cache_control: { type: "ephemeral" } }],
    messages: turns,
  });
  // يُرسل المفتاح بالترويسة x-api-key، وإن رُفض يُعاد بترويسة Authorization (الصيغتان مقبولتان لدى Anthropic)
  const call = (bearer: boolean) =>
    fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        ...(bearer ? { Authorization: `Bearer ${key}` } : { "x-api-key": key }),
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: payload,
    });

  let res: Response;
  try {
    res = await call(false);
    if (res.status === 401) {
      const again = await call(true);
      if (again.status !== 401) res = again;
    }
  } catch (e) {
    return reply(502, { code: "anthropic", error: `تعذّر الاتصال بخدمة Claude: ${(e as Error).message}` });
  }

  // deno-lint-ignore no-explicit-any
  const out: any = await res.json().catch(() => ({}));
  if (res.status === 401) {
    // تشخيص دون كشف المفتاح: نوعه وطوله وآخر أربعة أحرف منه للمطابقة مع لوحة Anthropic
    const hint = key.startsWith("sk-ant-admin")
      ? "المضاف مفتاح إدارة (Admin key) لا يصلح للأسئلة؛ أنشئ مفتاحاً من API Keys."
      : !key.startsWith("sk-ant-")
      ? "المضاف لا يبدو مفتاح Anthropic API (يبدأ عادةً بـ sk-ant-api)."
      : "المفتاح مرفوض: ربما أُلغي، أو نُسخ ناقصاً، أو يتبع حساباً آخر.";
    return reply(502, {
      code: "bad_key",
      error: `${hint} (الطول ${key.length}، وينتهي بـ …${key.slice(-4)}). صحّحه في Supabase ← Edge Functions ← Secrets ← ANTHROPIC_API_KEY.`,
    });
  }
  if (!res.ok) {
    return reply(502, { code: "anthropic", error: out?.error?.message ?? `HTTP ${res.status}` });
  }

  const blocks = Array.isArray(out?.content) ? out.content : [];
  const text = blocks
    // deno-lint-ignore no-explicit-any
    .filter((b: any) => b?.type === "text" && typeof b.text === "string")
    // deno-lint-ignore no-explicit-any
    .map((b: any) => b.text)
    .join("\n")
    .trim();
  // اقتراحات التعديل: تعود إلى التطبيق كما هي، ولا يُنفَّذ منها شيء هنا
  const actions = blocks
    // deno-lint-ignore no-explicit-any
    .filter((b: any) => b?.type === "tool_use" && typeof b.name === "string" && b.name.startsWith("propose_"))
    // deno-lint-ignore no-explicit-any
    .map((b: any) => ({ id: String(b.id ?? ""), name: b.name, input: b.input ?? {} }))
    .slice(0, 20);
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
    text: text || (actions.length ? `اقترحتُ ${actions.length} ${actions.length === 1 ? "تعديلاً" : "تعديلات"}؛ راجعها ثم نفّذ ما تعتمده.` : "لم يصل رد من Claude. أعد صياغة السؤال."),
    actions,
    model: used,
    usage,
    stop_reason: out?.stop_reason ?? null,
  });
});
