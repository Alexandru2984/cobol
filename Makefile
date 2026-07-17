PYTHON ?= venv/bin/python
COBC   ?= cobc

.PHONY: build seed test demo deploy clean

build:
	$(COBC) -x -free ledger.cbl sha256.cbl -o ledger.cgi
	$(COBC) -x -free seed.cbl -o seed
	$(COBC) -x -free hello.cbl -o hello.cgi

seed: build
	./seed

test:
	$(PYTHON) -m pytest tests/ -v

demo:
	./run_demo.sh

deploy:
	./deploy.sh

clean:
	rm -f ledger.cgi seed hello.cgi *.o
