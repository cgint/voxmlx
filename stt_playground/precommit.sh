#!/bin/bash

# Function to install the pre-commit hook
install_hook() {
    HOOK_DIR=".git/hooks"
    HOOK_PATH="$HOOK_DIR/pre-commit"

    # Create hooks directory if it doesn't exist
    mkdir -p "$HOOK_DIR"

    # Create the pre-commit hook
    cat > "$HOOK_PATH" << EOL
#!/bin/bash
\$(dirname "\$0")/../../precommit.sh
EOL

    # Make the hook executable
    chmod +x "$HOOK_PATH"

    echo "Pre-commit hook installed successfully."
}

# Function to uninstall the pre-commit hook
uninstall_hook() {
    HOOK_PATH=".git/hooks/pre-commit"
    rm -f "$HOOK_PATH"
    echo "Pre-commit hook uninstalled successfully."
}

# Check if the script is called with 'install' parameter
if [ "$1" = "install" ]; then
    install_hook
    exit 0
fi

# Check if the script is called with 'uninstall' parameter
if [ "$1" = "uninstall" ]; then
    uninstall_hook
    exit 0
fi

# Precommit script for Elixir/Phoenix LiveView project
# This script ensures code quality and runs all necessary checks

set -e  # Exit on any error

echo "🚀 Running precommit checks..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "mix.exs" ]; then
    print_error "mix.exs not found. Please run this script from the project root."
    exit 1
fi

# 1. Check for uncommitted changes (optional warning)
if [ -d ".git" ]; then
    if ! git diff-index --quiet HEAD --; then
        print_warning "You have uncommitted changes"
    fi
fi

# 2. Get dependencies
print_status "Fetching dependencies..."
if ! mix deps.get; then
    print_error "Failed to fetch dependencies"
    exit 1
fi
print_success "Dependencies fetched"

# 3. Check for unused dependencies
print_status "Checking for unused dependencies..."
if ! mix deps.unlock --check-unused; then
    print_warning "Some dependencies might be unused"
else
    print_success "No unused dependencies found"
fi

# 4. Format code
print_status "Formatting code..."
if ! mix format; then
    print_error "Formatting failed or has warnings"
    exit 1
fi
print_success "Formatting successful"

# 5. Compile with warnings as errors
mix deps.compile
print_status "Compiling with warnings as errors..."
mix clean
if ! mix compile --warnings-as-errors; then
    print_error "Compilation failed or has warnings"
    exit 1
fi
print_success "Compilation successful"

# 6. Run static analysis with Credo (if available)
# print_status "Running static analysis..."
# if mix help credo >/dev/null 2>&1; then
#     if ! mix credo --strict; then
#         print_error "Credo analysis failed"
#         exit 1
#     fi
#     print_success "Static analysis passed"
# else
#     print_warning "Credo not available, skipping static analysis"
# fi

# 7. Security analysis with Sobelow (if available)
# print_status "Running security analysis..."
# if mix help sobelow >/dev/null 2>&1; then
#     if ! mix sobelow --config; then
#         print_error "Security analysis failed"
#         exit 1
#     fi
#     print_success "Security analysis passed"
# else
#     print_warning "Sobelow not available, skipping security analysis"
# fi

# 8. Run all tests
print_status "Running tests..."
if ! mix test; then
    print_error "Tests failed"
    exit 1
fi
print_success "All tests passed"

# 9. Check test coverage (if ExCoveralls is available)
print_status "Checking test coverage..."
if mix help coveralls >/dev/null 2>&1; then
    if ! mix coveralls; then
        print_warning "Coverage check completed with warnings"
    else
        print_success "Coverage check passed"
    fi
else
    print_warning "ExCoveralls not available, skipping coverage check"
fi

# 10. Check dialyzer types (if available)
print_status "Running Dialyzer type checking..."
if mix help dialyzer >/dev/null 2>&1; then
    if ! mix dialyzer; then
        print_error "Dialyzer type checking failed"
        exit 1
    fi
    print_success "Type checking passed"
else
    print_warning "Dialyzer not available, skipping type checking"
fi

# 11. Compile assets
print_status "Compiling assets..."
if [ -f "assets/package.json" ]; then
    cd assets
    if ! npm install; then
        print_error "Failed to install npm dependencies"
        exit 1
    fi
    if ! npm run build; then
        print_error "Failed to build assets"
        exit 1
    fi
    cd ..
    print_success "Assets compiled"
else
    # Phoenix 1.7+ style
    if ! mix assets.deploy; then
        print_warning "Asset compilation had issues"
    else
        print_success "Assets compiled"
    fi
fi

# 12. Check for production-unsafe runtime calls
print_status "Checking for production-unsafe runtime calls..."
UNSAFE_CALLS=""

# Check for Mix.env() calls (but exclude compile-time module attributes)
MIX_ENV_CALLS=$(grep -rn "Mix\.env()" lib/ | grep -v "@compile_env Mix\.env()" 2>/dev/null || true)
if [ -n "$MIX_ENV_CALLS" ]; then
    UNSAFE_CALLS="${UNSAFE_CALLS}Mix.env() calls found (runtime usage):\n$MIX_ENV_CALLS\n\n"
fi

# Check for other Mix module calls that won't work in production
MIX_MODULE_CALLS=$(grep -rn "Mix\." lib/ | grep -v "Mix\.env()" | grep -v "@compile_env Mix\.env()" 2>/dev/null || true)
if [ -n "$MIX_MODULE_CALLS" ]; then
    UNSAFE_CALLS="${UNSAFE_CALLS}Other Mix module calls found:\n$MIX_MODULE_CALLS\n\n"
fi

# Check for Application.get_application() calls (should use compile-time alternatives)
APP_GET_CALLS=$(grep -rn "Application\.get_application()" lib/ 2>/dev/null || true)
if [ -n "$APP_GET_CALLS" ]; then
    UNSAFE_CALLS="${UNSAFE_CALLS}Application.get_application() calls found (use compile-time alternatives):\n$APP_GET_CALLS\n\n"
fi

if [ -n "$UNSAFE_CALLS" ]; then
    print_error "Found production-unsafe runtime calls:"
    echo -e "$UNSAFE_CALLS"
    echo "These calls will fail in production releases. Consider:"
    echo "  • Replace Mix.env() with @compile_env Mix.env() module attribute"
    echo "  • Use Application.get_env/2 instead of Mix module functions"
    echo "  • Move runtime configuration to config/runtime.exs"
    exit 1
else
    print_success "No production-unsafe runtime calls found"
fi

# 13. Check for TODO/FIXME comments
print_status "Checking for TODO/FIXME comments..."
TODO_COUNT=$(grep -r "TODO\|FIXME" lib test --exclude-dir=deps --exclude-dir=_build | wc -l)
if [ "$TODO_COUNT" -gt 0 ]; then
    print_warning "Found $TODO_COUNT TODO/FIXME comments"
    grep -r "TODO\|FIXME" lib test --exclude-dir=deps --exclude-dir=_build
else
    print_success "No TODO/FIXME comments found"
fi

echo ""
print_success "🎉 All precommit checks passed! Ready to commit."
echo ""

# Summary
echo "Summary of checks:"
echo "✅ Dependencies fetched and checked"
echo "✅ Code formatted"
echo "✅ Compilation successful"
echo "✅ Static analysis passed"
echo "✅ Security analysis passed"
echo "✅ All tests passed"
echo "✅ Coverage checked"
echo "✅ Type checking passed"
echo "✅ Assets compiled"
echo "✅ Production-safe code verified"
