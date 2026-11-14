import {createClient} from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import {SUPABASE_URL, SUPABASE_ANON_KEY} from "./config.js";

/* ---------- helpers ---------- */
const $root = document.getElementById("root");
const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const dstr = (d = new Date()) => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
const GOAL = 3;
const lsGet = k => { try { return localStorage.getItem(k); } catch (e) { return null; } };
const lsSet = (k, v) => { try { localStorage.setItem(k, v); } catch (e) {} };

const UI = {
 en:{timeline:"Timeline",cards:"Cards",admin:"Admin",login:"Log in",logout:"Log out",signup:"Create account",email:"Email",password:"Password (min. 6 characters)",
  haveAcc:"I already have an account",noAcc:"Create a new account",guest:"You are not logged in: progress is not saved.",goal:"Daily goal",lessons:"lessons",total:"Overall",
  start:"Start quiz",next:"Next lesson",ok:"Correct!",wrong:"Not quite",again:"Try again",unlocked:"Card unlocked",back:"← Back to timeline",tl:"Back to timeline",
  collection:"Your collection",locked:"Locked",open:"Open",loading:"Loading…",confirm:"Check your email to confirm your account, then log in.",
  newL:"New lesson",editL:"Edit lesson",chapter:"Chapter",when:"When",title:"Title",text:"Explanation",q:"Question",o1:"Correct answer",o2:"Wrong answer 1",o3:"Wrong answer 2",o4:"Wrong answer 3",x:"Why is it correct? (optional)",
  save:"Save lesson",cancel:"Cancel",edit:"Edit",del:"Delete",allLessons:"All lessons",fillBoth:"Fill in every field of a language (or leave that language empty).",needOne:"Fill in at least one language.",saved:"Saved.",failed:"Could not save: ",delAsk:"Delete this lesson for everyone?",
  setup:"Setup needed: fill in SUPABASE_URL and SUPABASE_ANON_KEY in config.js.",loadErr:"Could not load lessons: ",langNote:"Fill in English, Dutch or both. A missing language falls back to the other."},
 nl:{timeline:"Tijdlijn",cards:"Kaarten",admin:"Beheer",login:"Inloggen",logout:"Uitloggen",signup:"Account maken",email:"E-mail",password:"Wachtwoord (min. 6 tekens)",
  haveAcc:"Ik heb al een account",noAcc:"Nieuw account maken",guest:"Je bent niet ingelogd: voortgang wordt niet bewaard.",goal:"Dagdoel",lessons:"lessen",total:"Totaal",
  start:"Start quiz",next:"Volgende les",ok:"Juist!",wrong:"Niet helemaal",again:"Opnieuw",unlocked:"Kaart ontgrendeld",back:"← Terug naar tijdlijn",tl:"Terug naar tijdlijn",
  collection:"Jouw collectie",locked:"Vergrendeld",open:"Open",loading:"Laden…",confirm:"Check je e-mail om je account te bevestigen en log daarna in.",
  newL:"Nieuwe les",editL:"Les bewerken",chapter:"Hoofdstuk",when:"Wanneer",title:"Titel",text:"Uitleg",q:"Vraag",o1:"Juist antwoord",o2:"Fout antwoord 1",o3:"Fout antwoord 2",o4:"Fout antwoord 3",x:"Waarom is het juist? (optioneel)",
  save:"Les opslaan",cancel:"Annuleren",edit:"Bewerk",del:"Verwijder",allLessons:"Alle lessen",fillBoth:"Vul alle velden van een taal in (of laat die taal leeg).",needOne:"Vul minstens één taal in.",saved:"Opgeslagen.",failed:"Opslaan mislukt: ",delAsk:"Deze les voor iedereen verwijderen?",
  setup:"Configuratie nodig: vul SUPABASE_URL en SUPABASE_ANON_KEY in config.js in.",loadErr:"Lessen laden mislukt: ",langNote:"Vul Engels, Nederlands of beide in. Een ontbrekende taal valt terug op de andere."}
};

/* ---------- state ---------- */
const st = {
  lang: lsGet("aeon-lang") === "nl" ? "nl" : "en",
  chapters: [], lessons: [], loaded: false, error: "",
  user: null, isAdmin: false, done: new Set(),
  stats: {xp: 0, streak: 0, last_day: null, day: null, today_n: 0},
  v: {tab: "timeline", ch: null, lessonId: null, order: [], picked: null, authMode: "login", msg: "", msgKind: "", editId: null}
};
const t = k => (UI[st.lang] && UI[st.lang][k]) || UI.en[k];
const gl = l => l[st.lang] || l.en || l.nl;
const chName = c => st.lang === "nl" ? c.name_nl : c.name_en;
const chRange = c => st.lang === "nl" ? c.range_nl : c.range_en;
const chOf = id => st.chapters.find(c => c.id === id) || st.chapters[0];
const inCh = id => st.lessons.filter(l => l.chapter === id);
const ordered = () => st.chapters.flatMap(c => inCh(c.id));
document.documentElement.lang = st.lang;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  $root.innerHTML = `<div class="auth"><div class="card"><h2>⏳ Aeon</h2><p>${esc(UI.en.setup)}<br><br>${esc(UI.nl.setup)}</p></div></div>`;
  throw new Error("Supabase not configured");
}
const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

/* ---------- data ---------- */
async function loadContent() {
  const [c, l] = await Promise.all([
    sb.from("chapters").select("*").order("sort"),
    sb.from("lessons").select("*").order("sort")
  ]);
  if (c.error || l.error) { st.error = (c.error || l.error).message; return; }
  st.chapters = c.data; st.lessons = l.data; st.error = "";
  if (!st.v.ch && st.chapters.length) st.v.ch = st.chapters[0].id;
}
function normalizeStats() {
  const today = dstr(), y = new Date(); y.setDate(y.getDate() - 1);
  const s = st.stats;
  if (s.day !== today) { s.day = today; s.today_n = 0; }
  if (s.last_day && s.last_day !== today && s.last_day !== dstr(y)) s.streak = 0;
}
async function loadUser() {
  const {data} = await sb.auth.getSession();
  st.user = data.session ? data.session.user : null;
  st.isAdmin = false; st.done = new Set();
  st.stats = {xp: 0, streak: 0, last_day: null, day: null, today_n: 0};
  if (st.user) {
    const [p, s, a] = await Promise.all([
      sb.from("progress").select("lesson_id"),
      sb.from("stats").select("*").maybeSingle(),
      sb.rpc("is_admin")
    ]);
    if (p.data) st.done = new Set(p.data.map(r => r.lesson_id));
    if (s.data) st.stats = {xp: s.data.xp, streak: s.data.streak, last_day: s.data.last_day, day: s.data.day, today_n: s.data.today_n};
    st.isAdmin = a.data === true;
  }
  normalizeStats();
}

/* ---------- quiz ---------- */
function shuffle(n) { const a = [...Array(n).keys()]; for (let i = n - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }
async function answer(i) {
  const v = st.v; if (v.picked !== null) return;
  const l = st.lessons.find(x => x.id === v.lessonId);
  v.picked = i;
  const right = v.order[i] === 0, first = !st.done.has(l.id);
  const s = st.stats; normalizeStats();
  s.xp += right ? (first ? 10 : 2) : 1; s.today_n++;
  const today = dstr(), y = new Date(); y.setDate(y.getDate() - 1);
  if (s.last_day !== today) { s.streak = s.last_day === dstr(y) ? s.streak + 1 : 1; s.last_day = today; }
  if (right) st.done.add(l.id);
  render();
  if (st.user) {
    if (right && first) await sb.from("progress").upsert({lesson_id: l.id});
    await sb.from("stats").upsert({user_id: st.user.id, xp: s.xp, streak: s.streak, last_day: s.last_day, day: s.day, today_n: s.today_n});
  }
}

/* ---------- admin ---------- */
const FIELDS = ["w", "ti", "tx", "q", "o1", "o2", "o3", "o4", "x"];
function readLang(lg) {
  const g = f => (document.getElementById(lg + "-" + f).value || "").trim();
  const vals = Object.fromEntries(FIELDS.map(f => [f, g(f)]));
  const required = ["w", "ti", "tx", "q", "o1", "o2", "o3", "o4"];
  const filled = required.filter(f => vals[f]);
  if (filled.length === 0 && !vals.x) return {empty: true};
  if (filled.length < required.length) return {bad: true};
  return {w: vals.w, ti: vals.ti, tx: vals.tx, q: vals.q, o: [vals.o1, vals.o2, vals.o3, vals.o4], x: vals.x};
}
async function saveLesson() {
  const v = st.v, en = readLang("en"), nl = readLang("nl");
  const setMsg = (m, k) => { v.msg = m; v.msgKind = k; const el = document.getElementById("f-msg"); if (el) { el.textContent = m; el.className = "note " + (k || ""); } };
  if (en.bad || nl.bad) return setMsg(t("fillBoth"), "err");
  if (en.empty && nl.empty) return setMsg(t("needOne"), "err");
  const chapter = document.getElementById("f-ch").value;
  const row = {chapter, en: en.empty ? null : en, nl: nl.empty ? null : nl};
  let res;
  if (v.editId) res = await sb.from("lessons").update(row).eq("id", v.editId);
  else {
    row.id = "l" + Date.now().toString(36);
    row.sort = st.lessons.reduce((m, l) => Math.max(m, l.sort), 0) + 1;
    res = await sb.from("lessons").insert(row);
  }
  if (res.error) return setMsg(t("failed") + res.error.message, "err");
  v.editId = null; v.msg = t("saved"); v.msgKind = "good";
  await loadContent(); render();
}
async function deleteLesson(id) {
  if (!confirm(t("delAsk"))) return;
  const res = await sb.from("lessons").delete().eq("id", id);
  if (res.error) { st.v.msg = t("failed") + res.error.message; st.v.msgKind = "err"; }
  await loadContent(); render();
}

/* ---------- views ---------- */
function vTop() {
  const tabs = [["timeline", t("timeline")], ["cards", t("cards")]].concat(st.isAdmin ? [["admin", t("admin")]] : []);
  const s = st.stats;
  return `<div class="top"><span class="logo">⏳ Aeon</span><div class="tabs">${tabs.map(([k, n]) => `<button class="tab ${st.v.tab === k ? "on" : ""}" data-act="tab" data-v="${k}">${n}</button>`).join("")}</div>
  <span class="pill fire">🔥 ${s.streak}</span><span class="pill xp">⭐ ${s.xp}</span><button class="lang" data-act="lang">${st.lang.toUpperCase()}</button>
  ${st.user ? `<button class="lang" data-act="logout">${t("logout")}</button>` : `<button class="lang" data-act="tab" data-v="auth">${t("login")}</button>`}</div>`;
}
function vSide() {
  const all = ordered(), done = all.filter(l => st.done.has(l.id)).length, s = st.stats;
  const pct = id => { const ls = inCh(id); return ls.length ? Math.round(ls.filter(l => st.done.has(l.id)).length / ls.length * 100) : 0; };
  return `<aside class="side"><div class="goal"><b>${t("goal")}</b>: ${Math.min(s.today_n, GOAL)}/${GOAL} ${t("lessons")}<div class="bar"><i style="width:${Math.min(100, s.today_n / GOAL * 100)}%"></i></div>
  <div style="margin-top:10px"><b>${t("total")}</b>: ${done}/${all.length}</div><div class="bar"><i style="width:${all.length ? done / all.length * 100 : 0}%"></i></div></div>
  <div class="tl">${st.chapters.map(c => `<button class="ch ${st.v.ch === c.id && st.v.tab === "timeline" ? "on" : ""}" style="--c:${esc(c.color)}" data-act="chapter" data-id="${esc(c.id)}"><b>${esc(c.emoji)} ${esc(chName(c))}</b><small>${esc(chRange(c))}</small><div class="p"><i style="width:${pct(c.id)}%"></i></div></button>`).join("")}</div></aside>`;
}
const PATH_X = [0, -44, -64, -44, 0, 44, 64, 44];
function vTimeline() {
  const c = chOf(st.v.ch); if (!c) return "";
  return `<div class="hero" style="--c:${esc(c.color)}"><div><h1>${esc(chName(c))}</h1><p>${esc(chRange(c))}</p></div><div class="e">${esc(c.emoji)}</div></div>
  <div class="path" style="--c:${esc(c.color)}">${inCh(c.id).map((l, i) => { const d = gl(l), done = st.done.has(l.id); return `<div class="pn" style="--x:${PATH_X[i % PATH_X.length]}px"><button class="pbtn ${done ? "done" : ""}" data-act="open" data-id="${esc(l.id)}" aria-label="${esc(d.ti)}">${done ? "✓" : esc(c.emoji)}</button><div class="pl"><b>${esc(d.ti)}</b><small>${esc(d.w)}</small></div></div>`; }).join("")}</div>`;
}
function vLesson() {
  const v = st.v, l = st.lessons.find(x => x.id === v.lessonId); if (!l) return vTimeline();
  const d = gl(l), c = chOf(l.chapter);
  const left = `<div class="card"><span class="when" style="--c:${esc(c.color)}">${esc(c.emoji)} ${esc(chName(c))} · ${esc(d.w)}</span><h2>${esc(d.ti)}</h2><p>${esc(d.tx)}</p></div>`;
  let right;
  if (!v.order.length) right = `<div class="card q"><h2>🧠 Quiz</h2><p>${esc(d.q)}</p><button class="btn" data-act="start">${t("start")}</button></div>`;
  else {
    const opts = v.order.map((oi, i) => { let k = "opt"; if (v.picked !== null) { if (oi === 0) k += " ok"; else if (i === v.picked) k += " bad"; } return `<button class="${k}" ${v.picked !== null ? "disabled" : ""} data-act="pick" data-i="${i}">${esc(d.o[oi])}</button>`; }).join("");
    let foot = "";
    if (v.picked !== null) {
      const right_ = v.order[v.picked] === 0, a = ordered(), nx = a[a.findIndex(x => x.id === l.id) + 1];
      const correct = d.o[0];
      foot = right_
        ? `<div class="fb ok"><div><div class="fbt">✅ ${t("ok")}</div><div class="fbx">${esc(d.x)}</div></div><div class="fbb"><button class="btn sec" data-act="home">${t("tl")}</button>${nx ? `<button class="btn" data-act="open" data-id="${esc(nx.id)}">${t("next")}</button>` : ""}</div></div>`
        : `<div class="fb bad"><div><div class="fbt">❌ ${t("wrong")}</div><div class="fbx">${esc(correct)}${d.x ? " — " + esc(d.x) : ""}</div></div><div class="fbb"><button class="btn sec" data-act="home">${t("tl")}</button><button class="btn red" data-act="start">${t("again")}</button></div></div>`;
    }
    right = `<div class="card q"><h2>${esc(d.q)}</h2>${opts}</div>${foot}`;
  }
  return `<button class="back" data-act="home">${t("back")}</button><div class="split" style="--c:${esc(c.color)}">${left}${right}</div>`;
}
function vCards() {
  const all = ordered();
  return `<h1 style="margin-bottom:6px">${t("collection")}</h1><p class="note" style="margin-bottom:10px">${all.filter(l => st.done.has(l.id)).length} / ${all.length}</p>` +
    st.chapters.map(c => `<h2 class="sec">${esc(c.emoji)} ${esc(chName(c))}</h2><div class="cgrid">${inCh(c.id).map(l => { const d = gl(l); return st.done.has(l.id) ? `<div class="cc" style="--c:${esc(c.color)}" data-act="open" data-id="${esc(l.id)}"><span class="e">${esc(c.emoji)}</span><div><b>${esc(d.ti)}</b><br><small>${esc(d.w)}</small></div></div>` : `<div class="cc lock"><span class="e">🔒</span><b>${t("locked")}</b></div>`; }).join("")}</div>`).join("");
}
function langForm(lg, d) {
  d = d || {};
  const o = d.o || [];
  return `<div><h3 style="margin-top:6px">${lg === "en" ? "English" : "Nederlands"}</h3>
  <input id="${lg}-w" placeholder="${t("when")}" value="${esc(d.w)}"><input id="${lg}-ti" placeholder="${t("title")}" value="${esc(d.ti)}">
  <textarea id="${lg}-tx" rows="5" placeholder="${t("text")}">${esc(d.tx)}</textarea><input id="${lg}-q" placeholder="${t("q")}" value="${esc(d.q)}">
  <input id="${lg}-o1" placeholder="✅ ${t("o1")}" value="${esc(o[0])}"><input id="${lg}-o2" placeholder="${t("o2")}" value="${esc(o[1])}">
  <input id="${lg}-o3" placeholder="${t("o3")}" value="${esc(o[2])}"><input id="${lg}-o4" placeholder="${t("o4")}" value="${esc(o[3])}">
  <input id="${lg}-x" placeholder="${t("x")}" value="${esc(d.x)}"></div>`;
}
function vAdmin() {
  const v = st.v, ed = v.editId ? st.lessons.find(l => l.id === v.editId) : null;
  return `<h1>${ed ? t("editL") : t("newL")}</h1><p class="note">${t("langNote")}</p>
  <select id="f-ch" style="max-width:420px">${st.chapters.map(c => `<option value="${esc(c.id)}" ${(ed ? ed.chapter : v.ch) === c.id ? "selected" : ""}>${esc(c.emoji)} ${esc(chName(c))}</option>`).join("")}</select>
  <div class="grid2">${langForm("en", ed && ed.en)}${langForm("nl", ed && ed.nl)}</div>
  <p id="f-msg" class="note ${v.msgKind}">${esc(v.msg)}</p>
  <div style="display:flex;gap:10px;max-width:420px"><button class="btn" data-act="save">${t("save")}</button>${ed ? `<button class="btn sec" data-act="cancel">${t("cancel")}</button>` : ""}</div>
  <h2 class="sec">${t("allLessons")}</h2>${ordered().map(l => { const d = gl(l); return `<div class="row"><div class="t"><b>${esc(d.ti)}</b><small>${esc(chName(chOf(l.chapter)))} · ${esc(d.w)}</small></div><button class="lang sm" data-act="edit" data-id="${esc(l.id)}">${t("edit")}</button><button class="lang sm" data-act="del" data-id="${esc(l.id)}">${t("del")}</button></div>`; }).join("")}`;
}
function vAuth() {
  const m = st.v.authMode === "login";
  return `<div class="auth"><div class="card"><h2>${m ? t("login") : t("signup")}</h2>
  <input id="a-email" type="email" placeholder="${t("email")}" autocomplete="email"><input id="a-pw" type="password" placeholder="${t("password")}" autocomplete="${m ? "current-password" : "new-password"}">
  <p id="a-msg" class="note ${st.v.msgKind}">${esc(st.v.msg)}</p>
  <button class="btn" data-act="auth">${m ? t("login") : t("signup")}</button>
  <button class="link" data-act="authmode">${m ? t("noAcc") : t("haveAcc")}</button></div></div>`;
}
function render() {
  const v = st.v;
  let main;
  if (!st.loaded) main = `<p class="note">${t("loading")}</p>`;
  else if (st.error) main = `<p class="note err">${t("loadErr")}${esc(st.error)}</p>`;
  else if (v.tab === "auth") main = vAuth();
  else if (v.tab === "cards") main = vCards();
  else if (v.tab === "admin" && st.isAdmin) main = vAdmin();
  else main = v.lessonId ? vLesson() : vTimeline();
  const warn = !st.user && v.tab !== "auth" ? `<div class="warn">${t("guest")} <button class="link" data-act="tab" data-v="auth" style="margin:0 0 0 8px">${t("login")}</button></div>` : "";
  $root.innerHTML = vTop() + `<div class="layout">${st.loaded && !st.error ? vSide() : "<div></div>"}<main class="main ${v.picked !== null && v.lessonId ? "pad" : ""}">${warn}${main}</main></div>`;
}

/* ---------- events ---------- */
document.addEventListener("click", async e => {
  const el = e.target.closest("[data-act]"); if (!el) return;
  const a = el.dataset.act, v = st.v;
  if (a === "tab") { v.tab = el.dataset.v; v.lessonId = null; v.msg = ""; v.msgKind = ""; if (v.tab !== "admin") v.editId = null; render(); window.scrollTo(0, 0); }
  else if (a === "lang") { st.lang = st.lang === "en" ? "nl" : "en"; lsSet("aeon-lang", st.lang); document.documentElement.lang = st.lang; render(); }
  else if (a === "chapter") { v.tab = "timeline"; v.ch = el.dataset.id; v.lessonId = null; render(); window.scrollTo(0, 0); }
  else if (a === "home") { v.lessonId = null; render(); window.scrollTo(0, 0); }
  else if (a === "open") { const l = st.lessons.find(x => x.id === el.dataset.id); if (l) { v.tab = "timeline"; v.ch = l.chapter; v.lessonId = l.id; v.order = []; v.picked = null; render(); window.scrollTo(0, 0); } }
  else if (a === "start") { const l = st.lessons.find(x => x.id === v.lessonId); v.order = shuffle(gl(l).o.length); v.picked = null; render(); }
  else if (a === "pick") answer(Number(el.dataset.i));
  else if (a === "logout") { await sb.auth.signOut(); }
  else if (a === "authmode") { v.authMode = v.authMode === "login" ? "signup" : "login"; v.msg = ""; render(); }
  else if (a === "auth") {
    const email = document.getElementById("a-email").value.trim(), password = document.getElementById("a-pw").value;
    const setMsg = (m, k) => { v.msg = m; v.msgKind = k; document.getElementById("a-msg").textContent = m; document.getElementById("a-msg").className = "note " + k; };
    if (!email || !password) return;
    if (v.authMode === "login") {
      const {error} = await sb.auth.signInWithPassword({email, password});
      if (error) setMsg(error.message, "err"); else { v.tab = "timeline"; v.msg = ""; }
    } else {
      const {data, error} = await sb.auth.signUp({email, password, options: {emailRedirectTo: location.origin + location.pathname}});
      if (error) setMsg(error.message, "err");
      else if (!data.session) { v.authMode = "login"; setMsg(t("confirm"), "good"); render(); }
      else { v.tab = "timeline"; v.msg = ""; }
    }
  }
  else if (a === "save") saveLesson();
  else if (a === "cancel") { v.editId = null; v.msg = ""; render(); }
  else if (a === "edit") { v.editId = el.dataset.id; v.msg = ""; render(); window.scrollTo(0, 0); }
  else if (a === "del") deleteLesson(el.dataset.id);
});

/* ---------- boot ---------- */
sb.auth.onAuthStateChange((event) => {
  if (event === "SIGNED_IN" || event === "SIGNED_OUT") {
    // defer: awaiting Supabase calls inside this callback can deadlock the client
    setTimeout(async () => {
      await loadUser();
      if (st.v.tab === "admin" && !st.isAdmin) st.v.tab = "timeline";
      render();
    }, 0);
  }
});
render();
await loadContent();
await loadUser();
st.loaded = true;
render();
