.PHONY: test lint format check clean help

NVIM ?= nvim
PLENARY_DIR ?= ~/.local/share/nvim/site/pack/vendor/start/plenary.nvim

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

test: ## Run tests
	@$(NVIM) --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

lint: ## Run luacheck
	@luacheck lua/ --globals vim

format: ## Format code with stylua
	@stylua lua/ tests/ --config-path stylua.toml

format-check: ## Check formatting without changes
	@stylua lua/ tests/ --config-path stylua.toml --check

check: lint format-check ## Run all checks

clean: ## Clean generated files
	@rm -rf *.log

deps: ## Install plenary.nvim for testing
	@if [ ! -d "$(PLENARY_DIR)" ]; then \
		git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR); \
	fi

install-hooks: ## Install git hooks
	@./scripts/setup-hooks.sh
