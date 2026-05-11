#!/bin/bash
# Install all LSP servers for Claude Code

set -e

echo "🚀 Installing Claude Code LSP support..."

# PHP (Intelephense)
echo "📦 Installing PHP LSP (Intelephense)..."
npm install -g intelephense

# TypeScript/JavaScript (TypeScript Language Server)
echo "📦 Installing TypeScript/JavaScript LSP..."
npm install -g typescript-language-server typescript

# Vue (Vue Language Server)
echo "📦 Installing Vue LSP..."
npm install -g @vue/language-server

# Verify installation
echo "✅ Verifying LSP binaries..."
intelephense --version || echo "⚠️ Intelephense verification failed"
typescript-language-server --version || echo "⚠️ TypeScript LS verification failed"
vue-language-server --version || echo "⚠️ Vue LS verification failed"

echo ""
echo "✨ LSP installation complete!"
echo "Next step: Run 'export ENABLE_LSP_TOOL=1' to enable LSP"
echo "          Add this line to ~/.zshrc to make it permanent"
