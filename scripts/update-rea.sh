#!/usr/bin/env bash
set -euo pipefail

# Diretório raiz do repositório my-ai-skills
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="$REPO_DIR/skills/reverse-engineer-anything"
MCP_CONFIG="$HOME/.gemini/config/mcp_config.json"

# Versão alvo: se passada como argumento usa ela, senão pega a última do npm ou default 6.7.0
TARGET_VERSION="${1:-}"
if [ -z "$TARGET_VERSION" ]; then
  echo "🔍 Buscando versão mais recente de rea-agents no npm..."
  TARGET_VERSION="$(npm view rea-agents version 2>/dev/null || echo "6.7.0")"
fi

echo "=========================================="
echo "⚡ Atualizando REA (Reverse Engineer Anything)"
echo "   Versão Alvo : $TARGET_VERSION"
echo "   Repositório : $REPO_DIR"
echo "=========================================="

# 1. Baixar pacote e garantir cache local via npx
echo "📦 Baixando/verificando rea-agents@$TARGET_VERSION via npx..."
npx -y "rea-agents@$TARGET_VERSION" --version >/dev/null 2>&1

# 2. Atualizar arquivos da skill no repositório my-ai-skills
echo "🔄 Atualizando arquivos da skill em: $SKILL_DIR"
mkdir -p "$SKILL_DIR"

# Localiza onde o npx descompactou o pacote no cache ~/.npm/_npx
PKG_DIR=$(find "$HOME/.npm/_npx" -type d -path "*/node_modules/rea-agents" 2>/dev/null | while read -r dir; do
  if [ -f "$dir/package.json" ]; then
    v=$(node -e "try { console.log(require('$dir/package.json').version); } catch(e){}" 2>/dev/null || true)
    if [ "$v" = "$TARGET_VERSION" ]; then
      echo "$dir"
      break
    fi
  fi
done)

if [ -n "$PKG_DIR" ] && [ -d "$PKG_DIR/skills/reverse-engineer-anything" ]; then
  cp -r "$PKG_DIR/skills/reverse-engineer-anything/"* "$SKILL_DIR/"
  echo "   ✅ Arquivos da skill copiados com sucesso do pacote v$TARGET_VERSION."
else
  echo "   ℹ️ Pasta de skill empacotada já existente ou mantida do git."
fi

# 3. Atualizar configuração do MCP Server no Gemini / Antigravity
echo "⚙️ Configurando servidor MCP em: $MCP_CONFIG"
mkdir -p "$(dirname "$MCP_CONFIG")"

node -e "
const fs = require('fs');
const file = process.argv[1];
const ver = process.argv[2];

let config = { mcpServers: {} };
if (fs.existsSync(file)) {
  try {
    config = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    console.warn('   ⚠️ Não foi possível fazer parse do JSON existente. Criando nova base.');
  }
}
if (!config.mcpServers) config.mcpServers = {};

config.mcpServers.rea = {
  command: 'npx',
  args: ['-y', 'rea-agents@' + ver, 'mcp']
};

fs.writeFileSync(file, JSON.stringify(config, null, 2) + '\n');
" "$MCP_CONFIG" "$TARGET_VERSION"

echo "   ✅ mcp_config.json atualizado para rea-agents@$TARGET_VERSION."

# 4. Executar script de sincronização de links simbólicos
echo "🔗 Sincronizando links simbólicos nos diretórios dos agentes..."
if [ -x "$REPO_DIR/install.sh" ]; then
  "$REPO_DIR/install.sh"
else
  bash "$REPO_DIR/install.sh"
fi

# 5. Validação final via doctor
echo "🩺 Verificando integridade com o REA Doctor..."
npx -y "rea-agents@$TARGET_VERSION" doctor --client antigravity || true

echo ""
echo "🎉 REA atualizado para v$TARGET_VERSION com sucesso!"
