.PHONY: all server agent shell dashboard test standup

all: server agent shell

server:
	cd server && npm install && npm run typecheck && npm test

agent:
	cd agent && go build -o ../dist/pallet-agent .

shell:
	bash provision/build-shell.sh

dashboard:
	cd dashboard && npm install && npm run build

test: server
	bash scripts/test-api.sh

standup:
	bash scripts/standup-control-plane.sh
