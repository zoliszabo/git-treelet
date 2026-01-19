# git-treelet

Manage external repositories as subdirectories ("treelets") within your main repository, with bidirectional sync support.

## What is git-treelet?

Think of it as an enhanced `git subtree` that:
- Maintains bidirectional sync with external repos
- Filters out metadata commits when pushing
- Allows custom naming for treelets (independent of path)
- Supports author rewriting for privacy
- Works without touching your working tree during operations
- Can be run from any subdirectory (like standard git commands)
- Auto-detects treelet name when run from within treelet directories

**Use case:** You have a monorepo and want to maintain some subdirectories as independent git repositories that can be developed both in the monorepo and standalone.

## Comparison with git submodules and git subtree

| Feature | git submodules | git subtree | git-treelet |
|---------|---------------|-------------|-------------|
| **Integration** | External reference (pointer) | Full copy of history | Full copy of content |
| **Repository size** | Small (just pointer) | Large (includes history) | Medium (content only) |
| **Workflow complexity** | High (requires init/update) | Medium | Low |
| **Bidirectional sync** | Manual | Manual (split required) | Built-in (push/pull/sync) |
| **Working tree safety** | Requires checkout | Modifies during ops | No modification during ops |
| **Metadata commits** | N/A | Preserved in history | Automatically filtered |
| **Author rewriting** | N/A | Manual | Built-in option |
| **Custom naming** | Path = name | Path = reference | Independent from path |
| **Clone simplicity** | Requires --recurse | Just clone | Just clone |
| **Best for** | Independent dependencies | One-time imports | Active bidirectional sync |

**Key differences:**

- **git submodules**: External repositories stay separate (pointer only). Requires explicit initialization and updates. Best when you want to pin specific versions of dependencies.

- **git subtree**: Merges external repository history into your main repository. Good for one-time imports, but bidirectional sync (using `git subtree split`) is complex and preserves all metadata commits.

- **git-treelet**: Designed for active bidirectional development. Automatically filters metadata commits on push, supports author rewriting for privacy, and uses git plumbing to avoid working tree modifications during operations. Best when you want to actively develop code both in the monorepo and as a standalone repository. Particularly useful when working with AI tools / agents on the sub-repository, as they can iterate independently while changes seamlessly sync back to the main project.

## Installation

1. Place the `git-treelet` script in your `PATH`:

   ```bash
   mv git-treelet ~/.local/bin/git-treelet
   chmod +x ~/.local/bin/git-treelet
   ```

2. Ensure `git-filter-repo` is installed:

   ```bash
   pip install git-filter-repo
   ```

3. Use as a git subcommand:

   ```bash
   git treelet add https://github.com/user/lib.git main mylib
   ```

   **Note:** You can also invoke it directly as `git-treelet` if needed, but using the git subcommand form (`git treelet`) is recommended.

## Quick Start

```bash
# Add an external repo as a treelet
git treelet add https://github.com/user/lib.git main mylib

# Make changes in the treelet directory
echo "changes" >> mylib/file.txt
git add mylib/ && git commit -m "Update treelet"

# Push changes back to the external repo
git treelet push mylib

# Pull updates from the external repo
git treelet pull mylib

# Bidirectional sync (pull + push)
git treelet sync mylib

# List all treelets
git treelet list

# Remove treelet configuration (files remain)
git treelet remove mylib
```

**Note:** All commands work from any subdirectory within your repository, just like standard git commands. Additionally, when you're inside a treelet directory (or any of its subdirectories), you can omit the treelet name - it will be auto-detected:

```bash
# From repo root - treelet name required
git treelet push mylib

# From within mylib/ or mylib/src/ - auto-detected
cd mylib
git treelet push     # Automatically detects 'mylib'

cd src/components
git treelet pull     # Still works from nested directories
```

## Commands

### add

Add an external repository as a treelet:

```bash
git treelet add <remote> <ref> <path> [treelet-name]
```

Examples:
```bash
# Add with auto-generated name (mylib)
git treelet add https://github.com/user/lib.git main mylib

# Add with custom name for nested paths
git treelet add https://github.com/user/lib.git main vendor/libs/mylib my-lib

# Add with author rewriting
git treelet add --force-author-name="Bot" --force-author-email="bot@noreply.github.com" \
  https://github.com/user/lib.git main mylib
```

The treelet name is used for git config keys (`treelet.<name>.*`). If not specified, it's derived from the path (e.g., `vendor/libs/mylib` → `vendor-libs-mylib`).

### push

Push local changes to the treelet's remote repository:

```bash
git treelet push [treelet] [--verbose] [--squash]
```

Examples:
```bash
# Push changes (explicit name)
git treelet push mylib

# Push from within treelet directory (auto-detect)
cd mylib && git treelet push

# Push with all commits squashed into one
git treelet push mylib --squash

# Override author for this push
git treelet push --force-author-name="Bot" mylib
```

**Note:**
- Sync/add metadata commits are automatically filtered out
- If run from within a treelet directory, the treelet name can be omitted and will be auto-detected

### pull

Pull changes from the treelet's remote repository:

```bash
git treelet pull [treelet] [--verbose]
```

Examples:
```bash
# Pull changes (explicit name)
git treelet pull mylib

# Pull from within treelet directory (auto-detect)
cd mylib && git treelet pull

# Pull with custom author for the sync commit
git treelet pull --force-author-name="Bot" mylib
```

**Note:**
- Skips pulling if remote hasn't changed
- If run from within a treelet directory, the treelet name can be omitted and will be auto-detected

### sync

Bidirectional sync (pull then push):

```bash
git treelet sync [treelet] [--verbose]
```

Examples:
```bash
# Sync (explicit name)
git treelet sync mylib

# Sync from within treelet directory (auto-detect)
cd mylib && git treelet sync
```

**Note:** If run from within a treelet directory, the treelet name can be omitted and will be auto-detected

### list

List all configured treelets:

```bash
git treelet list
```

Shows treelet names and their configuration.

### config

Get or set treelet configuration:

```bash
# Get configuration
git treelet config get <treelet> <key>

# Set configuration
git treelet config set <treelet> <key> <value>
```

Configuration keys:
- `remote` - Remote repository URL
- `remote-ref` - Remote branch/ref name
- `path` - Local subdirectory path
- `force-author-name` - Author name for commits
- `force-author-email` - Author email for commits
- `last-sync` - Last sync commit SHA (read-only)

Examples:
```bash
# Get the remote URL
git treelet config get mylib remote

# Change the branch
git treelet config set mylib remote-ref develop

# Set author email for privacy
git treelet config set mylib force-author-email "bot@noreply.github.com"
```

### remove

Remove treelet configuration (files remain):

```bash
git treelet remove <treelet>
```

## Options

- `--verbose` - Show detailed operation logs
- `--squash` - Squash all commits into one (push only)
- `--force-author-name=<name>` - Override author name
- `--force-author-email=<email>` - Override author email
- `-h` - Show help message

## How It Works

**Add/Pull:**
- Fetches the remote ref
- Uses git plumbing (`git read-tree`, `git commit-tree`) to merge the tree
- Updates working directory with `git reset --hard`
- Never modifies working tree during operations

**Push:**
- Creates temporary clone and filters to extract treelet history
- Filters out sync/add metadata commits
- Optionally squashes commits or rewrites authors
- Pushes filtered history to remote

**Configuration:**
Stored in git config as `treelet.<name>.*` keys, plus refs under `refs/treelet/<name>/`.

## Requirements

- Git (tested on 2.x)
- `git-filter-repo` for push operations
- Bash 4.x or later

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for development guidelines and testing information.

## License

See [LICENSE](LICENSE) for license information.
