@default:
    just --list --justfile {{source_file()}}

build:
    forge build

test:
    forge test

clean:
    forge clean
