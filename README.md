# 🧠 My AI Skills

Repositório centralizado para gerenciar minhas **Skills**, instruções, prompts e automações para Agentes e Modelos de IA (Antigravity / Gemini, Claude Code, Codex / OpenAI, Cursor, etc.).

## 📁 Estrutura do Repositório

```text
my-ai-skills/
├── skills/                  # Skills universais (padrão SKILL.md compartilhado entre agentes)
│   ├── backend-patterns/           # Padrões para Hono, Cloudflare Workers, Express, Supabase e Prisma
│   ├── coding-standards/           # Boas práticas de TypeScript, JavaScript, React e Node.js
│   ├── database-migrations/        # Migrations seguras zero-downtime (PostgreSQL, Prisma, Supabase)
│   ├── docker-patterns/            # Docker, Docker Compose, segurança de containers e Linux
│   ├── frontend-patterns/          # Padrões gerais de UI e arquitetura Frontend
│   ├── hexagonal-architecture/     # Clean Architecture, Ports & Adapters e modularização de arquivos >400 linhas
│   ├── postgres-patterns/          # Otimização de queries PostgreSQL, índices e RLS no Supabase
│   ├── prisma-patterns/            # Boas práticas e armadilhas críticas do Prisma ORM
│   ├── python-patterns/            # Python idiomático, PEP 8, tipagem e boas práticas
│   ├── react-patterns/             # Padrões modernos de React 18/19 (hooks, boundaries, composição)
│   ├── react-performance/          # 70+ regras de otimização React (Vercel Engineering)
│   ├── reverse-engineer-anything/  # Engenharia reversa com REA
│   ├── security-review/            # Checklist de segurança (Zod, RLS Supabase, Secrets, SQLi/XSS)
│   ├── tdd-workflow/               # Fluxo de testes unitários, integração e E2E (Vitest/Playwright)
│   ├── verification-loop/          # Verificação em 6 fases pré-commit/PR (build, tsc, lint, testes)
│   └── vite-patterns/              # Configuração avançada de Vite, env vars, proxy e build
├── targets/                 # Customizações, rules ou skills exclusivas por modelo/ecossistema
│   ├── gemini/              # Específicas para Gemini / Google Antigravity
│   ├── claude/              # Específicas para Claude / Claude Code
│   └── openai/              # Específicas para GPT / Codex
├── templates/               # Templates para criar novas skills rapidamente
│   └── skill-template/
└── install.sh               # Script que cria symlinks para ~/.agents/skills e ~/.gemini/config/skills
```

## 🚀 Como Usar / Instalar em uma Máquina Nova

Clone o repositório e rode o script de instalação para criar os links simbólicos (*symlinks*) automaticamente:

```bash
git clone git@github.com:JKLModesto/my-ai-skills.git ~/Projetos/my-ai-skills
cd ~/Projetos/my-ai-skills
./install.sh
```

Qualquer alteração feita nas skills dentro deste repositório reflete **imediatamente** nos agentes locais (pois estão linkadas via symlink).

## ➕ Como Criar uma Nova Skill

1. Copie o template base para `skills/` (se for universal) ou para `targets/<modelo>/` (se for específica):
   ```bash
   cp -r templates/skill-template skills/minha-nova-skill
   ```
2. Edite o arquivo `skills/minha-nova-skill/SKILL.md` com o nome, descrição e instruções.
3. Rode `./install.sh` para criar o link simbólico nos diretórios dos agentes.
4. Faça o commit e push para o GitHub!
