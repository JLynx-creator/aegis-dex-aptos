.PHONY: test test-move test-sdk test-app build clean
test: test-move test-sdk test-app

test-move:
	./scripts/test.sh

test-sdk:
	cd sdk && npm ci && npm run typecheck && npm test && npm run build

# The app consumes the SDK via file:../sdk, so the SDK must be built first.
test-app: test-sdk
	cd app && npm ci && npm test && \
	VITE_NETWORK=testnet VITE_AEGIS_ADDRESS=0xcafe \
	VITE_TOKENS='[{"symbol":"A","name":"A","address":"0xa1","decimals":8},{"symbol":"B","name":"B","address":"0xb2","decimals":8}]' \
	npm run build

build: test-app

clean:
	rm -rf build testnet_tokens/build sdk/dist sdk/node_modules app/dist app/node_modules
