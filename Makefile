APP = Gaugebar
SCHEME = Stats

BUILD_PATH = $(PWD)/build
DERIVED_DATA = $(BUILD_PATH)/DerivedData
APP_PATH = "$(DERIVED_DATA)/Build/Products/Release/$(APP).app"
UPSTREAM_URL = https://github.com/exelban/stats

.PHONY: build test test-smc run clean leveldb upstream

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

# Shows what Stats has changed since Gaugebar last merged it. Changes nothing but local tags.
upstream:
	@git remote get-url upstream >/dev/null 2>&1 || git remote add upstream $(UPSTREAM_URL).git
	@git fetch --quiet --tags upstream
	@base=$$(git merge-base HEAD upstream/master); \
	echo "Stats:        $(UPSTREAM_URL)"; \
	echo "Releases:     $(UPSTREAM_URL)/releases"; \
	echo "Last merged:  $$(git describe --tags --abbrev=0 $$base)"; \
	echo "Latest:       $$(git tag --list 'v*' --sort=-v:refname | head -1)"; \
	echo "New commits:  $$(git rev-list --count --no-merges $$base..upstream/master)"; \
	echo; \
	git log --oneline --no-merges $$base..upstream/master

leveldb:
	if [ ! -d $(PWD)/leveldb-source ]; then \
		git clone --recurse-submodules https://github.com/google/leveldb.git leveldb-source; \
	fi
	mkdir -p $(PWD)/leveldb-source/build
	cd $(PWD)/leveldb-source/build && cmake -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" -DCMAKE_BUILD_TYPE=Release .. && cmake --build .
	cp $(PWD)/leveldb-source/build/libleveldb.a $(PWD)/Kit/lldb/libleveldb.a
	rm -rf $(PWD)/leveldb-source
