import test from 'node:test';
import assert from 'node:assert/strict';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import ReactMarkdown from 'react-markdown';
import { normalizeMath, remarkPlugins, rehypePlugins } from './markdown.js';

const render = (source) => renderToStaticMarkup(React.createElement(ReactMarkdown,
  { remarkPlugins, rehypePlugins }, normalizeMath(source)));

test('renders the reported average as a display fraction', () => {
  const html = render('**Average**\\\n' + String.raw`[ \text{Average} = \frac{\text{Sum}}{6} = \frac{75}{6} = 12.5 ]`);
  assert.match(html, /<strong>Average<\/strong>/);
  assert.match(html, /katex-display/);
  assert.match(html, /<mfrac>/);
  assert.doesNotMatch(html, /katex-error/);
});

test('supports dollar and TeX delimiters', () => {
  for (const source of [String.raw`$\frac{75}{6}$`, '$$\n\\frac{75}{6}\n$$', String.raw`\(\frac{75}{6}\)`, String.raw`\[\frac{75}{6}\]`]) {
    assert.match(render(source), /<mfrac>/);
  }
});

test('preserves code, links, ordinary brackets and existing math', () => {
  for (const source of ['```text\n[ \\frac{75}{6} ]\n```', '`\\(x\\)`', '    [ \\frac{75}{6} ]', '[documentation](https://example.com)', '[ordinary text]', '$$\n\\frac{75}{6}\n$$']) {
    assert.equal(normalizeMath(source), source);
  }
});

test('invalid math stays visible and untrusted HTML is not executed', () => {
  assert.match(render(String.raw`$\notARealCommand{1}$`), /\\notARealCommand/);
  assert.doesNotMatch(render('<script>alert(1)</script>'), /<script>/);
  assert.doesNotMatch(render(String.raw`$\href{javascript:alert(1)}{click}$`), /href="javascript:/);
});
