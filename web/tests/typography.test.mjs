import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import postcss from "postcss";

test("uses local system typography and readable minimum text sizes", async () => {
  const css = await readFile(new URL("../app/globals.css", import.meta.url), "utf8");
  const root = postcss.parse(css);
  assert.match(css, /--font-ui: -apple-system, BlinkMacSystemFont, "PingFang SC"/);
  assert.match(css, /font-variant-numeric: tabular-nums/);
  assert.doesNotMatch(css, /Georgia|Songti SC|@font-face|fonts\.googleapis/);
  root.walkDecls("font-size", (declaration) => {
    if (/^\d+px$/.test(declaration.value)) assert.ok(parseInt(declaration.value) >= 12, declaration.toString());
  });
  assert.match(css, /input, select, textarea \{ font-size: 16px; font-weight: 400; \}/);
  assert.match(css, /\.hero h1, \.page-heading h1 \{ font-size: 24px; \}/);
});
