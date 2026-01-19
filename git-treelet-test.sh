#!/bin/bash
set -euo pipefail

# Parse arguments
QUIET_MODE=false
if [[ "${1:-}" == "--quiet" ]] || [[ "${1:-}" == "-q" ]]; then
    QUIET_MODE=true
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test directory
TEST_DIR="$(pwd)/test-treelet-tmp"
SCRIPT="$(pwd)/git-treelet"

# Cleanup function
cleanup() {
    if [ -d "$TEST_DIR" ]; then
        rm -rf "$TEST_DIR"
    fi
}

# Setup test environment
setup() {
    cleanup
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
}

# Test helper functions
pass() {
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${GREEN}✓${NC} $1"
    fi
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    if [ "$QUIET_MODE" = false ]; then
        echo -e "${RED}✗${NC} $1"
        echo -e "  ${RED}Error:${NC} $2"
    fi
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$QUIET_MODE" = false ]; then
        echo -e "\n${YELLOW}Test $TESTS_RUN:${NC} $1"
    fi
}

# Initialize a test repo
init_test_repo() {
    local repo_name=$1
    mkdir -p "$repo_name"
    cd "$repo_name"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "Initial" > README.md
    git add README.md
    git commit -q -m "Initial commit"
    cd ..
}

#############################################
# Tests
#############################################

test_script_syntax() {
    test_start "Script has valid bash syntax"

    if bash -n "$SCRIPT" 2>/dev/null; then
        pass "Script syntax is valid"
    else
        fail "Script syntax" "Bash syntax errors detected"
    fi
}

test_treelet_add() {
    test_start "Treelet add command imports external repo"

    # Create remote repo
    init_test_repo "remote-lib"
    cd remote-lib
    # Allow pushes to checked out branch
    git config receive.denyCurrentBranch updateInstead
    mkdir src
    echo "library code" > src/lib.js
    git add src
    git commit -q -m "Add library"
    cd ..

    # Create monorepo
    init_test_repo "monorepo"
    cd monorepo

    # Add treelet
    if "$SCRIPT" add ../remote-lib/.git master mylib > /dev/null 2>&1; then
        if [ -d "mylib" ] && [ -f "mylib/src/lib.js" ]; then
            local remote=$(git config --get treelet.mylib.remote || echo "")
            local path=$(git config --get treelet.mylib.path || echo "")

            if [ "$remote" = "../remote-lib/.git" ] && [ "$path" = "mylib" ]; then
                pass "Treelet add imports external repo correctly"
            else
                fail "Treelet add" "Config not saved correctly"
            fi
        else
            fail "Treelet add" "Files not imported"
        fi
    else
        fail "Treelet add" "Command failed"
    fi

    cd ..
}

test_treelet_list() {
    test_start "Treelet list shows configured treelets"

    cd monorepo

    if "$SCRIPT" list | grep -q "mylib"; then
        pass "Treelet list shows configured treelets"
    else
        fail "Treelet list" "Doesn't show treelet"
    fi

    cd ..
}

test_treelet_pull() {
    test_start "Treelet pull syncs changes from remote"

    # Make change in remote
    cd remote-lib
    echo "updated" >> src/lib.js
    git add src
    git commit -q -m "Update library"
    cd ..

    # Pull in monorepo
    cd monorepo
    if "$SCRIPT" pull mylib > /dev/null 2>&1; then
        if grep -q "updated" mylib/src/lib.js 2>/dev/null; then
            pass "Treelet pull syncs changes from remote"
        else
            fail "Treelet pull" "Changes not synced"
        fi
    else
        fail "Treelet pull" "Command failed"
    fi

    cd ..
}

test_treelet_push() {
    test_start "Treelet push sends changes to remote"

    # Skip if git-filter-repo not available
    if ! command -v git-filter-repo >/dev/null 2>&1; then
        if [ "$QUIET_MODE" = false ]; then
            echo "  Skipped: git-filter-repo not installed"
        fi
        return
    fi

    cd monorepo

    # Make local change
    echo "local change" >> mylib/src/lib.js
    git add mylib
    git commit -q -m "Update treelet"

    # Push
    if "$SCRIPT" push mylib > /dev/null 2>&1; then
        # Check remote has the change
        cd ../remote-lib
        if grep -q "local change" src/lib.js 2>/dev/null; then
            pass "Treelet push sends changes to remote"
        else
            fail "Treelet push" "Changes not pushed to remote"
        fi
        cd ../monorepo
    else
        fail "Treelet push" "Command failed"
    fi

    cd ..
}

test_treelet_remove() {
    test_start "Treelet remove cleans up configuration"

    cd monorepo

    "$SCRIPT" remove mylib > /dev/null 2>&1

    if ! git config --get-regexp "^treelet\.mylib\." >/dev/null 2>&1; then
        # Check files still exist
        if [ -d "mylib" ]; then
            pass "Treelet remove cleans up config but keeps files"
        else
            fail "Treelet remove" "Files were deleted"
        fi
    else
        fail "Treelet remove" "Config still exists"
    fi

    cd ..
}

test_treelet_subdirectory() {
    test_start "Commands work from subdirectories"

    # Create remote repo
    init_test_repo "remote-subdir"
    cd remote-subdir
    git config receive.denyCurrentBranch updateInstead
    echo "content" > file.txt
    git add file.txt
    git commit -q -m "Add content"
    REMOTE_URL=$(pwd)
    REMOTE_BRANCH=$(git symbolic-ref --short HEAD)
    cd ..

    # Create parent repo
    init_test_repo "parent-subdir"
    cd parent-subdir

    # Create a subdirectory
    mkdir -p some/nested/dir
    echo "other content" > some/nested/dir/file.txt
    git add some/nested/dir/file.txt
    git commit -q -m "Add nested content"

    # Try to add treelet from subdirectory
    cd some/nested/dir
    if "$SCRIPT" add "$REMOTE_URL" "$REMOTE_BRANCH" sublib > /dev/null 2>&1; then
        # Go back to root to verify
        cd ../../..
        if [ -d "sublib" ] && [ -f "sublib/file.txt" ]; then
            # Now test other commands from subdirectory
            cd some/nested/dir

            # Test list command
            if "$SCRIPT" list > /dev/null 2>&1; then
                # Test pull command (should say up-to-date)
                if "$SCRIPT" pull sublib > /dev/null 2>&1; then
                    cd ../../..
                    pass "Commands work from subdirectories"
                else
                    cd ../../..
                    fail "Subdirectory test" "Pull failed from subdirectory"
                fi
            else
                cd ../../..
                fail "Subdirectory test" "List failed from subdirectory"
            fi
        else
            fail "Subdirectory test" "Treelet not added correctly from subdirectory"
        fi
    else
        cd ../../..
        fail "Subdirectory test" "Add failed from subdirectory"
    fi

    cd ..
}

test_treelet_autodetect() {
    test_start "Auto-detect treelet name from current directory"

    # Create remote repo
    init_test_repo "remote-autodetect"
    cd remote-autodetect
    git config receive.denyCurrentBranch updateInstead
    echo "content" > file.txt
    git add file.txt
    git commit -q -m "Add content"
    REMOTE_URL=$(pwd)
    REMOTE_BRANCH=$(git symbolic-ref --short HEAD)
    cd ..

    # Create parent repo
    init_test_repo "parent-autodetect"
    cd parent-autodetect

    # Add treelet from repo root
    "$SCRIPT" add "$REMOTE_URL" "$REMOTE_BRANCH" mylib > /dev/null 2>&1

    # Test push without specifying treelet name from within treelet directory
    echo "change" >> mylib/file.txt
    git add mylib && git commit -q -m "Update"

    cd mylib
    if "$SCRIPT" push > /dev/null 2>&1; then
        # Test pull without specifying treelet name
        cd ..
        cd mylib
        if "$SCRIPT" pull > /dev/null 2>&1; then
            # Test from nested subdirectory within treelet
            mkdir -p subdir
            cd subdir
            if "$SCRIPT" list > /dev/null 2>&1; then
                cd ../..
                pass "Auto-detect works from treelet directory and subdirectories"
            else
                cd ../..
                fail "Auto-detect test" "List failed from nested subdirectory"
            fi
        else
            cd ..
            fail "Auto-detect test" "Pull failed with auto-detection"
        fi
    else
        cd ..
        fail "Auto-detect test" "Push failed with auto-detection"
    fi

    cd ..
}

#############################################
# Run all tests
#############################################

main() {
    if [ "$QUIET_MODE" = false ]; then
        echo "================================================"
        echo "  git-treelet Test Suite"
        echo "================================================"

        # Check dependencies
        if ! command -v git-filter-repo >/dev/null 2>&1; then
            echo -e "${YELLOW}Warning:${NC} git-filter-repo not installed, push test will be skipped"
        fi
    fi

    setup

    # Run tests
    test_script_syntax
    test_treelet_add
    test_treelet_list
    test_treelet_pull
    test_treelet_push
    test_treelet_remove
    test_treelet_subdirectory
    test_treelet_autodetect

    # Cleanup
    cd "$(dirname "$TEST_DIR")"
    cleanup

    # Summary
    if [ "$QUIET_MODE" = false ]; then
        echo ""
        echo "================================================"
        echo "  Test Summary"
        echo "================================================"
        echo -e "Total:  $TESTS_RUN"
        echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"

        if [ $TESTS_FAILED -gt 0 ]; then
            echo -e "${RED}Failed: $TESTS_FAILED${NC}"
        else
            echo -e "\n${GREEN}All tests passed!${NC}"
        fi
    else
        # Quiet mode: minimal output
        if [ $TESTS_FAILED -gt 0 ]; then
            echo "FAILED: $TESTS_FAILED/$TESTS_RUN tests failed"
        else
            echo "PASSED: All $TESTS_RUN tests passed"
        fi
    fi

    # Exit code based on test results
    if [ $TESTS_FAILED -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run tests
main
