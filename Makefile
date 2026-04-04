.SUFFIXES:

all:

# runs all the test files.
test:
	nvim --version | head -n 1 && echo ''
	nvim --headless --noplugin -u ./scripts/minimal_init.lua \
		-c "lua require('mini.test').setup()" \
		-c "lua MiniTest.run({ execute = { reporter = MiniTest.gen_reporter.stdout({ group_depth = 1 }) } })"

# installs `mini.nvim`, used for both the tests and documentation.
deps:
	@mkdir -p deps
	git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim

# installs deps before running tests, useful for the CI.
test-ci: deps test

# generates the documentation.
documentation:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "luafile ./scripts/docgen.lua" -c "qa!"

# installs deps before running the documentation generation, useful for the CI.
documentation-ci: deps documentation

# performs a lint check and fixes issues if possible, following the config in `stylua.toml`.
lint:
	stylua .

# installs the repo pre-commit hook that runs `make precommit` before every commit.
precommit-install:
	@mkdir -p .git/hooks
	@printf '#!/usr/bin/env bash\nmake precommit\n' > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "pre-commit hook installed at .git/hooks/pre-commit"

# runs the pre-commit checks: lints staged Lua files and regenerates docs.
precommit:
	@set -eu; \
	staged_lua=$$(git diff --cached --name-only --diff-filter=ACMR -- '*.lua' || true); \
	if [ -n "$$staged_lua" ]; then \
	  if ! command -v stylua >/dev/null 2>&1; then \
	    echo "precommit: stylua not installed; skipping lint" >&2; \
	  else \
	    stylua $$staged_lua; \
	    git add $$staged_lua; \
	  fi; \
	fi; \
	$(MAKE) documentation; \
	git add doc

clean:
	rm -rf deps
