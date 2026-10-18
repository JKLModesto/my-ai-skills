#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Diretórios globais onde os agentes buscam skills
TARGET_DIRS=(
  "$HOME/.agents/skills"
  "$HOME/.gemini/config/skills"
  "$HOME/.claude/skills"
)

echo "🔗 Sincronizando AI Skills a partir de: $REPO_DIR"

for target_dir in "${TARGET_DIRS[@]}"; do
  mkdir -p "$target_dir"
done

# 1. Linkar skills universais (pasta skills/)
if [ -d "$REPO_DIR/skills" ]; then
  for skill_path in "$REPO_DIR/skills"/*; do
    [ -d "$skill_path" ] || continue
    skill_name="$(basename "$skill_path")"

    for target_dir in "${TARGET_DIRS[@]}"; do
      dest="$target_dir/$skill_name"
      if [ -L "$dest" ]; then
        rm "$dest"
      elif [ -d "$dest" ]; then
        mv "$dest" "${dest}.bak.$(date +%s)"
        echo "  📦 Backup criado para diretório existente: ${dest}.bak.*"
      fi
      ln -s "$skill_path" "$dest"
      echo "  ✅ [universal] $skill_name -> $dest"
    done
  done
fi

# 2. Linkar skills específicas do Gemini / Antigravity (targets/gemini/)
if [ -d "$REPO_DIR/targets/gemini" ]; then
  for skill_path in "$REPO_DIR/targets/gemini"/*; do
    [ -d "$skill_path" ] || continue
    skill_name="$(basename "$skill_path")"
    dest="$HOME/.gemini/config/skills/$skill_name"

    if [ -L "$dest" ]; then
      rm "$dest"
    elif [ -d "$dest" ]; then
      mv "$dest" "${dest}.bak.$(date +%s)"
    fi
    ln -s "$skill_path" "$dest"
    echo "  ✅ [gemini]    $skill_name -> $dest"
  done
fi

# 3. Linkar skills específicas do Claude (targets/claude/) se usar ~/.claude/skills
if [ -d "$REPO_DIR/targets/claude" ]; then
  for skill_path in "$REPO_DIR/targets/claude"/*; do
    [ -d "$skill_path" ] || continue
    mkdir -p "$HOME/.claude/skills"
    skill_name="$(basename "$skill_path")"
    dest="$HOME/.claude/skills/$skill_name"

    if [ -L "$dest" ]; then
      rm "$dest"
    elif [ -d "$dest" ]; then
      mv "$dest" "${dest}.bak.$(date +%s)"
    fi
    ln -s "$skill_path" "$dest"
    echo "  ✅ [claude]    $skill_name -> $dest"
  done
fi

echo "🚀 Concluído! Suas skills estão centralizadas e ativas."
