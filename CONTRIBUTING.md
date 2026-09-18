# Contributing to camouflage.nvim

Thank you for your interest in contributing to camouflage.nvim!

## Development Setup

1. Clone the repository:

```bash
git clone https://github.com/zeybek/camouflage.nvim.git
cd camouflage.nvim
```

The GitHub wiki is a repository of its own. `make wiki-update` clones it into
`wiki/`, which is ignored here, or pulls it if it is already there. Skip it if
you are not touching the wiki.

It is deliberately not a submodule: plugin managers clone plugins with their
submodules, so every user would download the wiki, and an install made before
the submodule existed fails to update (#141).

To edit the wiki, commit and push inside `wiki/` (branch `master`):

```bash
make wiki-update   # clone or pull the wiki
cd wiki && $EDITOR Configuration.md && git commit -am "docs: ..." && git push
```

2. Install git hooks for conventional commits:

```bash
./scripts/setup-hooks.sh
```

3. Install development dependencies:

```bash
# For linting
luarocks install luacheck

# For formatting
# Install stylua: https://github.com/JohnnyMorganz/StyLua
```

## Code Style

- Follow the existing code style
- Use [StyLua](https://github.com/JohnnyMorganz/StyLua) for formatting
- Run `make format` before committing
- Run `make lint` to check for issues

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/).

Format: `<type>(<scope>)?: <subject>`

Types:
- `feat` - A new feature
- `fix` - A bug fix
- `docs` - Documentation only changes
- `style` - Code style changes (formatting, etc)
- `refactor` - Code change that neither fixes a bug nor adds a feature
- `perf` - Performance improvement
- `test` - Adding or correcting tests
- `build` - Changes to build system or dependencies
- `ci` - Changes to CI configuration
- `chore` - Other changes

Examples:
- `feat: add new masking style`
- `fix(parser): handle empty values correctly`
- `docs: update README installation section`

## Testing

Run tests with:

```bash
make test
```

Or manually:

```bash
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/amazing-feature`)
3. Make your changes
4. Run tests and linting
5. Commit with a conventional commit message
6. Push to your fork
7. Open a Pull Request

## Reporting Bugs

When reporting bugs, please include:

- Neovim version (`nvim --version`)
- Plugin version or commit hash
- Minimal configuration to reproduce
- Steps to reproduce
- Expected vs actual behavior

## Feature Requests

Feature requests are welcome! Please describe:

- The problem you're trying to solve
- Your proposed solution
- Any alternatives you've considered
