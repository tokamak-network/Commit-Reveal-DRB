# Copyright 2024 justin
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

-include .env

.PHONY: set-l1fee-mode all test clean deploy help install snapshot format anvil

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
			@echo "Usage:"
			@echo " make deploy [ARGS=...]\n	example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install OpenZeppelin/openzeppelin-contracts --no-commit && forge install Cyfrin/foundry-devops --no-commit

# Update Dependencies
update :; forge update

build :; forge build

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

#################### * scripts ####################

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network thanossepolia,$(ARGS)), --network thanossepolia)
	NETWORK_ARGS := --rpc-url $(THANOS_SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier blockscout --verifier-url https://explorer.thanos-sepolia.tokamak.network/api --etherscan-api-key 11 -vv
endif
ifeq ($(findstring --network sepolia,$(ARGS)), --network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vv
endif


deploy: deploy-drb deploy-consumer-example set-l1fee-mode
# make deploy ARGS="--network thanossepolia"

deploy-drb:
	@forge script script/DeployDRBCoordinator.s.sol:DeployDRBCoordinator $(NETWORK_ARGS)

deploy-consumer-example:
	@forge script script/DeployConsumerExample.s.sol:DeployConsumerExample $(NETWORK_ARGS)

set-l1fee-mode:
	@forge script script/Interactions.s.sol:SetL1FeeCalculation $(NETWORK_ARGS)

three-deposit-activate:
	@forge script script/Interactions.s.sol:ThreeDepositAndActivate $(NETWORK_ARGS)

request-random:
	@forge script script/Interactions.s.sol:ConsumerRequestRandomNumber $(NETWORK_ARGS)

ADDRESS := $()
request-random-with-address:
	@forge script script/Interactions.s.sol:ConsumerRequestRandomNumber $(NETWORK_ARGS) --sig "run(address)" $(ADDRESS)

ROUND := $()

commit:
	@forge script script/Interactions.s.sol:Commit $(NETWORK_ARGS) --sig "run(uint256)" $(ROUND)

reveal:
	@forge script script/Interactions.s.sol:Reveal $(NETWORK_ARGS) --sig "run(uint256)" $(ROUND)

SECOND := $()

increase:
	@forge script script/Interactions.s.sol:IncreaseTime $(NETWORK_ARGS) --sig "run(uint256)" $(SECOND)

refund:
	@forge script script/Interactions.s.sol:Refund $(NETWORK_ARGS) --sig "run(uint256)" $(ROUND)




ROUND_ARG := $()

re-request-round:
	@forge script script/Interactions.s.sol:ReRequestRandomWord $(NETWORK_ARGS)


verfy-drb:
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(uint256,uint256,uint256[3])" 1000000000000000000 10000000000000000 "[200000000000000000,300000000000000000,400000000000000000]") \
	forge verify-contract --constructor-args CONSTRUCTOR_ARGS --verifier blockscout --verifier-url https://explorer.thanos-sepolia.tokamak.network/api --rpc-url $(THANOS_SEPOLIA_URL) $(ADDRESS) DRBCoordinator

DRB := $()

verify-consumer-example:
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(address)" 0xd7142b66a9804315eA8653bF9Af9bBaB958aa5E6) \
	forge verify-contract --constructor-args CONSTRUCTOR_ARGS --verifier blockscout --verifier-url https://explorer.thanos-sepolia.tokamak.network/api --rpc-url $(THANOS_SEPOLIA_URL) $(ADDRESS) DRBCoordinator

#################### * test ####################

test:
	@forge test --nmp test/unit/Prime.t.sol --gas-report --gas-limit 999999999999

test-pietrzak:
	@forge test --mp test/staging/Pietrzak.t.sol --gas-report -vv --gas-limit 999999999999
test-wesolowski:
	@forge test --mp test/staging/Wesolowski.t.sol --gas-report -vv --gas-limit 999999999999
test-getL1Fee:
	@forge test --mp test/unit/GetL1Fee.t.sol -v --gas-report

test-prime:
	@forge test --mp test/unit/Prime.t.sol -vv


#forge verify-contract --constructor-args 0xcC377BD2EA392DC48605bfe0779a638ea4fCf365 --verifier blockscout --verifier-url https://explorer.thanos-sepolia.tokamak.network/api 0xf10Cf5550143850fac7CCF09B36cd4BEE018070D ConsumerExample