.PHONY: data test lint deploy clean

CONN ?= opssentinel

data:
	python3 data/generate.py

test:
	python3 -m pytest

lint:
	python3 -m pyflakes data app tests || true
	python3 scripts/check_no_em_dash.py

deploy:
	bash scripts/deploy.sh $(CONN)

clean:
	rm -rf data/generated __pycache__ .pytest_cache
