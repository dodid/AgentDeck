.PHONY: test build

test:
	@if [ -x .venv/bin/python ]; then \
		.venv/bin/python -m pytest -q; \
	elif command -v uv >/dev/null 2>&1; then \
		uv run pytest -q; \
	else \
		python3 -m pytest -q; \
	fi

build:
	./scripts/build.sh
