import AppKit
import WebKit

/// The note as text an agent can read: compact Markdown, none of the styling.
///
/// Notes are styled HTML, and pasted raw most of the tokens are inline CSS. This
/// walks the RENDERED page instead, so a table a note's own script built is read
/// too. Nothing that carries content is dropped: tables stay tables, links keep
/// their URL, closed <details> and hidden blocks are read, and a diagram keeps its
/// labels. Only presentation goes - styles, scripts, data: image bytes.
enum AgentText {
    static let script = #"""
    (() => {
      const SKIP = new Set(["SCRIPT","STYLE","NOSCRIPT","TEMPLATE","HEAD","META","LINK","BUTTON","INPUT","SELECT","TEXTAREA"]);
      const BLOCK = new Set(["P","SECTION","ARTICLE","HEADER","FOOTER","MAIN","NAV","ASIDE","FIGURE","FIGCAPTION",
                             "DETAILS","SUMMARY","BLOCKQUOTE","DL","DT","DD","ADDRESS","FORM","FIELDSET","CENTER"]);
      // PARA marks a paragraph break and KEEP a newline that must survive as is
      // (code, plain notes). Plain "\n" is a layout break and collapses to one.
      const PARA = "\u0001", KEEP = "\u0002";
      const keep = s => s.replace(/\n/g, KEEP);
      const squash = s => s.replace(/\s+/g, " ");
      const cell = el => inline(el).replace(/\s*\n\s*/g, " ").replace(/\|/g, "\\|").trim();
      // Joins without doubling the space where two spaced pieces meet.
      const join = parts => parts.reduce((a, s) => a.endsWith(" ") && s.startsWith(" ") ? a + s.slice(1) : a + s, "");
      const inline = el => join([...el.childNodes].map(n => walk(n, 0)));

      function svgText(svg) {
        const seen = new Set();
        svg.querySelectorAll("text, title").forEach(t => { const s = squash(t.textContent).trim(); if (s) seen.add(s); });
        return seen.size ? `${PARA}[diagram: ${[...seen].join(" · ")}]${PARA}` : "";
      }

      function table(t) {
        let rows = [...t.rows].map(r => [...r.cells].map(cell));
        if (!rows.length) return "";
        let width = Math.max(...rows.map(r => r.length));
        // A column of icons alone comes out empty in every row: drop it.
        const keep = [...Array(width).keys()].filter(i => rows.some(r => r[i]));
        rows = rows.map(r => keep.map(i => r[i] || ""));
        width = keep.length;
        if (!width) return "";
        // One column is a list of lines; wider is the leanest table Markdown reads:
        // no outer pipes, a bare "-|-" under the header.
        if (width === 1) return PARA + rows.map(r => r[0]).filter(Boolean).join("\n") + PARA;
        const line = r => [...r, ...Array(width - r.length).fill("")].join(" | ");
        const out = [line(rows[0]), Array(width).fill("-").join("|"), ...rows.slice(1).map(line)];
        return PARA + out.join("\n") + PARA;
      }

      function list(el, depth) {
        let i = 0;
        const items = [...el.children].filter(c => c.tagName === "LI").map(li => {
          i += 1;
          const mark = el.tagName === "OL" ? `${i}.` : "-";
          const body = walk(li, depth + 1, true).replace(/[\u0001\n]+/g, "\n").trim();
          return "  ".repeat(depth) + mark + " " + body;
        });
        return depth ? "\n" + items.join("\n") + "\n" : PARA + items.join("\n") + PARA;
      }

      function walk(n, depth, inLi) {
        if (n.nodeType === Node.TEXT_NODE) return squash(n.textContent);
        if (n.nodeType !== Node.ELEMENT_NODE) return "";
        const tag = n.tagName.toUpperCase();
        if (SKIP.has(tag)) return "";
        if (tag === "LI" && inLi) return [...n.childNodes].map(c => walk(c, depth)).join("");
        switch (tag) {
          case "BR": return "\n";
          case "HR": return PARA + "---" + PARA;
          case "SVG": return svgText(n);
          case "CANVAS": { const l = n.getAttribute("aria-label"); return l ? `[chart: ${l}]` : ""; }
          case "IMG": {
            const alt = (n.getAttribute("alt") || "").trim(), src = n.getAttribute("src") || "";
            // An icon beside its own label says nothing the label does not.
            const around = n.closest("td, th, li, p, h1, h2, h3, h4, h5, h6, div, section");
            if (alt && around && squash(around.textContent).includes(alt)) return "";
            if (/^https?:/.test(src)) return `![${alt}](${src})`;
            return alt ? `[image: ${alt}]` : "";
          }
          case "A": {
            const text = inline(n).trim(), href = n.getAttribute("href") || "";
            if (!text) return n.querySelector("img, svg") ? "" : href;
            if (!/^(https?|mailto|noto):/.test(href) || text === href) return text;
            return `[${text}](${href})`;
          }
          case "CODE": { const t = n.textContent; return t.includes("\n") ? keep(t) : "`" + t.trim() + "`"; }
          case "PRE":
            // A plain-text note is shown as one <pre class="plain">: hand it back as is.
            if (n.classList.contains("plain")) return PARA + keep(n.textContent) + PARA;
            return PARA + keep("```\n" + n.textContent.replace(/\n$/, "") + "\n```") + PARA;
          case "TABLE": return table(n);
          case "UL": case "OL": return list(n, depth);
        }
        const h = /^H([1-6])$/.exec(tag);
        if (h) return `${PARA}${"#".repeat(+h[1])} ${inline(n).replace(/[\u0001\n]+/g, " ").trim()}${PARA}`;
        const inner = join([...n.childNodes].map(c => walk(c, depth)));
        if (tag === "BLOCKQUOTE") return PARA + inner.replace(/[\u0001\n]+/g, "\n").trim().split("\n").map(l => "> " + l).join("\n") + PARA;
        if (tag === "TR" || tag === "LI") return "\n" + inner.trim() + "\n";
        if (BLOCK.has(tag)) return PARA + inner + PARA;
        // Anything else is spaced by how the page lays it out: chips set side by
        // side as inline-blocks ran together as one word, and a div is layout more
        // often than a paragraph, so it gets one line break, not two.
        const display = getComputedStyle(n).display;
        if (display.startsWith("inline-")) return " " + inner + " ";
        return display === "inline" || display === "contents" ? inner : "\n" + inner + "\n";
      }

      return walk(document.body, 0)
        .split("\n").map(l => l.replace(/[ \t]+$/, "").replace(/^ (?=\S)/, "")).join("\n")
        .replace(/\n+/g, "\n")
        .replace(/\n?\u0001[\u0001\n]*/g, "\n\n")
        .replace(/\u0002/g, "\n")
        .trim();
    })()
    """#

    /// Title on top, then the body. A rough token count rides along in the toast so
    /// the cost of pasting it is visible before it is pasted.
    @MainActor
    static func copy(title: String, from view: WKWebView?) async -> (Toast.Kind, String) {
        guard let view else { return (.failure, "Nothing to copy yet") }
        do {
            let body = try await view.evaluateJavaScript(script, in: nil, contentWorld: .defaultClient) as? String ?? ""
            let text = "# \(title)\n\n\(body)\n"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return (.success, "Copied for agent: about \(max(1, text.utf8.count / 4)) tokens")
        } catch {
            return (.failure, "Could not read the note: \(error.localizedDescription)")
        }
    }
}
