# 🧠 My AI Skills

Repositório centralizado para gerenciar minhas **Skills**, instruções, prompts e automações para Agentes e Modelos de IA (Antigravity / Gemini, Claude Code, Codex / OpenAI, Cursor, etc.).

## 📁 Estrutura do Repositório

```text
my-ai-skills/
├── skills/                  # Skills universais (padrão SKILL.md compartilhado entre agentes)
│   └── reverse-engineer-anything/
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
