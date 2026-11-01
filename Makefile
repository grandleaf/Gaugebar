APP = Gaugebar
SCHEME = Stats

BUILD_PATH = $(PWD)/build
DERIVED_DATA = $(BUILD_PATH)/DerivedData
APP_PATH = "$(DERIVED_DATA)/Build/Products/Release/$(APP).app"

.PHONY: build test test-smc run clean leveldb

# Requires Config/Local.xcconfig. See the README.
build:
	xcodebuild \
		-project Stats.xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=macOS' \
		build

test: test-smc
	xcodebuild test \
		-project Stats.xcodeproj \
		-scheme $(SCHEME) \
		-derivedDataPath $(DERIVED_DATA) \
		-destination 'platform=macOS'

test-smc:
	python3 Kit/scripts/run-smc-tests.py

run: build
	open $(APP_PATH)

clean:
	rm -rf $(BUILD_PATH)

leveldb:
	if [ ! -d $(PWD)/leveldb-source ]; then \
		git clone --recurse-submodules https://github.com/google/leveldb.git leveldb-source; \
	fi
	mkdir -p $(PWD)/leveldb-source/build
	cd $(PWD)/leveldb-source/build && cmake -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" -DCMAKE_BUILD_TYPE=Release .. && cmake --build .
	cp $(PWD)/leveldb-source/build/libleveldb.a $(PWD)/Kit/lldb/libleveldb.a
	rm -rf $(PWD)/leveldb-source
