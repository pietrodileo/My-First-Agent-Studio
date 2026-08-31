import { unified } from 'unified';
import remarkParse from 'remark-parse';
import remarkMath from 'remark-math';
import remarkGfm from 'remark-gfm';
import rehypeKatex from 'rehype-katex';

export const remarkPlugins = [remarkGfm, remarkMath];
export const rehypePlugins = [[rehypeKatex, { trust: false, strict: 'ignore' }]];

const parser = unified().use(remarkParse).use(remarkMath);
const protectedTypes = new Set(['code', 'inlineCode', 'link', 'image', 'linkReference', 'imageReference', 'definition', 'html', 'math', 'inlineMath']);

// Models also emit TeX delimiters, or standalone brackets around LaTeX.
// Normalize only presentation text; keep stored messages and code unchanged.
export function normalizeMath(source = '') {
  const ranges = [];
  function visit(node) {
    if (protectedTypes.has(node.type)) {
      ranges.push([node.position.start.offset, node.position.end.offset]);
    } else {
      node.children?.forEach(visit);
    }
  }
  visit(parser.parse(source));
  function convert(text) {
    return text
      .replace(/\\\[([\s\S]*?)\\\]/g, (_, math) => `\n\n$$\n${math.trim()}\n$$\n\n`)
      .replace(/\\\(([^\n]*?)\\\)/g, (_, math) => `$${math.trim()}$`)
      .replace(/^[ \t]*\[[ \t]*([^\n]+?)[ \t]*\][ \t]*$/gm, (line, math) =>
        /\\(?:frac|text|sqrt|sum|mathrm|mathbf)\b/.test(math)
          ? `\n$$\n${math.trim()}\n$$\n` : line);
  }
  let output = '', cursor = 0;
  for (const [start, end] of ranges) {
    output += convert(source.slice(cursor, start)) + source.slice(start, end);
    cursor = end;
  }
  return output + convert(source.slice(cursor));
}
