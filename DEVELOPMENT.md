# Development Guide

This document covers development workflows, testing, and contribution guidelines for git-treelet.

## Running Tests

The project includes an automated test suite in `git-treelet-test.sh`:

```bash
# Verbose mode (default)
./git-treelet-test.sh

# Quiet mode (for automation/CI)
./git-treelet-test.sh --quiet
# or
./git-treelet-test.sh -q
```

**Quiet mode** outputs only a single line summary and exits with:
- Exit code `0` if all tests pass
- Exit code `1` if any test fails

This makes it easy for AI agents and CI/CD systems to check test results.

### Test Coverage

The test suite covers:
- Script syntax validation
- Treelet add (importing external repos)
- Treelet list (showing configured treelets)
- Treelet pull (syncing from remote)
- Treelet push (pushing changes to remote)
- Treelet remove (cleanup)

All tests run in `test-treelet-tmp/` and clean up automatically.

## Project Structure

```
git-treelet          # Main executable script
git-treelet-test.sh  # Test suite
README.md            # User documentation
DEVELOPMENT.md       # This file
CLAUDE.md            # Guidance for Claude Code
```

## Making Changes

### Adding New Commands

1. Add command parsing in the "Parse Commands" section (around line 132)
2. Update the error message with valid commands (around line 155)
3. Add to help text (around line 185)
4. Implement the command handler before the final error (line 910)

### Modifying Sync Logic

**Important constraints:**
- Never use commands that modify working tree during operations
- Use `git commit-tree` + `git update-ref` for commits
- All operations use git plumbing commands
- Respect `set -euo pipefail` - ensure `log()` calls don't cause exits

### Testing New Features

1. Add test function to `git-treelet-test.sh`
2. Follow the pattern: `test_start` → operations → `pass`/`fail`
3. Use helper function `init_test_repo` for creating test repos
4. Always `cd ..` back to `$TEST_DIR` at the end
5. Run `./git-treelet-test.sh -q` to verify all tests pass

## Architecture Notes

### Configuration Storage

Git config keys: `treelet.<name>.*`
- `remote` - Remote repository URL
- `remote-ref` - Remote branch/ref
- `path` - Local subdirectory path
- `last-sync` - Last sync commit SHA
- `force-author-name` - Author name override
- `force-author-email` - Author email override

Git refs: `refs/treelet/<name>/*`
- `remote` - Tracks last known remote state
- `split` - Working ref for push filtering
- `temp` - Temporary fetch target

### Critical Functions

**`log()` function (line 18):**
```bash
log() { $VERBOSE && echo "$1" || true; }
```
Must always return success due to `set -euo pipefail`. Use for progress messages only.

**Config helpers (lines 24-83):**
- `treelet_config_get` - Read config value
- `treelet_config_set` - Write config value (idempotent)
- `treelet_config_validate_key` - Validate key name
- `load_treelet_config` - Load all config for a treelet

**Validation helpers (lines 89-127):**
- `require_git_repo` - Ensure in git repo
- `require_clean_working_tree` - Ensure no uncommitted changes
- `require_path_not_exists` - Validate path doesn't exist (for add)
- `require_treelet_configured` - Ensure treelet is configured

### Push Implementation

The push command (lines 643-873) is the most complex:

1. Check for local changes (`git diff --quiet`)
2. Create temporary clone with `git clone --no-hardlinks`
3. Filter with `git-filter-repo` to extract treelet history
4. Filter out sync/add metadata commits by checking commit messages
5. Optionally squash commits
6. Optionally rewrite author info
7. Push to remote
8. Update tracking refs

**Key insight:** Sync/add commits contain metadata like `Treelet-Sync:` or `Treelet-Add:` in the commit message. These are filtered out before pushing to keep remote history clean.

## Code Style

- Use bash 4.x features
- Always quote variables: `"$VAR"`
- Use `[[ ]]` for conditionals
- Prefer `git rev-parse` over parsing git output
- Use descriptive variable names in UPPER_CASE for globals
- Add comments for non-obvious logic

## Testing Checklist

Before submitting changes:

- [ ] Run `./git-treelet-test.sh -q` - all tests pass
- [ ] Run `bash -n git-treelet` - no syntax errors
- [ ] Test with real repos if making significant changes
- [ ] Update README.md if changing user-facing behavior
- [ ] Update this file if changing architecture

## Performance Considerations

- **Push creates full temporary clone** - Can be slow for large repos (hundreds of MB+)
- **git-filter-repo is fast** - Written in Python, efficiently rewrites history
- **Early exits save time**:
  - Pull skips if remote unchanged (checks commit SHA)
  - Push skips if no local changes (uses `git diff --quiet`)
  - Push skips if only metadata commits found

## Common Development Tasks

### Adding a new configuration key

1. Add to `treelet_config_validate_key` validation
2. Document in README.md config section
3. Use with `treelet_config_get`/`treelet_config_set`

### Debugging test failures

```bash
# Run verbose mode to see what's happening
./git-treelet-test.sh

# Inspect test repo (it's deleted after tests)
# Modify cleanup() in test file to skip deletion
```

### Testing with git-filter-repo

The push test requires `git-filter-repo`. Install with:
```bash
pip install git-filter-repo
```

Without it, the push test is skipped automatically.
