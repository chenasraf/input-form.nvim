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

# installs the lefthook-managed git hooks defined in `lefthook.yml`.
hooks-install:
	@command -v lefthook >/dev/null 2>&1 || { \
	  echo "hooks-install: lefthook is not installed (brew install lefthook)" >&2; \
	  exit 1; \
	}
	@lefthook install

# runs the lefthook pre-commit jobs on demand, outside of git.
precommit:
	@lefthook run pre-commit

clean:
	rm -rf deps
