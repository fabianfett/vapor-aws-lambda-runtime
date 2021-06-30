EXECUTABLE=Hello
LAMBDA_ZIP=lambda.zip

SWIFT_DOCKER_IMAGE=swift-lambda-builder

build_lambda:
	docker run \
			--rm \
			--volume "$(shell pwd)/../..:/src" \
			--workdir "/src/examples/Hello/" \
			$(SWIFT_DOCKER_IMAGE) \
			swift build --product Hello -c release

package_lambda:
	docker run \
			--rm \
			--volume "$(shell pwd)/../..:/src" \
			--workdir "/src/examples/Hello/" \
			$(SWIFT_DOCKER_IMAGE) \
			scripts/package.sh Hello
