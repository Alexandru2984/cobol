PYTHON ?= $(shell if [ -x ../current/runtime/bin/python ]; then echo ../current/runtime/bin/python; elif [ -x ../runtime-venv/bin/python ]; then echo ../runtime-venv/bin/python; elif [ -x venv/bin/python ]; then echo venv/bin/python; else echo python3; fi)
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
