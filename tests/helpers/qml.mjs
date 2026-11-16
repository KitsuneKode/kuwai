// Execute production QML JavaScript functions with explicit synthetic boundary adapters.
import { readFileSync } from 'node:fs';
export function functions(path, names, scope) {
  const source = readFileSync(new URL('../../' + path, import.meta.url), 'utf8');
  const bodies = names.map(name => {
    const start = source.indexOf('function ' + name + '(');
    if (start < 0) throw new Error('Missing production function ' + name);
    let depth = 0;
    for (let i = source.indexOf('{', start); i < source.length; i++) {
      if (source[i] === '{') depth++;
      else if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
    }
    throw new Error('Unclosed function ' + name);
  }).join('\n');
  Object.assign(scope, new Function('scope', 'with(scope) { ' + bodies + '; return {' + names.join(',') + '}; }')(scope));
  scope.root = scope;
  return scope;
}
