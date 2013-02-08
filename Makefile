all:
	@make all -C lib

test: all
	@bash run-test.sh

clean:
	@make clean -C lib

cleanup: clean
	@rm -rf work/*
	@rm -rf results/*
