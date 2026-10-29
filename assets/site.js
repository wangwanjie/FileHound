/* FileHound 主页脚本：语言、主题、雷达扫描演示、性能条形图、渐入与下载信息 */
(function () {
  "use strict";

  var root = document.documentElement;
  var params = new URLSearchParams(location.search);
  var reduceMotion = matchMedia("(prefers-reduced-motion: reduce)");
  var I18N = window.FH_I18N || { dynamic: {} };
  var LANGS = ["zh-CN", "en", "zh-TW"];
  var currentLang = "zh-CN";
  var listeners = { lang: [], theme: [] };

  function store(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch (e) {}
  }
  function load(key) {
    try {
      return localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }
  function emit(name) {
    listeners[name].forEach(function (fn) {
      fn();
    });
  }
  function dyn(key) {
    var table = I18N.dynamic[currentLang] || I18N.dynamic["zh-CN"];
    return table[key] || I18N.dynamic["zh-CN"][key] || key;
  }

  /* ---------------- 语言 ---------------- */
  // 简体中文原文直接从 DOM 采集，避免在脚本里重复一份
  var zhText = {};
  var zhAttr = [];
  var metaDesc = document.querySelector('meta[name="description"]');
  var ogTitle = document.querySelector('meta[property="og:title"]');
  var ogDesc = document.querySelector('meta[property="og:description"]');
  zhText["meta.title"] = document.title;
  zhText["meta.desc"] = metaDesc.getAttribute("content");
  document.querySelectorAll("[data-i18n]").forEach(function (el) {
    var key = el.getAttribute("data-i18n");
    if (!(key in zhText)) {
      zhText[key] = el.innerHTML;
    }
  });
  document.querySelectorAll("[data-i18n-attr]").forEach(function (el) {
    el.getAttribute("data-i18n-attr").split(";").forEach(function (pair) {
      var parts = pair.split(":");
      var attr = parts[0];
      var key = parts[1];
      if (!(key in zhText)) {
        zhText[key] = el.getAttribute(attr) || "";
      }
      zhAttr.push([el, attr, key]);
    });
  });

  function text(key) {
    if (currentLang !== "zh-CN" && I18N[currentLang] && key in I18N[currentLang]) {
      return I18N[currentLang][key];
    }
    return zhText[key] || "";
  }

  function normalizeLang(value) {
    if (!value) {
      return null;
    }
    var v = String(value).toLowerCase();
    if (v === "en" || v.indexOf("en-") === 0) {
      return "en";
    }
    if (/^zh-(tw|hk|mo|hant)/.test(v) || v === "tw") {
      return "zh-TW";
    }
    if (v.indexOf("zh") === 0 || v === "cn") {
      return "zh-CN";
    }
    return LANGS.indexOf(value) >= 0 ? value : null;
  }

  function detectLang() {
    var list = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || "en"];
    var first = String(list[0] || "en").toLowerCase();
    if (/^zh-(tw|hk|mo|hant)/.test(first)) {
      return "zh-TW";
    }
    if (first.indexOf("zh") === 0) {
      return "zh-CN";
    }
    return "en";
  }

  function applyLang(lang, persist) {
    currentLang = LANGS.indexOf(lang) >= 0 ? lang : "zh-CN";
    root.setAttribute("lang", currentLang);
    document.title = text("meta.title");
    metaDesc.setAttribute("content", text("meta.desc"));
    ogTitle.setAttribute("content", text("meta.title"));
    ogDesc.setAttribute("content", text("meta.desc"));
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      el.innerHTML = text(el.getAttribute("data-i18n"));
    });
    zhAttr.forEach(function (item) {
      item[0].setAttribute(item[1], text(item[2]));
    });
    document.querySelectorAll("[data-lang]").forEach(function (btn) {
      btn.setAttribute("aria-pressed", btn.getAttribute("data-lang") === currentLang ? "true" : "false");
    });
    if (persist) {
      store("filehound.lang", currentLang);
    }
    root.classList.remove("i18n-pending");
    emit("lang");
  }

  document.querySelectorAll("[data-lang]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      applyLang(btn.getAttribute("data-lang"), true);
    });
  });
  applyLang(normalizeLang(params.get("lang")) || normalizeLang(load("filehound.lang")) || detectLang(), false);

  /* ---------------- 主题 ---------------- */
  var darkQuery = matchMedia("(prefers-color-scheme: dark)");
  var themeMeta = document.querySelector('meta[name="theme-color"]');
  var themePref = root.getAttribute("data-theme-pref") || "system";

  function applyTheme(pref, persist) {
    themePref = pref === "light" || pref === "dark" ? pref : "system";
    var dark = themePref === "dark" || (themePref === "system" && darkQuery.matches);
    var changed = root.getAttribute("data-theme") !== (dark ? "dark" : "light");
    root.setAttribute("data-theme", dark ? "dark" : "light");
    root.setAttribute("data-theme-pref", themePref);
    themeMeta.setAttribute("content", dark ? "#050a14" : "#f3eee2");
    document.querySelectorAll("[data-theme-set]").forEach(function (btn) {
      btn.setAttribute("aria-pressed", btn.getAttribute("data-theme-set") === themePref ? "true" : "false");
    });
    if (persist) {
      store("filehound.theme", themePref);
    }
    if (changed) {
      emit("theme");
    }
  }

  document.querySelectorAll("[data-theme-set]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      applyTheme(btn.getAttribute("data-theme-set"), true);
    });
  });
  var onSchemeChange = function () {
    if (themePref === "system") {
      applyTheme("system", false);
    }
  };
  if (darkQuery.addEventListener) {
    darkQuery.addEventListener("change", onSchemeChange);
  } else if (darkQuery.addListener) {
    darkQuery.addListener(onSchemeChange);
  }
  applyTheme(themePref, false);

  /* ---------------- 滚动渐入 ---------------- */
  var reveals = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window && !reduceMotion.matches) {
    var revealObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          revealObserver.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    reveals.forEach(function (el, i) {
      // 同一组内的卡片错开一点出现
      el.style.transitionDelay = (i % 4) * 70 + "ms";
      revealObserver.observe(el);
    });
  } else {
    reveals.forEach(function (el) {
      el.classList.add("in");
    });
  }

  /* ---------------- 雷达扫描演示 ---------------- */
  // 文件树：顶层目录 → 子目录 → 文件。标记 h 隐藏 / p 包内容 / s 系统目录 / r 需 root / c 内容含 TODO
  var TREE = [
    ["Users", [
      ["~/.config", [["git/config", "h"], ["gh/hosts.yml", "h"], ["fish/config.fish", "h"]]],
      ["~/.ssh", [["config", "h"], ["known_hosts", "h"]]],
      ["~", [[".zshrc", "hc"]]],
      ["~/Documents", [["config-notes.md", "c"], ["report-2026.pdf", ""], ["budget.numbers", ""], ["todo.txt", "c"]]],
      ["~/Projects/hound", [["Package.swift", "c"], ["Sources/main.swift", "c"], ["README.md", ""], [".gitignore", "h"], [".env", "h"]]],
      ["~/Library/Preferences", [["com.apple.dock.plist", "h"], ["com.apple.finder.plist", "h"]]],
      ["~/Downloads", [["photo.heic", ""], ["invoice.pdf", ""]]]
    ]],
    ["Applications", [
      ["/Applications/Xcode.app/Contents", [["Info.plist", "p"], ["version.plist", "p"]]],
      ["/Applications/Safari.app/Contents", [["Info.plist", "p"], ["PkgInfo", "p"]]],
      ["/Applications/FileHound.app/Contents", [["Info.plist", "p"], ["MacOS/FileHound", "p"]]]
    ]],
    ["System", [
      ["/System/Library/CoreServices", [["SystemVersion.plist", "s"], ["Finder.app", "s"]]],
      ["/System/Library/LaunchDaemons", [["ssh.plist", "s"]]]
    ]],
    ["private", [
      ["/private/etc/ssh", [["sshd_config", "s"], ["ssh_config", "s"]]],
      ["/private/etc", [["hosts", "s"]]],
      ["/private/var/root/.ssh", [["config", "rh"]]]
    ]],
    ["Library", [
      ["/Library/Fonts", [["Arial Unicode.ttf", ""]]]
    ]]
  ];
  var QUERIES = [
    { key: "q1", test: function (leaf) { return /config/i.test(leaf.name); } },
    { key: "q2", test: function (leaf) { return /\.plist$/i.test(leaf.name); } },
    { key: "q3", test: function (leaf) { return leaf.flags.indexOf("c") >= 0; } }
  ];

  var canvas = document.getElementById("radar");
  if (canvas && canvas.getContext) {
    initRadar();
  }

  function initRadar() {
    var ctx = canvas.getContext("2d");
    var list = document.getElementById("results-list");
    var foot = document.getElementById("results-foot");
    var queryEl = document.getElementById("scope-query");
    var statusEl = document.getElementById("scope-status");
    var scannedEl = document.getElementById("scope-scanned");
    var totalEl = document.getElementById("scope-total");
    var hitsEl = document.getElementById("scope-hits");

    // 把树展开成节点，并按叶子顺序分配角度（顶层目录之间留空隙）
    var tops = [];
    var leaves = [];
    var GAP = 1.2;
    var slot = 0;
    TREE.forEach(function (top, ti) {
      var topNode = { name: top[0], groups: [], r: 0.3 };
      top[1].forEach(function (group) {
        var groupNode = { name: group[0], leaves: [], r: 0.58 };
        group[1].forEach(function (leafDef) {
          var full = group[0] + "/" + leafDef[0];
          var leaf = {
            path: full,
            name: full.split("/").pop(),
            dir: full.slice(0, full.lastIndexOf("/")),
            flags: leafDef[1],
            slot: slot,
            group: groupNode,
            top: topNode,
            r: 0.8 + ((leaves.length * 37) % 9) / 100
          };
          slot += 1;
          groupNode.leaves.push(leaf);
          leaves.push(leaf);
        });
        topNode.groups.push(groupNode);
      });
      tops.push(topNode);
      if (ti < TREE.length - 1) {
        slot += GAP;
      }
    });
    var totalSlots = slot + GAP;
    var TAU = Math.PI * 2;
    var START = -Math.PI / 2;
    leaves.forEach(function (leaf) {
      leaf.a = START + ((leaf.slot + GAP / 2 + 0.5) / totalSlots) * TAU;
    });
    tops.forEach(function (top) {
      var sumTop = 0;
      var countTop = 0;
      top.groups.forEach(function (group) {
        var sum = 0;
        group.leaves.forEach(function (leaf) {
          sum += leaf.a;
        });
        group.a = sum / group.leaves.length;
        sumTop += sum;
        countTop += group.leaves.length;
      });
      top.a = sumTop / countTop;
    });
    totalEl.textContent = leaves.length;

    var size = 0;
    var dpr = 1;
    var staticLayer = document.createElement("canvas");
    var beamLayer = document.createElement("canvas");
    var colors = {};

    function readColors() {
      var cs = getComputedStyle(root);
      var dark = root.getAttribute("data-theme") === "dark";
      colors = {
        dark: dark,
        blue: cs.getPropertyValue("--blue").trim() || "#5b97ff",
        amber: cs.getPropertyValue("--amber").trim() || "#ffbf3f",
        amberInk: cs.getPropertyValue("--amber-ink").trim() || "#ffc95c",
        ink: cs.getPropertyValue("--ink").trim() || "#e4ecfa",
        faint: cs.getPropertyValue("--faint").trim() || "#66748f",
        panel: dark ? "rgba(8,17,31,0.86)" : "rgba(250,247,239,0.92)",
        ring: dark ? "rgba(110,160,255,0.22)" : "rgba(26,36,56,0.18)",
        ring2: dark ? "rgba(110,160,255,0.09)" : "rgba(26,36,56,0.07)",
        edge: dark ? "rgba(120,170,255,0.20)" : "rgba(29,88,216,0.20)",
        node: dark ? "rgba(150,185,255,0.42)" : "rgba(26,36,56,0.40)",
        rootRed: dark ? "#ff7d8e" : "#d0495c",
        face0: dark ? "rgba(20,48,100,0.55)" : "rgba(255,252,242,0.9)",
        face1: dark ? "rgba(5,10,20,0.2)" : "rgba(232,223,200,0.55)",
        beam: dark ? "91,151,255" : "29,88,216"
      };
    }

    function px(v) {
      return v * size;
    }
    function polar(a, r) {
      var c = size / 2;
      var R = size * 0.46;
      return [c + Math.cos(a) * r * R, c + Math.sin(a) * r * R];
    }

    function resize() {
      var css = canvas.getBoundingClientRect().width;
      if (!css) {
        return;
      }
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      var next = Math.round(css * dpr);
      if (next === size) {
        return;
      }
      size = next;
      canvas.width = canvas.height = size;
      staticLayer.width = staticLayer.height = size;
      beamLayer.width = beamLayer.height = size;
      buildLayers();
      draw();
    }

    // 静态层：屏面、刻度、文件树连线与节点
    function buildLayers() {
      readColors();
      var g = staticLayer.getContext("2d");
      var c = size / 2;
      var R = size * 0.46;
      g.clearRect(0, 0, size, size);
      var face = g.createRadialGradient(c, c, 0, c, c, R);
      face.addColorStop(0, colors.face0);
      face.addColorStop(1, colors.face1);
      g.fillStyle = face;
      g.beginPath();
      g.arc(c, c, R, 0, TAU);
      g.fill();

      g.lineWidth = Math.max(1, dpr * 0.8);
      [0.25, 0.5, 0.75, 1].forEach(function (k) {
        g.strokeStyle = k === 1 ? colors.ring : colors.ring2;
        g.beginPath();
        g.arc(c, c, R * k, 0, TAU);
        g.stroke();
      });
      g.strokeStyle = colors.ring2;
      for (var i = 0; i < 4; i++) {
        var a = (i * Math.PI) / 4;
        g.beginPath();
        g.moveTo(c - Math.cos(a) * R, c - Math.sin(a) * R);
        g.lineTo(c + Math.cos(a) * R, c + Math.sin(a) * R);
        g.stroke();
      }
      // 外圈刻度
      g.strokeStyle = colors.ring;
      for (var d = 0; d < 360; d += 5) {
        var ar = (d * Math.PI) / 180;
        var len = d % 30 === 0 ? R * 0.05 : R * 0.022;
        g.beginPath();
        g.moveTo(c + Math.cos(ar) * R, c + Math.sin(ar) * R);
        g.lineTo(c + Math.cos(ar) * (R - len), c + Math.sin(ar) * (R - len));
        g.stroke();
      }

      // 树的连线：用二次曲线从父节点弯向子节点
      g.strokeStyle = colors.edge;
      g.lineWidth = Math.max(1, dpr * 0.75);
      tops.forEach(function (top) {
        var tp = polar(top.a, top.r);
        g.beginPath();
        g.moveTo(c, c);
        g.lineTo(tp[0], tp[1]);
        g.stroke();
        top.groups.forEach(function (group) {
          var gp = polar(group.a, group.r);
          var ctrl = polar(group.a, top.r);
          g.beginPath();
          g.moveTo(tp[0], tp[1]);
          g.quadraticCurveTo(ctrl[0], ctrl[1], gp[0], gp[1]);
          g.stroke();
          group.leaves.forEach(function (leaf) {
            var lp = polar(leaf.a, leaf.r);
            var lc = polar(leaf.a, group.r);
            g.beginPath();
            g.moveTo(gp[0], gp[1]);
            g.quadraticCurveTo(lc[0], lc[1], lp[0], lp[1]);
            g.stroke();
          });
        });
      });

      // 目录节点
      var s = Math.max(2, size * 0.008);
      tops.forEach(function (top) {
        var tp = polar(top.a, top.r);
        g.fillStyle = colors.blue;
        g.fillRect(tp[0] - s, tp[1] - s, s * 2, s * 2);
        top.groups.forEach(function (group) {
          var gp = polar(group.a, group.r);
          g.strokeStyle = colors.blue;
          g.lineWidth = Math.max(1, dpr);
          g.strokeRect(gp[0] - s * 0.8, gp[1] - s * 0.8, s * 1.6, s * 1.6);
        });
      });
      // 顶层目录名
      g.font = "600 " + Math.round(size * 0.026) + "px ui-monospace, SFMono-Regular, Menlo, monospace";
      g.fillStyle = colors.faint;
      g.textBaseline = "middle";
      tops.forEach(function (top) {
        var tp = polar(top.a, top.r);
        var right = Math.cos(top.a) >= -0.2;
        g.textAlign = right ? "left" : "right";
        g.fillText("/" + top.name, tp[0] + (right ? s * 2.2 : -s * 2.2), tp[1] - s * 2.4);
      });
      // 圆心
      g.fillStyle = colors.amber;
      g.beginPath();
      g.arc(c, c, s * 1.2, 0, TAU);
      g.fill();
      // 叶子节点（暗色底图）
      leaves.forEach(function (leaf) {
        drawLeafGlyph(g, leaf, colors.node, 1);
      });

      // 扫描波束：前沿亮、向后渐隐的扇形
      var b = beamLayer.getContext("2d");
      b.clearRect(0, 0, size, size);
      var span = 1.1;
      var steps = 48;
      for (var k = 0; k < steps; k++) {
        var a0 = -span + (span * k) / steps;
        var a1 = -span + (span * (k + 1)) / steps + 0.004;
        var alpha = Math.pow((k + 1) / steps, 2.2) * (colors.dark ? 0.34 : 0.2);
        b.fillStyle = "rgba(" + colors.beam + "," + alpha.toFixed(3) + ")";
        b.beginPath();
        b.moveTo(c, c);
        b.arc(c, c, R, a0, a1);
        b.closePath();
        b.fill();
      }
      b.strokeStyle = "rgba(" + colors.beam + "," + (colors.dark ? 0.95 : 0.7) + ")";
      b.lineWidth = Math.max(1.2, dpr * 1.4);
      b.beginPath();
      b.moveTo(c, c);
      b.lineTo(c + R, c);
      b.stroke();
    }

    // 叶子图形：普通圆点、隐藏为空心圆、包内容为菱形、系统目录为方块、root 为双圈
    function drawLeafGlyph(g, leaf, color, scale) {
      var p = polar(leaf.a, leaf.r);
      var s = Math.max(1.6, size * 0.0072) * scale;
      var f = leaf.flags;
      g.fillStyle = color;
      g.strokeStyle = color;
      g.lineWidth = Math.max(1, dpr * 0.9 * scale);
      g.beginPath();
      if (f.indexOf("r") >= 0) {
        g.arc(p[0], p[1], s * 1.25, 0, TAU);
        g.stroke();
        g.beginPath();
        g.arc(p[0], p[1], s * 0.5, 0, TAU);
        g.fill();
      } else if (f.indexOf("p") >= 0) {
        g.moveTo(p[0], p[1] - s * 1.3);
        g.lineTo(p[0] + s * 1.3, p[1]);
        g.lineTo(p[0], p[1] + s * 1.3);
        g.lineTo(p[0] - s * 1.3, p[1]);
        g.closePath();
        g.fill();
      } else if (f.indexOf("s") >= 0) {
        g.rect(p[0] - s, p[1] - s, s * 2, s * 2);
        g.fill();
      } else if (f.indexOf("h") >= 0) {
        g.arc(p[0], p[1], s, 0, TAU);
        g.stroke();
      } else {
        g.arc(p[0], p[1], s, 0, TAU);
        g.fill();
      }
    }

    // 动画状态：波束匀速旋转；每轮查询从当前角度起扫满一圈
    var SPEED = TAU / 6.2;
    var clock = 0;
    var sweep = START;
    var qIndex = 0;
    var phase = "scan";
    var scanStart = START;
    var swept = 0;
    var holdUntil = 0;
    var detected = [];
    var lastHit = null;

    function leafRel(leaf) {
      var rel = (leaf.a - scanStart) % TAU;
      return rel < 0 ? rel + TAU : rel;
    }

    function setStatus(done) {
      statusEl.textContent = done ? dyn("done") : dyn("scanning");
      statusEl.classList.toggle("done", done);
    }

    function updateFoot() {
      if (!detected.length) {
        foot.innerHTML = dyn("footEmpty");
        return;
      }
      var blind = detected.filter(function (d) {
        return /[hpsr]/.test(d.leaf.flags);
      }).length;
      foot.innerHTML = dyn("foot").replace("{n}", detected.length).replace("{x}", blind);
    }

    function tagKeys(leaf) {
      var keys = [];
      if (leaf.flags.indexOf("r") >= 0) {
        keys.push("root");
      }
      if (leaf.flags.indexOf("s") >= 0) {
        keys.push("sys");
      }
      if (leaf.flags.indexOf("p") >= 0) {
        keys.push("pkg");
      }
      if (leaf.flags.indexOf("h") >= 0) {
        keys.push("hid");
      }
      if (!keys.length) {
        keys.push("spot");
      }
      return keys.slice(0, 2);
    }

    function addRow(leaf) {
      var li = document.createElement("li");
      li.className = "fresh";
      var dot = document.createElement("span");
      dot.className = "dot";
      var nm = document.createElement("span");
      nm.className = "nm";
      nm.textContent = leaf.name;
      var tg = document.createElement("span");
      tg.className = "tg";
      tagKeys(leaf).forEach(function (k) {
        var t = document.createElement("span");
        t.className = "tag tag-" + k;
        t.setAttribute("data-k", k);
        t.textContent = dyn("tag." + k);
        tg.appendChild(t);
      });
      var pt = document.createElement("span");
      pt.className = "pt";
      // rtl 让过长路径从左侧截断；用 LRM 包裹保证符号方向正确
      pt.textContent = "‎" + leaf.dir + "/‎";
      li.appendChild(dot);
      li.appendChild(nm);
      li.appendChild(tg);
      li.appendChild(pt);
      list.appendChild(li);
      setTimeout(function () {
        li.classList.remove("fresh");
      }, 1400);
      // 列表高度固定时（窄屏）移除最早的行，保持最新结果可见
      while (list.children.length > 1 && list.scrollHeight > list.clientHeight + 2) {
        list.removeChild(list.firstElementChild);
      }
    }

    function startQuery(index, animated) {
      qIndex = index;
      detected = [];
      lastHit = null;
      swept = 0;
      leaves.forEach(function (leaf) {
        leaf.seen = false;
      });
      // 切换期间暂停检测，等列表清空后再从当前角度开始新一轮扫描
      phase = "switch";
      var apply = function () {
        phase = "scan";
        scanStart = sweep;
        queryEl.textContent = dyn(QUERIES[qIndex].key);
        queryEl.classList.remove("swap");
        list.innerHTML = "";
        updateFoot();
        hitsEl.textContent = "0";
        scannedEl.textContent = "0";
        setStatus(false);
      };
      if (animated) {
        queryEl.classList.add("swap");
        Array.prototype.forEach.call(list.children, function (li) {
          li.classList.add("out");
        });
        setTimeout(apply, 380);
      } else {
        apply();
      }
    }

    function step(dt) {
      clock += dt;
      sweep += SPEED * dt;
      if (phase === "scan") {
        swept = Math.min(TAU, sweep - scanStart);
        var q = QUERIES[qIndex];
        var scanned = 0;
        leaves.forEach(function (leaf) {
          if (leafRel(leaf) <= swept) {
            scanned += 1;
            if (!leaf.seen && q.test(leaf)) {
              leaf.seen = true;
              var hit = { leaf: leaf, t: clock };
              detected.push(hit);
              lastHit = hit;
              addRow(leaf);
              hitsEl.textContent = detected.length;
              updateFoot();
            }
          }
        });
        scannedEl.textContent = scanned;
        if (swept >= TAU) {
          phase = "hold";
          holdUntil = clock + 3.2;
          setStatus(true);
        }
      } else if (phase === "hold" && clock >= holdUntil) {
        startQuery((qIndex + 1) % QUERIES.length, true);
      }
    }

    function draw() {
      if (!size) {
        return;
      }
      var c = size / 2;
      ctx.clearRect(0, 0, size, size);
      ctx.drawImage(staticLayer, 0, 0);

      // 波束
      ctx.save();
      ctx.translate(c, c);
      ctx.rotate(sweep);
      ctx.translate(-c, -c);
      ctx.drawImage(beamLayer, 0, 0);
      ctx.restore();

      // 余辉：波束刚扫过的节点短暂变亮
      leaves.forEach(function (leaf) {
        var d = (sweep - leaf.a) % TAU;
        if (d < 0) {
          d += TAU;
        }
        if (d < 0.9) {
          ctx.globalAlpha = 1 - d / 0.9;
          drawLeafGlyph(ctx, leaf, colors.blue, 1.25);
        }
      });
      ctx.globalAlpha = 1;

      // 命中的文件：琥珀色嗅迹 + 光点 + 回波环
      var c0 = [c, c];
      detected.forEach(function (hit) {
        var leaf = hit.leaf;
        var tp = polar(leaf.top.a, leaf.top.r);
        var gp = polar(leaf.group.a, leaf.group.r);
        var lp = polar(leaf.a, leaf.r);
        var gc = polar(leaf.group.a, leaf.top.r);
        var lc = polar(leaf.a, leaf.group.r);
        var age = clock - hit.t;
        ctx.globalAlpha = Math.min(1, age * 3) * 0.55;
        ctx.strokeStyle = colors.amber;
        ctx.lineWidth = Math.max(1.2, dpr * 1.1);
        ctx.beginPath();
        ctx.moveTo(c0[0], c0[1]);
        ctx.lineTo(tp[0], tp[1]);
        ctx.quadraticCurveTo(gc[0], gc[1], gp[0], gp[1]);
        ctx.quadraticCurveTo(lc[0], lc[1], lp[0], lp[1]);
        ctx.stroke();
        ctx.globalAlpha = 0.28;
        ctx.fillStyle = colors.amber;
        ctx.beginPath();
        ctx.arc(lp[0], lp[1], size * 0.022, 0, TAU);
        ctx.fill();
        ctx.globalAlpha = 1;
        drawLeafGlyph(ctx, leaf, colors.amber, 1.5);
        if (age < 1.1) {
          var k = age / 1.1;
          ctx.globalAlpha = 1 - k;
          ctx.strokeStyle = colors.amber;
          ctx.lineWidth = Math.max(1, dpr * 1.2);
          ctx.beginPath();
          ctx.arc(lp[0], lp[1], size * (0.02 + k * 0.06), 0, TAU);
          ctx.stroke();
          ctx.globalAlpha = 1;
        }
      });

      // 最近一次命中的文件名标签
      if (lastHit) {
        var age2 = clock - lastHit.t;
        var alpha = age2 < 1.8 ? 1 : Math.max(0, 1 - (age2 - 1.8) / 0.6);
        if (alpha > 0) {
          var p = polar(lastHit.leaf.a, lastHit.leaf.r);
          var fs = Math.round(size * 0.03);
          ctx.font = "600 " + fs + "px ui-monospace, SFMono-Regular, Menlo, monospace";
          var label = lastHit.leaf.name;
          var w = ctx.measureText(label).width + fs * 0.9;
          var h = fs * 1.6;
          var right = p[0] < c;
          var x = right ? p[0] + fs * 0.9 : p[0] - fs * 0.9 - w;
          var y = p[1] - h / 2;
          x = Math.max(2, Math.min(size - w - 2, x));
          y = Math.max(2, Math.min(size - h - 2, y));
          ctx.globalAlpha = alpha;
          ctx.fillStyle = colors.panel;
          ctx.strokeStyle = colors.amber;
          ctx.lineWidth = Math.max(1, dpr);
          ctx.beginPath();
          if (ctx.roundRect) {
            ctx.roundRect(x, y, w, h, fs * 0.35);
          } else {
            ctx.rect(x, y, w, h);
          }
          ctx.fill();
          ctx.stroke();
          ctx.fillStyle = colors.dark ? colors.amber : colors.amberInk;
          ctx.textAlign = "left";
          ctx.textBaseline = "middle";
          ctx.fillText(label, x + fs * 0.45, y + h / 2 + 1);
          ctx.globalAlpha = 1;
        }
      }
    }

    // 运行控制：离开视口或页面隐藏时暂停
    var running = false;
    var visible = true;
    var rafId = 0;
    var last = 0;
    function frame(ts) {
      if (!running) {
        return;
      }
      var dt = last ? Math.min((ts - last) / 1000, 0.05) : 0;
      last = ts;
      step(dt);
      draw();
      rafId = requestAnimationFrame(frame);
    }
    function updateRunning() {
      var should = visible && !document.hidden && !reduceMotion.matches;
      if (should && !running) {
        running = true;
        last = 0;
        rafId = requestAnimationFrame(frame);
      } else if (!should && running) {
        running = false;
        cancelAnimationFrame(rafId);
      }
    }

    // 减少动态效果：直接展示第一个查询扫完的静态结果
    function renderStatic() {
      startQuery(0, false);
      sweep = START + TAU * 0.92;
      scanStart = START;
      clock = 10;
      var q = QUERIES[0];
      leaves.forEach(function (leaf) {
        if (q.test(leaf)) {
          leaf.seen = true;
          detected.push({ leaf: leaf, t: 0 });
          addRow(leaf);
        }
      });
      list.querySelectorAll("li").forEach(function (li) {
        li.classList.remove("fresh");
      });
      hitsEl.textContent = detected.length;
      scannedEl.textContent = leaves.length;
      updateFoot();
      setStatus(true);
      phase = "static";
      draw();
    }

    startQuery(0, false);
    resize();
    if (reduceMotion.matches) {
      renderStatic();
    }

    if ("ResizeObserver" in window) {
      new ResizeObserver(resize).observe(canvas);
    } else {
      window.addEventListener("resize", resize);
    }
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(function (entries) {
        visible = entries[0].isIntersecting;
        updateRunning();
      }).observe(canvas);
    }
    document.addEventListener("visibilitychange", updateRunning);
    var onMotionChange = function () {
      if (reduceMotion.matches) {
        updateRunning();
        renderStatic();
      } else {
        startQuery(0, false);
        updateRunning();
      }
    };
    if (reduceMotion.addEventListener) {
      reduceMotion.addEventListener("change", onMotionChange);
    }
    listeners.theme.push(function () {
      if (size) {
        buildLayers();
        draw();
      }
    });
    listeners.lang.push(function () {
      queryEl.textContent = dyn(QUERIES[qIndex].key);
      setStatus(phase !== "scan");
      updateFoot();
      list.querySelectorAll(".tag[data-k]").forEach(function (t) {
        t.textContent = dyn("tag." + t.getAttribute("data-k"));
      });
    });
    updateRunning();
  }

  /* ---------------- 性能条形图：按真实耗时等比例回放 ---------------- */
  var benches = Array.prototype.map.call(document.querySelectorAll("[data-bench]"), function (el) {
    var rows = Array.prototype.map.call(el.querySelectorAll(".bars li"), function (li) {
      return {
        li: li,
        t: parseFloat(li.getAttribute("data-t")),
        bar: li.querySelector(".track i"),
        value: li.querySelector(".bv"),
        x: li.querySelector(".bx"),
        done: false
      };
    });
    var max = Math.max.apply(null, rows.map(function (r) { return r.t; }));
    rows.forEach(function (r) {
      r.x.textContent = r.li.getAttribute("data-x");
    });
    return { el: el, rows: rows, max: max, raf: 0, started: false };
  });

  function finishBench(b) {
    b.rows.forEach(function (r) {
      r.bar.style.transform = "scaleX(" + r.t / b.max + ")";
      r.value.textContent = r.t.toFixed(2) + " s";
      r.li.classList.remove("running");
      r.li.classList.add("done");
    });
  }

  function runBench(b) {
    cancelAnimationFrame(b.raf);
    b.started = true;
    if (reduceMotion.matches) {
      finishBench(b);
      return;
    }
    var DURATION = 3.4;
    var begin = 0;
    b.rows.forEach(function (r) {
      r.li.classList.remove("done");
      r.li.classList.add("running");
      r.bar.style.transform = "scaleX(0)";
      r.value.textContent = "0.00 s";
    });
    var tick = function (ts) {
      if (!begin) {
        begin = ts;
      }
      // 模拟时间：最长的一条在 DURATION 秒内走完
      var elapsed = ((ts - begin) / 1000 / DURATION) * b.max;
      var all = true;
      b.rows.forEach(function (r) {
        var v = Math.min(elapsed, r.t);
        r.bar.style.transform = "scaleX(" + (v / b.max).toFixed(4) + ")";
        r.value.textContent = v.toFixed(2) + " s";
        if (v >= r.t) {
          r.li.classList.remove("running");
          r.li.classList.add("done");
        } else {
          all = false;
        }
      });
      if (!all) {
        b.raf = requestAnimationFrame(tick);
      }
    };
    b.raf = requestAnimationFrame(tick);
  }

  if ("IntersectionObserver" in window) {
    var benchObserver = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          var b = benches.filter(function (x) { return x.el === entry.target; })[0];
          if (b && !b.started) {
            runBench(b);
          }
          benchObserver.unobserve(entry.target);
        }
      });
    }, { threshold: 0.35 });
    benches.forEach(function (b) {
      benchObserver.observe(b.el);
    });
  } else {
    benches.forEach(finishBench);
  }
  var replay = document.getElementById("perf-replay");
  if (replay) {
    replay.addEventListener("click", function () {
      benches.forEach(runBench);
    });
  }

  /* ---------------- 下载：芯片识别与最新版本信息 ---------------- */
  function markPrimary(intel) {
    var heroArm = document.querySelector(".btn.dl-arm");
    var heroIntel = document.querySelector(".btn.dl-intel");
    document.querySelector(".dl-card.dl-arm").classList.toggle("primary", !intel);
    document.querySelector(".dl-card.dl-intel").classList.toggle("primary", intel);
    if (intel && heroArm && heroIntel) {
      heroArm.className = "btn btn-ghost dl-arm";
      heroIntel.className = "btn btn-primary dl-intel";
      heroArm.parentNode.insertBefore(heroIntel, heroArm);
      // 主按钮保留下载图标
      var icon = heroArm.querySelector("svg");
      if (icon) {
        heroIntel.insertBefore(icon, heroIntel.firstChild);
      }
    }
  }
  markPrimary(false);
  var detectChip = function () {
    try {
      var gl = document.createElement("canvas").getContext("webgl");
      var info = gl && gl.getExtension("WEBGL_debug_renderer_info");
      var renderer = info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : "";
      if (/Intel|AMD|Radeon/i.test(renderer) && !/Apple/i.test(renderer) && /Mac/i.test(navigator.platform || navigator.userAgent)) {
        markPrimary(true);
      }
    } catch (e) {}
  };
  if ("requestIdleCallback" in window) {
    requestIdleCallback(detectChip, { timeout: 2000 });
  } else {
    setTimeout(detectChip, 600);
  }

  if (window.fetch) {
    fetch("https://api.github.com/repos/wangwanjie/FileHound/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
      .then(function (res) {
        return res.ok ? res.json() : null;
      })
      .then(function (release) {
        if (!release) {
          return;
        }
        if (release.tag_name) {
          var ver = document.querySelector("[data-version]");
          ver.textContent = release.tag_name;
          ver.hidden = false;
        }
        (release.assets || []).forEach(function (asset) {
          var el = document.querySelector('[data-size="' + asset.name + '"]');
          if (el) {
            el.textContent = (asset.size / 1048576).toFixed(1) + " MB";
          }
        });
      })
      .catch(function () {});
  }
})();
