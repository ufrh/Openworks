import { LuauState } from 'luau-web';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const state = await LuauState.createAsync();

let compiled = 0;

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const filePath = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      if (entry.name !== 'node_modules') {
        walk(filePath);
      }
    } else if (filePath.endsWith('.lua') || filePath.endsWith('.luau')) {
      state.loadstring(fs.readFileSync(filePath, 'utf8'), filePath, true);
      compiled++;
    }
  }
}

try {
  walk(root + 'src');
  walk(root + 'scripts');

  let code = fs.readFileSync(new URL('./host_math.luau', import.meta.url), 'utf8');
  const paths = [
    'FORM/Features',
    'FORM/SketchBodyProfile',
    'Assembly/GeometryReferences',
    'Assembly/Alignment',
    'Assembly/MechanicalResolver',
    'Assembly/AssemblyLayout',
    'Assembly/ConstraintCompiler',
  ];

  for (const modulePath of paths) {
    const name = modulePath.split('/').at(-1);
    const source = fs
      .readFileSync(root + 'src/shared/' + modulePath + '.lua', 'utf8')
      .replace(/require\(script[^\n]+?\.([A-Za-z]+)\)/g, '$1');

    code += `\nlocal ${name}=(function()\n${source}\nend)()\n`;
  }

  code +=
    '\nlocal spec=(function()\n' +
    fs.readFileSync(new URL('./AssemblyDomain.spec.lua', import.meta.url), 'utf8') +
    '\nend)()\nreturn spec(Alignment,GeometryReferences,MechanicalResolver,AssemblyLayout,ConstraintCompiler)';

  const fn = state.loadstring(code, 'assembly-domain-tests', true);
  console.log({
    compiled,
    domainAssertions: (await fn())[0],
    engineTests: 'not executed; host math doubles only',
  });
} finally {
  state.destroy();
}
