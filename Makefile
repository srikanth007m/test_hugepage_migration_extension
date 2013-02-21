all:
	@make all -C lib

test: all
	@bash run-test.sh

test1g: all
	@bash run-test-1g.sh

clean:
	@make clean -C lib

cleanup: clean
	@rm -rf work/*
	@rm -rf results/*
