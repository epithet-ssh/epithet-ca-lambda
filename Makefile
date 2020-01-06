DOCKER_TEST_SSHD_VERSION := 5

.PHONY: all
all: epithet-ca-lambda.zip				## run tests and build binaries

epithet-ca-lambda:					## build linux binary for lambda
	GOOS=linux GOARCH=amd64 go build
	touch -t 200001010101 epithet-ca-lambda

epithet-ca-lambda.zip: epithet-ca-lambda		## build lambda zip 
	zip -X epithet-ca-lambda.zip epithet-ca-lambda

.PHONY: clean
clean:							## clean all local resources
	go clean
	rm -f epithet-*
	
.PHONY: help
help:							## Show this help.
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/##//'
