#!/usr/bin/env node
// Creates a reverse-engineering knowledge base from the skill templates.
// Never overwrites an existing file.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const USAGE = 'Usage: node init-kb.mjs [kb-dir] --product "<Name>" [--git]   (kb-dir defaults to ./re-<product-slug>)';
const TEXT_EXTENSIONS = new Set(['.md', '.csv', '.mmd', '.ts']);

function parseArgs(argv) {
  const options = { git: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--product') options.product = argv[(i += 1)];
    else if (arg === '--git') options.git = true;
    else if (arg === '--help' || arg === '-h') options.help = true;
    else if (!arg.startsWith('--') && !options.dir) options.dir = arg;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  return options;
}

function slugify(text) {
  return text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

function listFiles(dir) {
  const files = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) files.push(...listFiles(full));
    else files.push(full);
  }
  return files;
}

function copyTree(sourceDir, targetDir, replacements, report) {
  for (const source of listFiles(sourceDir)) {
    const target = join(targetDir, relative(sourceDir, source));
    if (existsSync(target)) {
      report.skipped.push(target);
      continue;
    }
    mkdirSync(dirname(target), { recursive: true });
    const extension = source.slice(source.lastIndexOf('.'));
    if (TEXT_EXTENSIONS.has(extension)) {
      let text = readFileSync(source, 'utf8');
      for (const [key, value] of Object.entries(replacements)) text = text.replaceAll(`{{${key}}}`, value);
      writeFileSync(target, text);
    } else {
      writeFileSync(target, readFileSync(source));
    }
    report.created.push(target);
  }
}

// True when dir is the root of its own git repository (not just inside another one).
function isRepoRoot(dir) {
  try {
    const top = execFileSync('git', ['-C', dir, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', stdio: 'pipe' }).trim();
    return realpathSync(top) === realpathSync(dir);
  } catch {
    return false;
  }
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(`${error.message}\n${USAGE}`);
    process.exit(2);
  }
  if (options.help || !options.product) {
    console.error(USAGE);
    process.exit(options.help ? 0 : 2);
  }

  const skillDir = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const kbDir = resolve(options.dir || `re-${slugify(options.product)}`);
  const replacements = {
    PRODUCT: options.product,
    DATE: new Date().toLocaleDateString('en-CA'),
    SLUG: slugify(options.product),
  };
  const report = { created: [], skipped: [] };

  mkdirSync(kbDir, { recursive: true });
  copyTree(join(skillDir, 'templates', 'kb'), kbDir, replacements, report);
  copyTree(join(skillDir, 'templates', 'artifacts'), join(kbDir, '_templates'), {}, report);

  console.log(`Knowledge base: ${kbDir}`);
  console.log(`Created ${report.created.length} files, kept ${report.skipped.length} existing files.`);

  if (options.git) {
    if (isRepoRoot(kbDir)) {
      console.log('The knowledge base is already a git repository.');
    } else {
      execFileSync('git', ['init', '-q', '-b', 'main'], { cwd: kbDir });
      execFileSync('git', ['add', '-A'], { cwd: kbDir });
      try {
        execFileSync('git', ['commit', '-q', '-m', `Create knowledge base for ${options.product}`], { cwd: kbDir, stdio: 'pipe' });
        console.log('Git repository created with an initial commit.');
      } catch {
        // Usually a missing git identity (user.name, user.email). The repository is still usable.
        console.log('Git repository created; the initial commit failed. Set git user.name and user.email, then commit.');
      }
    }
  }

  console.log('Next: fill 00-charter.md, then sandbox/environment.md. STATUS.md lists the next actions.');
}

main();
